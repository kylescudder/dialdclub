import Foundation
import UIKit

@MainActor
final class APIPushRegistrationTransport: PushRegistrationTransport {
    private weak var auth: AuthClient?
    private let deviceName: String
    private let bundleID: String
    private var registeredToken: String?

    init(
        auth: AuthClient,
        deviceName: String = UIDevice.current.name,
        bundleID: String = Bundle.main.bundleIdentifier ?? "club.diald"
    ) {
        self.auth = auth
        self.deviceName = deviceName
        self.bundleID = bundleID
    }

    func register(
        installationID: UUID,
        deviceToken: Data,
        environment: APNSEnvironment,
        identity: PushIdentity
    ) async throws {
        guard let auth else { return }
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        let payload: [String: String] = [
            "apns_token": token,
            "device_name": deviceName,
            "bundle_id": bundleID,
            "environment": environment.rawValue
        ]
        _ = try await auth.api.json("api/devices", values: payload)
        registeredToken = token
        Log.breadcrumb("apns token uploaded", category: "notifications")
    }

    func unregister(
        installationID: UUID,
        identity: PushIdentity
    ) async throws {
        guard let auth, let registeredToken else { return }
        _ = try await auth.api.json(
            "api/devices",
            method: "DELETE",
            values: ["apns_token": registeredToken]
        )
        self.registeredToken = nil
    }
}

enum PushRegistrationTransportKind: Equatable {
    case gateway
    case api

    static func selected(for configuration: PushGatewayConfiguration?) -> Self {
        configuration == nil ? .api : .gateway
    }
}
