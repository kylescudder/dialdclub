import Foundation

@MainActor
protocol RemoteNotificationRegistering: AnyObject {
    func registerIfAuthorized() async
}

@MainActor
final class PushRegistrationLifecycle {
    typealias ErrorHandler = @MainActor (Error) -> Void

    private let identityProvider: any PushIdentityProviding
    private let installationIDProvider: any PushInstallationIDProviding
    private let transport: any PushRegistrationTransport
    private weak var remoteNotificationRegistrar: (any RemoteNotificationRegistering)?
    private let environment: APNSEnvironment
    private let errorHandler: ErrorHandler

    private var pendingOperation: Task<Void, Never>?
    private var generation = UUID()

    private(set) var identity: PushIdentity?
    private(set) var latestDeviceToken: Data?

    init(
        identityProvider: any PushIdentityProviding,
        installationIDProvider: any PushInstallationIDProviding,
        transport: any PushRegistrationTransport,
        remoteNotificationRegistrar: any RemoteNotificationRegistering,
        environment: APNSEnvironment,
        errorHandler: @escaping ErrorHandler
    ) {
        self.identityProvider = identityProvider
        self.installationIDProvider = installationIDProvider
        self.transport = transport
        self.remoteNotificationRegistrar = remoteNotificationRegistrar
        self.environment = environment
        self.errorHandler = errorHandler
    }

    func activate() async {
        let generation = generation
        await enqueue {
            guard self.generation == generation else { return }
            let identity = await self.identityProvider.currentPushIdentity()
            guard self.generation == generation else { return }
            self.identity = identity
            await self.registerLatestTokenIfPossible()
            guard self.generation == generation else { return }
            await self.remoteNotificationRegistrar?.registerIfAuthorized()
        }
    }

    func refresh() async {
        // Foreground refresh must not reactivate credentials during sign-out.
        guard identity != nil else { return }
        await activate()
    }

    func receivedDeviceToken(_ data: Data) async {
        latestDeviceToken = data
        let generation = generation
        await enqueue {
            guard self.generation == generation else { return }
            await self.registerLatestTokenIfPossible()
        }
    }

    func deactivate() async {
        let identity = identity
        resetForSignedOutState()
        // Drain any in-flight PUT before DELETE; cancellation alone cannot undo
        // a registration that the gateway has already accepted.
        await enqueue {
            guard let identity else { return }
            do {
                try await self.transport.unregister(
                    installationID: self.installationIDProvider.installationID(),
                    identity: identity
                )
            } catch {
                self.errorHandler(error)
            }
        }
    }

    func resetForSignedOutState() {
        generation = UUID()
        identity = nil
    }

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) async {
        let previous = pendingOperation
        let task = Task { @MainActor in
            await previous?.value
            await operation()
        }
        pendingOperation = task
        await task.value
    }

    private func registerLatestTokenIfPossible() async {
        guard let identity, let latestDeviceToken else { return }
        do {
            try await transport.register(
                installationID: installationIDProvider.installationID(),
                deviceToken: latestDeviceToken,
                environment: environment,
                identity: identity
            )
        } catch {
            errorHandler(error)
        }
    }
}
