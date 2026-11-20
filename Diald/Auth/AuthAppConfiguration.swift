import Foundation

@MainActor
enum AuthAppConfiguration {
    static let callbackScheme = "diald"
    static let keychainService = "club.diald.auth"
    static let initialDisplayNamePath = "api/profile/name"
    static let bootstrapFailureState: AuthClient.State = .signedOut
}
