import Foundation

@MainActor
final class StatsRepository: ObservableObject {
    @Published private(set) var stats = BrewStats(totalBrews: 0)

    private let auth: AuthClient

    init(auth: AuthClient) {
        self.auth = auth
    }

    func refresh() async {
        guard let userID = auth.currentUserID else { return }
        do {
            let rows: [BrewStats] = try await auth.supabase
                .rpc("get_brew_stats", params: ["user_id": userID.uuidString.lowercased()])
                .execute()
                .value
            stats = rows.first ?? BrewStats(totalBrews: 0)
        } catch {
            Log.error(error, category: "stats.refresh")
        }
    }
}
