import Foundation

struct PushIdentity: Equatable, Sendable {
    let principalID: String
    let accessToken: String
}

@MainActor
protocol PushIdentityProviding: AnyObject {
    func currentPushIdentity() async -> PushIdentity?
}

protocol PushInstallationIDProviding: Sendable {
    func installationID() throws -> UUID
}

enum APNSEnvironment: String, Codable, Sendable {
    case sandbox
    case production
}

protocol PushRegistrationTransport: Sendable {
    @MainActor
    func register(
        installationID: UUID,
        deviceToken: Data,
        environment: APNSEnvironment,
        identity: PushIdentity
    ) async throws

    @MainActor
    func unregister(
        installationID: UUID,
        identity: PushIdentity
    ) async throws
}

enum PushRegistrationTransportKind: Equatable {
    case gateway
    case legacy

    static func selected(for configuration: PushGatewayConfiguration?) -> Self {
        configuration == nil ? .legacy : .gateway
    }
}
