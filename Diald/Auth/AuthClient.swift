import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Supabase

@MainActor
final class AuthClient: ObservableObject {
    enum State: Equatable {
        case unknown
        case signedOut
        case signedIn(UUID, String?)
    }

    @Published private(set) var state: State = .unknown
    @Published var lastError: String?
    @Published var isPasswordRecovery = false

    let supabase: SupabaseClient
    private var stateTask: Task<Void, Never>?
    private var pendingAppleNonce: String?
    private let configurationError = AppSecrets.supabaseConfigurationError

    init() {
        supabase = SupabaseClient(
            supabaseURL: AppSecrets.supabaseURL,
            supabaseKey: AppSecrets.supabaseAnonKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }

    deinit { stateTask?.cancel() }

    var currentUserID: UUID? {
        if case let .signedIn(id, _) = state { id } else { nil }
    }

    func bootstrap() async {
        if let configurationError {
            Log.error(AppConfigurationError(message: configurationError), category: "auth.configuration")
            apply(session: nil)
            return
        }

        do {
            let session = try await supabase.auth.session
            apply(session: session)
        } catch {
            apply(session: nil)
        }

        stateTask?.cancel()
        stateTask = Task { [weak self] in
            guard let self else { return }
            for await (event, session) in supabase.auth.authStateChanges {
                if event == .passwordRecovery {
                    isPasswordRecovery = true
                }
                self.apply(session: session)
            }
        }
    }

    private func ensureSupabaseConfigured(category: String) -> Bool {
        guard let configurationError else { return true }
        lastError = "Auth isn't configured for this build. Please install the latest build."
        Log.error(AppConfigurationError(message: configurationError), category: category)
        return false
    }

    private func apply(session: Session?) {
        if let session, !session.isExpired {
            state = .signedIn(session.user.id, session.user.email)
            Log.breadcrumb("session active", category: "auth")
        } else {
            state = .signedOut
            Log.breadcrumb("signed out", category: "auth")
        }
    }

    func signIn(email: String, password: String) async {
        lastError = nil
        guard ensureSupabaseConfigured(category: "auth.signIn.configuration") else { return }
        do {
            _ = try await supabase.auth.signIn(email: email, password: password)
            AuthClient.clearPendingRecoveryFlag()
        } catch {
            lastError = error.localizedDescription
            Log.error(error, category: "auth.signIn")
        }
    }

    enum SignUpResult: Equatable {
        case signedIn
        case needsEmailConfirmation(email: String)
    }

    func signUp(email: String, password: String, username: String) async -> SignUpResult? {
        lastError = nil
        guard ensureSupabaseConfigured(category: "auth.signUp.configuration") else { return nil }
        do {
            let response = try await supabase.auth.signUp(
                email: email,
                password: password,
                data: [
                    "username": .string(username),
                    "display_name": .string(username)
                ],
                redirectTo: AppSecrets.authRedirectURL
            )
            AuthClient.clearPendingRecoveryFlag()
            if response.session != nil {
                apply(session: response.session)
                return .signedIn
            }
            return .needsEmailConfirmation(email: email)
        } catch {
            if isConfirmationEmailFailure(error),
               let fallback = await signInAfterConfirmationEmailFailure(email: email, password: password) {
                return fallback
            }
            lastError = userFacingSignUpError(error)
            Log.error(error, category: "auth.signUp")
            return nil
        }
    }

    private func signInAfterConfirmationEmailFailure(email: String, password: String) async -> SignUpResult? {
        do {
            let response = try await supabase.auth.signIn(email: email, password: password)
            AuthClient.clearPendingRecoveryFlag()
            apply(session: response)
            return .signedIn
        } catch {
            Log.error(error, category: "auth.signUp.fallbackSignIn")
            return nil
        }
    }

    private func userFacingSignUpError(_ error: Error) -> String {
        if isConfirmationEmailFailure(error) {
            return "Diald created the account, but the confirmation email could not be sent. Email confirmations are enabled on the server, so SMTP needs to be configured or confirmations need to be disabled."
        }
        return error.localizedDescription
    }

    private func isConfirmationEmailFailure(_ error: Error) -> Bool {
        error.localizedDescription.localizedCaseInsensitiveContains("confirmation email")
            || error.localizedDescription.localizedCaseInsensitiveContains("sending email")
    }

    func signOut() async {
        AuthClient.clearPendingRecoveryFlag()
        do {
            try await supabase.auth.signOut()
        } catch {
            Log.error(error, category: "auth.signOut")
        }
    }

    func deleteAccount() async throws {
        AuthClient.clearPendingRecoveryFlag()
        try await supabase.rpc("delete_my_account").execute()
        try await supabase.auth.signOut()
    }

    func sendPasswordReset(email: String) async -> Bool {
        lastError = nil
        guard ensureSupabaseConfigured(category: "auth.resetPassword.configuration") else { return false }
        do {
            try await supabase.auth.resetPasswordForEmail(email, redirectTo: AppSecrets.authRedirectURL)
            UserDefaults.standard.set(
                Date().addingTimeInterval(3600),
                forKey: AuthClient.recoveryPendingKey
            )
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private static let recoveryPendingKey = "auth.recoveryPendingUntil"

    private static func consumePendingRecoveryFlag() -> Bool {
        let key = AuthClient.recoveryPendingKey
        guard let until = UserDefaults.standard.object(forKey: key) as? Date else {
            return false
        }
        UserDefaults.standard.removeObject(forKey: key)
        return until > Date()
    }

    private static func clearPendingRecoveryFlag() {
        UserDefaults.standard.removeObject(forKey: AuthClient.recoveryPendingKey)
    }

    func updatePassword(newPassword: String) async -> Bool {
        lastError = nil
        guard ensureSupabaseConfigured(category: "auth.updatePassword.configuration") else { return false }
        do {
            _ = try await supabase.auth.update(user: UserAttributes(password: newPassword))
            isPasswordRecovery = false
            AuthClient.clearPendingRecoveryFlag()
            try await supabase.auth.signOut()
            return true
        } catch {
            lastError = error.localizedDescription
            Log.error(error, category: "auth.updatePassword")
            return false
        }
    }

    private var lastHandledCallback: (url: String, at: Date)?

    func handle(callbackURL url: URL) async {
        guard ensureSupabaseConfigured(category: "auth.callback.configuration") else { return }

        let now = Date()
        if let last = lastHandledCallback,
           last.url == url.absoluteString,
           now.timeIntervalSince(last.at) < 5 {
            Log.breadcrumb("auth callback ignored (duplicate within 5s)", category: "auth.callback")
            return
        }
        lastHandledCallback = (url.absoluteString, now)

        let isRecovery = AuthClient.urlContainsTypeRecovery(url) || AuthClient.consumePendingRecoveryFlag()
        if isRecovery {
            isPasswordRecovery = true
        }
        do {
            try await supabase.auth.session(from: url)
            Log.breadcrumb("auth callback session established", category: "auth.callback")
        } catch {
            if isRecovery {
                isPasswordRecovery = false
            }
            lastError = "Couldn't finish from this link: \(error.localizedDescription)"
            Log.error(error, category: "auth.callback")
        }
    }

    private static func urlContainsTypeRecovery(_ url: URL) -> Bool {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        if comps.queryItems?.contains(where: { $0.name == "type" && $0.value == "recovery" }) == true {
            return true
        }
        if let fragment = comps.fragment {
            for pair in fragment.split(separator: "&") {
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2, parts[0] == "type", parts[1] == "recovery" {
                    return true
                }
            }
        }
        return false
    }

    func signInWithGoogle() async {
        lastError = nil
        guard ensureSupabaseConfigured(category: "auth.google.configuration") else { return }
        do {
            let url = try supabase.auth.getOAuthSignInURL(
                provider: .google,
                scopes: "openid email profile",
                redirectTo: AppSecrets.authRedirectURL
            )
            let callback = try await GoogleSignIn.start(authURL: url, callbackScheme: "diald")
            try await supabase.auth.session(from: callback)
            AuthClient.clearPendingRecoveryFlag()
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
        guard ensureSupabaseConfigured(category: "auth.apple.configuration") else {
            pendingAppleNonce = nil
            return
        }

        do {
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = pendingAppleNonce else { return }
            let session = try await supabase.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
            )
            AuthClient.clearPendingRecoveryFlag()
            apply(session: session)
            if let firstName = credential.fullName?.givenName?.trimmingCharacters(in: .whitespaces),
               !firstName.isEmpty {
                _ = try? await supabase
                    .from("profiles")
                    .update(["display_name": firstName])
                    .eq("id", value: session.user.id.uuidString.lowercased())
                    .execute()
            }
        } catch {
            lastError = error.localizedDescription
            Log.error(error, category: "auth.apple")
        }
        pendingAppleNonce = nil
    }
}

private struct AppConfigurationError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
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
