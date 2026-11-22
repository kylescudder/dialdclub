import Foundation

/// Diald's quick actions for the shared `QuickActionRouter`. Keep widgets,
/// App Intents, URL path names, raw values and notification names in sync.
enum AppQuickAction: String, CaseIterable {
    case logBrew
    case startTimer

    /// Where an action waits until the UI is ready. Keep the key stable.
    static let pendingStorageKey = "diald.pendingQuickAction"

    @MainActor
    func route() {
        switch self {
        case .logBrew:
            NotificationCenter.default.post(name: .openLogBrew, object: nil)
        case .startTimer:
            NotificationCenter.default.post(name: .openStartTimer, object: nil)
        }
    }
}

extension QuickActionRouter {
    /// `diald://shortcut/<action>` runs a quick action; anything else is an
    /// auth callback.
    static func handle(url: URL, auth: AuthClient) {
        Log.breadcrumb("incoming app link", category: "deeplink")

        if url.scheme == "diald", url.host == "shortcut",
           let actionName = url.pathComponents.last,
           let action = AppQuickAction(rawValue: actionName) {
            handle(action)
            return
        }

        Task { await auth.handle(callbackURL: url) }
    }
}

extension Notification.Name {
    static let openLogBrew = Notification.Name("diald.openLogBrew")
    static let openStartTimer = Notification.Name("diald.openStartTimer")
}
