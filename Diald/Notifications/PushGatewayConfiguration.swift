import Foundation

struct PushGatewayConfiguration: Equatable, Sendable {
    let baseURL: URL
    let applicationID: String

    static var fromBundle: PushGatewayConfiguration? {
        from(bundle: .main)
    }

    static func from(bundle: Bundle) -> PushGatewayConfiguration? {
        make(
            rawURL: bundle.object(forInfoDictionaryKey: "PUSH_GATEWAY_URL") as? String,
            applicationID: bundle.object(
                forInfoDictionaryKey: "PUSH_GATEWAY_APPLICATION_ID"
            ) as? String
        )
    }

    static func make(rawURL: String?, applicationID: String?) -> PushGatewayConfiguration? {
        guard
            let rawURL = rawURL?.trimmingCharacters(in: .whitespacesAndNewlines),
            !rawURL.isEmpty,
            let baseURL = URL(string: rawURL),
            ["https", "http"].contains(baseURL.scheme?.lowercased() ?? ""),
            baseURL.host != nil,
            let applicationID = applicationID?.trimmingCharacters(in: .whitespacesAndNewlines),
            applicationID.range(
                of: #"^[a-z0-9][a-z0-9-]{1,62}[a-z0-9]$"#,
                options: .regularExpression
            ) != nil
        else { return nil }

        return PushGatewayConfiguration(baseURL: baseURL, applicationID: applicationID)
    }
}
