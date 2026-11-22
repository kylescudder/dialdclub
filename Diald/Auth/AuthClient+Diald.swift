import Foundation

extension AuthClient {
    func signUp(email: String, password: String, username: String) async -> SignUpResult? {
        await signUp(email: email, password: password, displayName: username)
    }

    func performSessionInvalidatingOperation<T>(_ operation: () async throws -> T) async rethrows -> T {
        try await performSessionInvalidation(operation)
    }
}
