import Foundation
import UIKit

@MainActor
final class LegacyPushRegistrationTransport: PushRegistrationTransport {
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
            "user_id": identity.principalID,
            "apns_token": token,
            "device_name": deviceName,
            "bundle_id": bundleID,
            "environment": environment.rawValue
        ]
        try await auth.supabase
            .from("device_tokens")
            .upsert(payload, onConflict: "user_id,apns_token")
            .execute()
        registeredToken = token
        Log.breadcrumb("apns token uploaded", category: "notifications")
    }

    func unregister(
        installationID: UUID,
        identity: PushIdentity
    ) async throws {
        guard let auth, let registeredToken else { return }
        try await auth.supabase
            .from("device_tokens")
            .delete()
            .eq("user_id", value: identity.principalID)
            .eq("apns_token", value: registeredToken)
            .execute()
        self.registeredToken = nil
    }
}
