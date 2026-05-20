import Foundation

enum AppSecrets {
    static let supabaseURL: URL = {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              let url = URL(string: raw),
              !raw.isEmpty else {
            assertionFailure("SUPABASE_URL is not configured")
            return URL(string: "https://placeholder.supabase.co")!
        }
        return url
    }()

    static let supabaseAnonKey: String = {
        Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? ""
    }()

    static let sentryDSN: String = {
        Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String ?? ""
    }()

    static let authRedirectURL = URL(string: "diald://auth-callback")!
}
