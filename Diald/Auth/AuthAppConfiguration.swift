import Foundation

@MainActor
enum AuthAppConfiguration {
    static let callbackScheme = "diald"
    static let keychainService = "club.diald.auth"
    static let initialDisplayNamePath = "api/profile/name"
    static let bootstrapFailureState: AuthClient.State = .signedOut

    // Shared sign-in views
    static let signInLogo = SignInLogo(imageName: "AppLogoIcon", size: 78, cornerRadius: Theme.Radius.md)
    static let signInTitle = "Diald"
    static let signInTagline = "Track extractions, beans, recipes, and the tiny changes that actually matter."
    /// Leaving the reset-password sheet signs out and retains local data.
    static let passwordRecoveryExit = PasswordRecoveryExit.signOut

    /// Diald keeps no other per-account state to reset after the user
    /// discards local data from the sign-in screen.
    static func didDiscardLocalAccount(_ services: AppServices) {}
}
