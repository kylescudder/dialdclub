import Foundation
import Security

/// Diald's values for the shared push adapters (`PushManager`,
/// `PushRegistration`, `AuthClient+PushIdentity`).
enum PushAppConfiguration {
    /// The Keychain item that already holds Diald's gateway installation ID.
    /// Changing it would give every device a new installation.
    static let installationIDKeychainService: String? = Bundle.main.bundleIdentifier ?? "club.diald"
    static let installationIDKeychainAccessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String

    static let fallbackBundleID = "club.diald"

    /// Diald has no server-originated push yet; brew reminders are local and
    /// a tap simply opens the app.
    static func route(for userInfo: [AnyHashable: Any]) -> PushRoute? {
        nil
    }
}
