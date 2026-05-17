import AuthenticationServices
import CryptoKit
import Foundation
import Supabase

@MainActor
final class AuthClient: ObservableObject {
    enum State: Equatable {
        case loading
        case signedOut
        case signedIn(UUID, String?)
    }

    @Published private(set) var state: State = .loading
    @Published var lastError: String?

    let supabase: SupabaseClient
    private var pendingAppleNonce: String?

    init() {
        supabase = SupabaseClient(
            supabaseURL: AppSecrets.supabaseURL,
            supabaseKey: AppSecrets.supabaseAnonKey
        )
    }

    var currentUserID: UUID? {
        if case let .signedIn(id, _) = state { id } else { nil }
    }

    func restoreSession() async {
        do {
            let session = try await supabase.auth.session
            state = .signedIn(session.user.id, session.user.email)
        } catch {
            state = .signedOut
        }
    }

    func signIn(email: String, password: String) async {
        lastError = nil
        do {
            let session = try await supabase.auth.signIn(email: email, password: password)
            state = .signedIn(session.user.id, session.user.email)
        } catch {
            lastError = error.localizedDescription
            Log.error(error, category: "auth.signIn")
        }
    }

    func signUp(email: String, password: String, username: String) async {
        lastError = nil
        do {
            let session = try await supabase.auth.signUp(
                email: email,
                password: password,
                data: ["username": .string(username)]
            )
            if let user = session.user {
                state = .signedIn(user.id, user.email)
            }
        } catch {
            lastError = error.localizedDescription
            Log.error(error, category: "auth.signUp")
        }
    }

    func signOut() async {
        do {
            try await supabase.auth.signOut()
        } catch {
            Log.error(error, category: "auth.signOut")
        }
        state = .signedOut
    }

    func sendPasswordReset(email: String) async -> Bool {
        do {
            try await supabase.auth.resetPasswordForEmail(email, redirectTo: AppSecrets.authRedirectURL)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func signInWithGoogle() async {
        do {
            try await supabase.auth.signInWithOAuth(
                provider: .google,
                redirectTo: AppSecrets.authRedirectURL
            )
        } catch {
            lastError = error.localizedDescription
            Log.error(error, category: "auth.google")
        }
    }

    func beginAppleSignIn(request: ASAuthorizationAppleIDRequest) {
        let nonce = AppleNonce.random()
        pendingAppleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = AppleNonce.sha256(nonce)
    }

    func completeAppleSignIn(result: Result<ASAuthorization, Error>) async {
        do {
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = pendingAppleNonce else { return }
            let session = try await supabase.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
            )
            state = .signedIn(session.user.id, session.user.email)
        } catch {
            lastError = error.localizedDescription
            Log.error(error, category: "auth.apple")
        }
        pendingAppleNonce = nil
    }
}

enum AppleNonce {
    static func random(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if status == errSecSuccess, random < charset.count {
                result.append(charset[Int(random)])
                remaining -= 1
            }
        }
        return result
    }

    static func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
