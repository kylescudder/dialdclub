import Foundation

final class QuickActionRouter {
    static let shared = QuickActionRouter()
    private init() {}

    var pendingAction: URL?

    func handle(url: URL) {
        pendingAction = url
        Log.breadcrumb("opened \(url.absoluteString)", category: "deeplink")
    }
}
