import Foundation
import XCTest
@testable import Diald

@MainActor
final class PushRegistrationLifecycleTests: XCTestCase {
    private let installationID = UUID(uuidString: "550d5a6b-7248-49da-a4dc-92db45608c07")!
    private let accountA = PushIdentity(principalID: "account-a", accessToken: "token-a")
    private let accountB = PushIdentity(principalID: "account-b", accessToken: "token-b")

    func testTokenBeforeSignInIsRetainedThenRegisteredOnActivation() async {
        let identity = FakePushIdentityProvider()
        let transport = FakePushRegistrationTransport()
        let registrar = FakeRemoteNotificationRegistrar()
        let lifecycle = makeLifecycle(identity: identity, transport: transport, registrar: registrar)

        await lifecycle.receivedDeviceToken(Data([0x01]))
        XCTAssertTrue(transport.calls.isEmpty)

        identity.identity = accountA
        await lifecycle.activate(isAuthorized: true)

        XCTAssertEqual(transport.calls, [.register(accountA, installationID, Data([0x01]))])
        XCTAssertEqual(registrar.registrationCount, 1)
    }

    func testActivationBeforeTokenWaitsForCallback() async {
        let identity = FakePushIdentityProvider(identity: accountA)
        let transport = FakePushRegistrationTransport()
        let registrar = FakeRemoteNotificationRegistrar()
        let lifecycle = makeLifecycle(identity: identity, transport: transport, registrar: registrar)

        await lifecycle.activate(isAuthorized: true)
        XCTAssertTrue(transport.calls.isEmpty)
        XCTAssertEqual(registrar.registrationCount, 1)

        await lifecycle.receivedDeviceToken(Data([0x00, 0xff]))
        XCTAssertEqual(transport.calls, [.register(accountA, installationID, Data([0x00, 0xff]))])
    }

    func testForegroundRefreshRequestsAPNsAndIdempotentlyRegistersLatestToken() async {
        let identity = FakePushIdentityProvider(identity: accountA)
        let transport = FakePushRegistrationTransport()
        let registrar = FakeRemoteNotificationRegistrar()
        let lifecycle = makeLifecycle(identity: identity, transport: transport, registrar: registrar)

        await lifecycle.activate(isAuthorized: true)
        await lifecycle.receivedDeviceToken(Data([0x0a]))
        await lifecycle.refreshRegistration(isAuthorized: true)

        XCTAssertEqual(registrar.registrationCount, 2)
        XCTAssertEqual(
            transport.calls,
            [
                .register(accountA, installationID, Data([0x0a])),
                .register(accountA, installationID, Data([0x0a]))
            ]
        )
    }

    func testRepeatedIdenticalCallbackIsSafeAndIdempotentAtTransportBoundary() async {
        let identity = FakePushIdentityProvider(identity: accountA)
        let transport = FakePushRegistrationTransport()
        let lifecycle = makeLifecycle(
            identity: identity,
            transport: transport,
            registrar: FakeRemoteNotificationRegistrar()
        )
        await lifecycle.activate(isAuthorized: true)

        await lifecycle.receivedDeviceToken(Data([0x01]))
        await lifecycle.receivedDeviceToken(Data([0x01]))

        XCTAssertEqual(transport.calls.count, 2)
        XCTAssertEqual(transport.calls[0], transport.calls[1])
    }

    func testDeactivateAttemptsUnregisterAndClearsIdentityEvenOnFailure() async {
        let identity = FakePushIdentityProvider(identity: accountA)
        let transport = FakePushRegistrationTransport()
        transport.unregisterError = TestError.expected
        var errors: [TestError] = []
        let lifecycle = makeLifecycle(
            identity: identity,
            transport: transport,
            registrar: FakeRemoteNotificationRegistrar(),
            errorHandler: { error in
                if let error = error as? TestError { errors.append(error) }
            }
        )
        await lifecycle.activate(isAuthorized: true)

        await lifecycle.deactivate()

        XCTAssertEqual(transport.calls, [.unregister(accountA, installationID)])
        XCTAssertNil(lifecycle.identity)
        XCTAssertEqual(errors, [.expected])
    }

    func testUnregisterRunsBeforeAuthCredentialsAreInvalidated() async throws {
        let identity = FakePushIdentityProvider(identity: accountA)
        let transport = FakePushRegistrationTransport()
        let lifecycle = makeLifecycle(
            identity: identity,
            transport: transport,
            registrar: FakeRemoteNotificationRegistrar()
        )
        await lifecycle.activate(isAuthorized: true)
        var events: [String] = []
        transport.eventHandler = { events.append($0) }

        let auth = AuthClient()
        auth.beforeSessionInvalidation = { await lifecycle.deactivate() }
        _ = try await auth.performSessionInvalidatingOperation {
            events.append("invalidate")
            return true
        }

        XCTAssertEqual(events, ["unregister", "invalidate"])
    }

    func testAccountSwitchUnregistersAThenRegistersBWithSameInstallation() async {
        let identity = FakePushIdentityProvider(identity: accountA)
        let transport = FakePushRegistrationTransport()
        let lifecycle = makeLifecycle(
            identity: identity,
            transport: transport,
            registrar: FakeRemoteNotificationRegistrar()
        )
        await lifecycle.activate(isAuthorized: true)
        await lifecycle.receivedDeviceToken(Data([0xaa]))

        await lifecycle.deactivate()
        identity.identity = accountB
        await lifecycle.activate(isAuthorized: true)

        XCTAssertEqual(
            transport.calls,
            [
                .register(accountA, installationID, Data([0xaa])),
                .unregister(accountA, installationID),
                .register(accountB, installationID, Data([0xaa]))
            ]
        )
    }

    func testFailedUnregisterDoesNotPreventLaterAccountRebind() async {
        let identity = FakePushIdentityProvider(identity: accountA)
        let transport = FakePushRegistrationTransport()
        let lifecycle = makeLifecycle(
            identity: identity,
            transport: transport,
            registrar: FakeRemoteNotificationRegistrar()
        )
        await lifecycle.activate(isAuthorized: true)
        await lifecycle.receivedDeviceToken(Data([0xbb]))
        transport.unregisterError = TestError.expected

        await lifecycle.deactivate()
        identity.identity = accountB
        await lifecycle.activate(isAuthorized: true)

        XCTAssertEqual(transport.calls.last, .register(accountB, installationID, Data([0xbb])))
    }

    func testDeniedAuthorizationChecksWithoutRegisteringOrPrompting() async {
        let identity = FakePushIdentityProvider(identity: accountA)
        let transport = FakePushRegistrationTransport()
        let registrar = FakeRemoteNotificationRegistrar(authorizationAllowsRegistration: false)
        let lifecycle = makeLifecycle(identity: identity, transport: transport, registrar: registrar)

        await lifecycle.activate(isAuthorized: false)
        await lifecycle.refreshRegistration(isAuthorized: false)

        XCTAssertEqual(registrar.authorizationCheckCount, 0)
        XCTAssertEqual(registrar.registrationCount, 0)
        XCTAssertTrue(transport.calls.isEmpty)
    }

    func testSessionInvalidationHooksRunInOrderAndRestoreAfterFailure() async throws {
        let auth = AuthClient()
        var events: [String] = []
        auth.beforeSessionInvalidation = { events.append("before") }
        auth.afterSessionInvalidationFailure = { events.append("restore") }

        _ = try await auth.performSessionInvalidatingOperation {
            events.append("invalidate")
            return true
        }
        XCTAssertEqual(events, ["before", "invalidate"])

        events = []
        do {
            let _: Void = try await auth.performSessionInvalidatingOperation {
                events.append("invalidate")
                throw TestError.expected
            }
            XCTFail("Expected invalidation to fail")
        } catch {
            XCTAssertEqual(error as? TestError, .expected)
        }
        XCTAssertEqual(events, ["before", "invalidate", "restore"])
    }

    func testAPISignOutRunsInvalidationHooksAndPreservesFailedSession() async {
        let store = TestSessionStore()
        let auth = AuthClient(sessionStore: store)
        var events: [String] = []
        auth.beforeSessionInvalidation = { events.append("unbind") }
        auth.afterSessionInvalidationFailure = { events.append("restore") }
        store.shouldFail = true
        let failed = await auth.signOut()
        XCTAssertFalse(failed)
        XCTAssertEqual(events, ["unbind", "restore"])
        store.shouldFail = false
        events = []
        let succeeded = await auth.signOut()
        XCTAssertTrue(succeeded)
        XCTAssertEqual(events, ["unbind"])
        XCTAssertEqual(auth.state, .signedOut)
    }

    func testInstallationIDIsStableAndCorruptValueIsReplaced() throws {
        let store = FakeInstallationIDStore()
        let provider = KeychainPushInstallationIDProvider(store: store)

        let first = try provider.installationID()
        XCTAssertEqual(first, try provider.installationID())
        XCTAssertEqual(store.values[KeychainPushInstallationIDProvider.account], first.uuidString.lowercased())

        store.values[KeychainPushInstallationIDProvider.account] = "not-a-uuid"
        let replacement = try provider.installationID()
        XCTAssertNotEqual(replacement, first)
        XCTAssertEqual(
            store.values[KeychainPushInstallationIDProvider.account],
            replacement.uuidString.lowercased()
        )
    }

    func testInstallationIDStoreFailureDoesNotInventFallbackIdentity() {
        let provider = KeychainPushInstallationIDProvider(store: FailingInstallationIDStore())

        XCTAssertThrowsError(try provider.installationID()) { error in
            XCTAssertEqual(error as? TestError, .expected)
        }
    }

    func testReplacingLocalRemindersDoesNotCallRemoteRegistration() async {
        let storageKey = "notifications.brewReminders"
        let previous = UserDefaults.standard.data(forKey: storageKey)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: storageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: storageKey)
            }
        }
        let identity = FakePushIdentityProvider(identity: accountA)
        let transport = FakePushRegistrationTransport()
        let registrar = FakeRemoteNotificationRegistrar()
        let lifecycle = makeLifecycle(identity: identity, transport: transport, registrar: registrar)
        let manager = NotificationManager(registrationLifecycle: lifecycle)

        await manager.replaceLocalReminders([])

        XCTAssertTrue(transport.calls.isEmpty)
        XCTAssertEqual(registrar.registrationCount, 0)
    }

    func testRefreshRecoversIdentityAfterOfflineReauthentication() async {
        let identity = FakePushIdentityProvider()
        let transport = FakePushRegistrationTransport()
        let lifecycle = makeLifecycle(identity: identity, transport: transport, registrar: FakeRemoteNotificationRegistrar())
        await lifecycle.activate(isAuthorized: true)
        await lifecycle.receivedDeviceToken(Data([0xaa]))
        XCTAssertTrue(transport.calls.isEmpty)
        identity.identity = accountA
        await lifecycle.refreshRegistration(isAuthorized: true)
        XCTAssertEqual(transport.calls, [.register(accountA, installationID, Data([0xaa]))])
    }

    func testLogoutWaitsForInflightRegistrationAndDropsQueuedRefresh() async {
        let identity = FakePushIdentityProvider(identity: accountA)
        let transport = FakePushRegistrationTransport()
        let registrar = FakeRemoteNotificationRegistrar()
        let lifecycle = makeLifecycle(identity: identity, transport: transport, registrar: registrar)
        await lifecycle.activate(isAuthorized: true)
        let gate = AsyncGate()
        transport.registerGate = gate
        let registration = Task { await lifecycle.receivedDeviceToken(Data([0xaa])) }
        await gate.waitUntilEntered()
        let refresh = Task { await lifecycle.refreshRegistration(isAuthorized: true) }
        let logout = Task { await lifecycle.deactivate() }
        // Yield until deactivation has synchronously invalidated registration.
        while lifecycle.identity != nil { await Task.yield() }
        XCTAssertEqual(transport.calls, [.register(accountA, installationID, Data([0xaa]))])
        gate.release()
        await registration.value
        await refresh.value
        await logout.value
        // Auth credentials can still exist until the invalidation hook returns.
        await lifecycle.refreshRegistration(isAuthorized: true)
        XCTAssertEqual(transport.calls, [
            .register(accountA, installationID, Data([0xaa])),
            .unregister(accountA, installationID)
        ])
        XCTAssertNil(lifecycle.identity)
        XCTAssertEqual(registrar.registrationCount, 1)
    }

    func testNewAccountRegistrationWaitsForOldAccountUnregister() async {
        let identity = FakePushIdentityProvider(identity: accountA)
        let transport = FakePushRegistrationTransport()
        let lifecycle = makeLifecycle(identity: identity, transport: transport, registrar: FakeRemoteNotificationRegistrar())
        await lifecycle.activate(isAuthorized: true)
        await lifecycle.receivedDeviceToken(Data([0xbb]))
        let gate = AsyncGate()
        transport.unregisterGate = gate
        let logout = Task { await lifecycle.deactivate() }
        await gate.waitUntilEntered()
        identity.identity = accountB
        let activation = Task { await lifecycle.activate(isAuthorized: true) }
        await Task.yield()
        XCTAssertEqual(transport.calls.count, 2)
        gate.release()
        await logout.value
        await activation.value
        XCTAssertEqual(transport.calls, [
            .register(accountA, installationID, Data([0xbb])),
            .unregister(accountA, installationID),
            .register(accountB, installationID, Data([0xbb]))
        ])
        XCTAssertEqual(lifecycle.identity, accountB)
    }

    func testSignOutWhileIdentityLookupIsSuspendedDoesNotRestoreIdentity() async {
        let identity = FakePushIdentityProvider(identity: accountA)
        let transport = FakePushRegistrationTransport()
        let registrar = FakeRemoteNotificationRegistrar()
        let lifecycle = makeLifecycle(identity: identity, transport: transport, registrar: registrar)
        await lifecycle.receivedDeviceToken(Data([0xaa]))
        let gate = AsyncGate()
        identity.gate = gate
        let activation = Task { await lifecycle.activate(isAuthorized: true) }
        await gate.waitUntilEntered()
        lifecycle.sessionEnded()
        gate.release()
        await activation.value
        XCTAssertNil(lifecycle.identity)
        XCTAssertTrue(transport.calls.isEmpty)
        XCTAssertEqual(registrar.registrationCount, 0)
    }

    private func makeLifecycle(
        identity: FakePushIdentityProvider,
        transport: FakePushRegistrationTransport,
        registrar: FakeRemoteNotificationRegistrar,
        errorHandler: @escaping @MainActor (Error) -> Void = { _ in }
    ) -> PushRegistrationLifecycle {
        PushRegistrationLifecycle(
            identityProvider: identity,
            installationIDProvider: FixedInstallationIDProvider(id: installationID),
            transport: transport,
            remoteNotificationRegistrar: registrar,
            environment: .sandbox,
            reportError: { error, _ in errorHandler(error) }
        )
    }
}

private enum TestError: Error, Equatable {
    case expected
}

@MainActor
private final class FakePushIdentityProvider: PushIdentityProviding {
    var identity: PushIdentity?
    var gate: AsyncGate?

    init(identity: PushIdentity? = nil) {
        self.identity = identity
    }

    func currentPushIdentity() async -> PushIdentity? {
        let capturedIdentity = identity
        await gate?.enter()
        return capturedIdentity
    }
}

private struct FixedInstallationIDProvider: PushInstallationIDProviding {
    let id: UUID

    func installationID() throws -> UUID { id }
}

@MainActor
private final class FakeRemoteNotificationRegistrar: RemoteNotificationRegistering {
    private let authorizationAllowsRegistration: Bool
    private(set) var authorizationCheckCount = 0
    private(set) var registrationCount = 0

    init(authorizationAllowsRegistration: Bool = true) {
        self.authorizationAllowsRegistration = authorizationAllowsRegistration
    }

    func registerForRemoteNotifications() {
        authorizationCheckCount += 1
        if authorizationAllowsRegistration {
            registrationCount += 1
        }
    }
}

@MainActor
private final class FakePushRegistrationTransport: PushRegistrationTransport {
    enum Call: Equatable {
        case register(PushIdentity, UUID, Data)
        case unregister(PushIdentity, UUID)
    }

    private(set) var calls: [Call] = []
    var registerGate: AsyncGate?
    var unregisterGate: AsyncGate?
    var unregisterError: Error?
    var eventHandler: ((String) -> Void)?

    func register(
        installationID: UUID,
        deviceToken: Data,
        environment: APNSEnvironment,
        identity: PushIdentity
    ) async throws {
        calls.append(.register(identity, installationID, deviceToken))
        eventHandler?("register")
        await registerGate?.enter()
    }

    func unregister(
        installationID: UUID,
        identity: PushIdentity
    ) async throws {
        calls.append(.unregister(identity, installationID))
        eventHandler?("unregister")
        await unregisterGate?.enter()
        if let unregisterError { throw unregisterError }
    }
}

private final class FakeInstallationIDStore: PushInstallationIDStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [String: String] = [:]

    var values: [String: String] {
        get { withLock { storedValues } }
        set { withLock { storedValues = newValue } }
    }

    func read(account: String) throws -> String? {
        withLock { storedValues[account] }
    }

    func write(account: String, value: String) throws {
        withLock { storedValues[account] = value }
    }

    private func withLock<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

private struct FailingInstallationIDStore: PushInstallationIDStoring {
    func read(account: String) throws -> String? { throw TestError.expected }
    func write(account: String, value: String) throws { throw TestError.expected }
}

@MainActor
private final class AsyncGate {
    private var entered = false
    private var enteredWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func enter() async {
        await withCheckedContinuation { continuation in
            releaseWaiter = continuation
            entered = true
            enteredWaiter?.resume()
            enteredWaiter = nil
        }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

@MainActor
private final class TestSessionStore: SessionStore {
    var shouldFail = false
    func read() throws -> Data? { nil }
    func write(_ data: Data?) throws {
        if shouldFail { throw TestError.expected }
    }
}
