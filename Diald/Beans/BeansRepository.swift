import Combine
import Foundation
import PowerSync

@MainActor
final class BeansRepository: ObservableObject {
    @Published private(set) var beans: [CoffeeBean] = []
    @Published private(set) var isLoading = false

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
        isLoading = true
        let database = database
        watchTask = Task { [weak self] in
            do {
                let stream = try database.watch(
                    sql: Self.selectSQL,
                    parameters: [userID],
                    mapper: CoffeeBean.from(cursor:)
                )
                for try await rows in stream {
                    guard !Task.isCancelled else { return }
                    self?.beans = rows.compactMap { $0 }
                    self?.isLoading = false
                }
            } catch {
                self?.isLoading = false
                Log.error(error, category: "beans.watch")
            }
        }
    }

    func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
        userID = nil
        beans = []
        isLoading = false
    }

    func refresh() async {
        guard let userID else { return }
        await load(userID: userID)
    }

    func create(name: String, roaster: String, origin: String?, process: String?, roastLevel: RoastLevel?) async {
        guard let userID else { return }
        let now = Date().iso8601
        do {
            try await database.execute(
                sql: """
                insert into beans
                  (id, owner_id, name, roaster, origin, process, roast_level, created_at, updated_at)
                values (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                parameters: [
                    UUID().uuidString.lowercased(),
                    userID,
                    name,
                    roaster,
                    origin?.nilIfBlank,
                    process?.nilIfBlank,
                    roastLevel?.rawValue,
                    now,
                    now,
                ]
            )
        } catch {
            Log.error(error, category: "beans.create")
        }
    }

    func softDelete(_ bean: CoffeeBean) async {
        do {
            let now = Date().iso8601
            try await database.execute(
                sql: "update beans set deleted_at = ?, updated_at = ? where id = ?",
                parameters: [now, now, bean.id.uuidString.lowercased()]
            )
        } catch {
            Log.error(error, category: "beans.delete")
        }
    }

    private func load(userID: String) async {
        do {
            let rows = try await database.getAll(
                sql: Self.selectSQL,
                parameters: [userID],
                mapper: CoffeeBean.from(cursor:)
            )
            beans = rows.compactMap { $0 }
            isLoading = false
        } catch {
            Log.error(error, category: "beans.refresh")
        }
    }

    private static let selectSQL = """
        select * from beans
        where owner_id = ? and deleted_at is null
        order by updated_at desc
        """
}
