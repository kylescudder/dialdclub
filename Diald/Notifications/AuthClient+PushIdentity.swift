import Foundation

extension AuthClient: PushIdentityProviding {
    func currentPushIdentity() async -> PushIdentity? {
        guard let principalID = currentUserID?.uuidString.lowercased(),
              let accessToken = await currentAccessToken(),
              currentUserID?.uuidString.lowercased() == principalID else { return nil }
        return PushIdentity(principalID: principalID, accessToken: accessToken)
    }
}
