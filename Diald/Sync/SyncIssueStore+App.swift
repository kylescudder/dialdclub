import Foundation

/// Diald's sync issue copy, layered on the shared `SyncIssueStore`.
extension SyncIssueStore {
    func reportRejectedBrew(_ error: BrewCreationError) {
        switch error {
        case .freeLimitReached:
            report(SyncIssue(
                title: "Offline brew not synced",
                message: "The server rejected this brew because the lifetime free limit was reached. The local copy will be removed."
            ))
        case .subscriptionVerificationPending:
            report(SyncIssue(
                title: "Offline brew not synced",
                message: "The server could not verify Supporter access for this brew. Retry subscription verification before logging another brew."
            ))
        default:
            report(SyncIssue(
                title: "Offline change rejected",
                message: "The server rejected a locally saved brew. The local copy will be restored to the server version."
            ))
        }
    }

    func reportRejectedChange(table: String) {
        let subject = table == "beans" ? "bean" : "profile change"
        report(SyncIssue(
            title: "Offline change not synced",
            message: "The server rejected a locally saved \(subject). The local data will be restored to the server version."
        ))
    }
}
