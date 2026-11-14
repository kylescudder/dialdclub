import Foundation

enum AppSecrets {
    private static let unresolvedPrefix = "$("
    private static let placeholderValues = [
        "your-instance.powersync.journeyapps.com"
    ]

    private static func rawString(for key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static let apiConfigurationError: String? = {
        let raw = rawString(for: "API_URL")
        guard !raw.isEmpty, !raw.hasPrefix(unresolvedPrefix),
              !raw.contains("your-api"), let url = URL(string: raw),
              url.host != nil, url.user == nil, url.password == nil,
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1"].contains(url.host ?? "")) else {
            return "API_URL is not configured for this build."
        }
        return nil
    }()

    static let apiURL = URL(string: rawString(for: "API_URL")) ?? URL(string: "https://your-api.invalid")!

    static let powerSyncConfigurationError: String? = {
        let rawURL = rawString(for: "POWERSYNC_URL")
        if rawURL.isEmpty || rawURL.hasPrefix(unresolvedPrefix) || placeholderValues.contains(where: rawURL.contains) {
            return "POWERSYNC_URL is not configured for this build."
        }
        guard let url = URL(string: rawURL), url.host != nil,
              url.user == nil, url.password == nil,
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1"].contains(url.host ?? "")) else {
            return "POWERSYNC_URL is invalid for this build."
        }
        return nil
    }()

    static let powerSyncURL: URL? = {
        guard powerSyncConfigurationError == nil else { return nil }
        return URL(string: rawString(for: "POWERSYNC_URL"))
    }()

    static let sentryDSN: String = {
        rawString(for: "SENTRY_DSN")
    }()

    static let authRedirectURL = URL(string: "diald://auth-callback")!
}
