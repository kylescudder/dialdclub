import Foundation

enum AppQuickAction: String {
    case logBrew
    case startTimer
}

@MainActor
enum QuickActionRouter {
    private static let pendingActionKey = "brewlab.pendingQuickAction"

    private static var isReady = false
    private static var pendingAction: AppQuickAction?

    static func activate() {
        isReady = true
        if let stored = UserDefaults.standard.string(forKey: pendingActionKey),
           let action = AppQuickAction(rawValue: stored) {
            pendingAction = action
            UserDefaults.standard.removeObject(forKey: pendingActionKey)
        }
        flushPendingAction()
    }

    static func handle(url: URL, auth: AuthClient) {
        Log.breadcrumb("incoming url: \(url.absoluteString)", category: "deeplink")

        if url.scheme == "brewlab", url.host == "shortcut",
           let actionName = url.pathComponents.last,
           let action = AppQuickAction(rawValue: actionName) {
            handle(action)
            return
        }

        Task { await auth.handle(callbackURL: url) }
    }

    static func handle(_ action: AppQuickAction) {
        guard isReady else {
            pendingAction = action
            UserDefaults.standard.set(action.rawValue, forKey: pendingActionKey)
            return
        }
        route(action)
    }

    private static func flushPendingAction() {
        guard let action = pendingAction else { return }
        pendingAction = nil
        route(action)
    }

    private static func route(_ action: AppQuickAction) {
        switch action {
        case .logBrew:
            NotificationCenter.default.post(name: .openLogBrew, object: nil)
        case .startTimer:
            NotificationCenter.default.post(name: .openStartTimer, object: nil)
        }
    }
}

extension Notification.Name {
    static let openLogBrew = Notification.Name("brewlab.openLogBrew")
    static let openStartTimer = Notification.Name("brewlab.openStartTimer")
}
