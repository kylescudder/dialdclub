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
        identity = await identityProvider.currentPushIdentity()
        await registerLatestTokenIfPossible()
        await remoteNotificationRegistrar?.registerIfAuthorized()
    }

    func refresh() async {
        await activate()
    }

    func receivedDeviceToken(_ data: Data) async {
        latestDeviceToken = data
        await registerLatestTokenIfPossible()
    }

    func deactivate() async {
        guard let identity else { return }
        do {
            try await transport.unregister(
                installationID: installationIDProvider.installationID(),
                identity: identity
            )
        } catch {
            errorHandler(error)
        }
        self.identity = nil
    }

    func resetForSignedOutState() {
        identity = nil
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
