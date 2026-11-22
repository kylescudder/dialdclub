import Foundation

/// Diald's values for the shared billing core (`BillingRepository`,
/// `SubscriptionPaywallView`).
enum BillingAppConfiguration {
    static let productID = "club.diald.supporter.monthly"
    static let verificationPendingMessage =
        "Apple verified your subscription, but Diald is still confirming it with the server. Tap Retry verification in a moment."

    static let paywallHeadline = "Keep logging extractions"
    static let paywallMessage =
        "Your first \(AppServices.freeExtractionLimit) extractions are free. This is a lifetime allowance, so deleted extractions still count. Subscribe to add unlimited brews, recipes, and tasting notes."
    static func usageText(count: Int) -> String {
        "\(count) \(count == 1 ? "extraction" : "extractions") logged"
    }

    static let privacyPolicyURL = URL(string: "https://diald.club/privacy")!
    static let termsOfUseURL = URL(string: "https://diald.club/terms")!
}
