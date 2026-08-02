import Combine
import Foundation
import PowerSync

@MainActor
final class StatsRepository: ObservableObject {
    @Published private(set) var stats = BrewStats(totalBrews: 0)

    private let database: PowerSyncDatabaseProtocol
    private var watchTask: Task<Void, Never>?
    private var userID: String?

    init(database: PowerSyncDatabaseProtocol) {
        self.database = database
    }

    deinit { watchTask?.cancel() }

    func startWatching(userID: String) {
        guard self.userID != userID || watchTask == nil else { return }
        self.userID = userID
        watchTask?.cancel()
        let database = database
        watchTask = Task { [weak self] in
            do {
                let stream = try database.watch(
                    sql: Self.statsSQL,
                    parameters: [userID, userID],
                    mapper: Self.mapStats(cursor:)
                )
                for try await rows in stream {
                    guard !Task.isCancelled else { return }
                    self?.stats = rows.compactMap { $0 }.first ?? BrewStats(totalBrews: 0)
                }
            } catch {
                Log.error(error, category: "stats.watch")
            }
        }
    }

    func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
        userID = nil
        stats = BrewStats(totalBrews: 0)
    }

    func refresh() async {
        guard let userID else { return }
        do {
            let rows = try await database.getAll(
                sql: Self.statsSQL,
                parameters: [userID, userID],
                mapper: Self.mapStats(cursor:)
            )
            stats = rows.compactMap { $0 }.first ?? BrewStats(totalBrews: 0)
        } catch {
            Log.error(error, category: "stats.refresh")
        }
    }

    nonisolated private static func mapStats(cursor: SqlCursor) -> BrewStats? {
        do {
            let method = try cursor.getStringOptional(name: "favourite_method")
                .flatMap(BrewMethod.init(rawValue:))
            return BrewStats(
                totalBrews: try cursor.getInt(name: "total_brews"),
                averageRating: try cursor.getDoubleOptional(name: "average_rating"),
                averageExtractionSeconds: try cursor.getDoubleOptional(name: "average_extraction_seconds"),
                favouriteMethod: method
            )
        } catch {
            return nil
        }
    }

    private static let statsSQL = """
        select
          count(*) as total_brews,
          round(avg(rating), 2) as average_rating,
          round(avg(extraction_seconds), 1) as average_extraction_seconds,
          (
            select method from brew_sessions
            where owner_id = ? and deleted_at is null
            group by method
            order by count(*) desc, method asc
            limit 1
          ) as favourite_method
        from brew_sessions
        where owner_id = ? and deleted_at is null
        """
}
