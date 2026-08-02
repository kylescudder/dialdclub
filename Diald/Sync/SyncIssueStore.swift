import Combine
import Foundation

struct SyncIssue: Identifiable, Equatable, Sendable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
final class SyncIssueStore: ObservableObject {
    @Published var current: SyncIssue?

    func reportRejectedBrew(_ error: BrewCreationError) {
        let issue: SyncIssue
        switch error {
        case .freeLimitReached:
            issue = SyncIssue(
                title: "Offline brew not synced",
                message: "The server rejected this brew because the lifetime free limit was reached. The local copy will be removed."
            )
        case .subscriptionVerificationPending:
            issue = SyncIssue(
                title: "Offline brew not synced",
                message: "The server could not verify Supporter access for this brew. Retry subscription verification before logging another brew."
            )
        default:
            issue = SyncIssue(
                title: "Offline change rejected",
                message: "The server rejected a locally saved brew. The local copy will be restored to the server version."
            )
        }
        current = issue
    }

    func reportRejectedChange(table: String) {
        let subject = table == "beans" ? "bean" : "profile change"
        current = SyncIssue(
            title: "Offline change not synced",
            message: "The server rejected a locally saved \(subject). The local data will be restored to the server version."
        )
    }

    func reportLocalClearFailure() {
        current = SyncIssue(
            title: "Offline data not cleared",
            message: "Diald signed out but could not clear its offline database. It will retry before another account can sync on this device."
        )
    }
}
