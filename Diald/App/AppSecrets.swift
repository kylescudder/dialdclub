import Foundation

enum AppSecrets {
    private static let unresolvedPrefix = "$("
    private static let placeholderValues = [
        "your-project.supabase.co",
        "your-supabase-anon-key",
        "placeholder.supabase.co"
    ]

    private static func rawString(for key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static let supabaseConfigurationError: String? = {
        let rawURL = rawString(for: "SUPABASE_URL")
        let anonKey = rawString(for: "SUPABASE_ANON_KEY")

        if rawURL.isEmpty || rawURL.hasPrefix(unresolvedPrefix) || placeholderValues.contains(where: rawURL.contains) {
            return "SUPABASE_URL is not configured for this build."
        }

        guard URL(string: rawURL) != nil else {
            return "SUPABASE_URL is invalid for this build."
        }

        if anonKey.isEmpty || anonKey.hasPrefix(unresolvedPrefix) || placeholderValues.contains(where: anonKey.contains) {
            return "SUPABASE_ANON_KEY is not configured for this build."
        }

        return nil
    }()

    static let supabaseURL: URL = {
        let raw = rawString(for: "SUPABASE_URL")
        guard supabaseConfigurationError == nil,
              let url = URL(string: raw) else {
            assertionFailure("SUPABASE_URL is not configured")
            return URL(string: "https://placeholder.supabase.co")!
        }
        return url
    }()

    static let supabaseAnonKey: String = {
        rawString(for: "SUPABASE_ANON_KEY")
    }()

    static let sentryDSN: String = {
        rawString(for: "SENTRY_DSN")
    }()

    static let authRedirectURL = URL(string: "diald://auth-callback")!
}
