import Combine
import Foundation
import PowerSync

@MainActor
final class PowerSyncManager: ObservableObject {
    private static let requiresWipeKey = "sync.requiresWipeBeforeConnect"

    enum Status: Equatable {
        case idle
        case connecting
        case connected
        case offline
        case error(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var pendingUploadCount = 0
    @Published private(set) var isMigrating = false
    @Published private(set) var requiresReload = false
    static let migratedKey = "sync.selfHostedDatabaseReady"

    let database: PowerSyncDatabaseProtocol

    private let auth: AuthClient
    private let issues: SyncIssueStore
    private var connector: APIConnector?
    private var authCancellables = Set<AnyCancellable>()
    private var statusTask: Task<Void, Never>?
    private var pendingCountTask: Task<Void, Never>?

    init(auth: AuthClient, issues: SyncIssueStore) {
        self.auth = auth
        self.issues = issues
        self.database = PowerSyncDatabase(
            schema: DatabaseSchema.schema,
            dbFilename: UserDefaults.standard.bool(forKey: Self.migratedKey) ? "diald-v2.sqlite" : "diald.sqlite"
        )
    }

    deinit {
        statusTask?.cancel()
        pendingCountTask?.cancel()
    }

    func startObservingAuth() async {
        Publishers.CombineLatest(auth.$state, auth.$requiresReauthentication)
            .removeDuplicates { $0.0 == $1.0 && $0.1 == $1.1 }
            .sink { [weak self] state, _ in
                Task { @MainActor [weak self] in
                    await self?.reconcile(state)
                }
            }
            .store(in: &authCancellables)

        statusTask?.cancel()
        let database = database
        statusTask = Task { [weak self] in
            for await update in database.currentStatus.asFlow() {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if let error = update.anyError {
                        self?.status = .error(String(describing: error))
                    } else if update.connected {
                        self?.status = .connected
                    } else if update.connecting {
                        self?.status = .connecting
                    } else if update.hasSynced == true {
                        self?.status = .offline
                    } else {
                        self?.status = .idle
                    }
                }
            }
        }

        pendingCountTask?.cancel()
        pendingCountTask = Task { [weak self] in
            do {
                let stream = try database.watch(
                    sql: "select count(*) as count from ps_crud",
                    parameters: [],
                    mapper: { try $0.getInt(name: "count") }
                )
                for try await rows in stream {
                    guard !Task.isCancelled else { return }
                    self?.pendingUploadCount = rows.first ?? 0
                }
            } catch {
                Log.error(error, category: "sync.pendingCount")
            }
        }

        await reconcile(auth.state)
    }

    private func reconcile(_ state: AuthClient.State) async {
        switch state {
        case .signedIn:
            await connectIfNeeded()
        case .signedOut:
            await disconnect()
        case .unknown:
            break
        }
    }

    private func connectIfNeeded() async {
        guard connector == nil, !isMigrating, !requiresReload,
              await auth.currentAccessToken() != nil else { return }
        guard UserDefaults.standard.string(forKey: AuthClient.ownerKey) == auth.currentUserID?.uuidString.lowercased() else {
            status = .error("Sign in with the original offline account before syncing.")
            return
        }
        if UserDefaults.standard.bool(forKey: Self.requiresWipeKey) {
            do {
                try await database.disconnectAndClear()
                UserDefaults.standard.removeObject(forKey: Self.requiresWipeKey)
                pendingUploadCount = 0
            } catch {
                status = .error("Offline data must be cleared before syncing another account.")
                Log.error(error, category: "sync.preconnectWipe")
                return
            }
        }
        guard AppSecrets.powerSyncConfigurationError == nil else {
            status = .error(AppSecrets.powerSyncConfigurationError ?? "PowerSync is not configured.")
            return
        }

        if !UserDefaults.standard.bool(forKey: Self.migratedKey) {
            await migrateService()
            return
        }
        status = .connecting
        let connector = APIConnector(auth: auth, issues: issues)
        self.connector = connector
        do {
            try await database.connect(connector: connector)
        } catch {
            self.connector = nil
            status = .error(error.localizedDescription)
            Log.error(error, category: "sync.connect")
        }
    }

    private func disconnect() async {
        guard connector != nil else { return }
        do {
            try await database.disconnect()
            connector = nil
            status = .idle
        } catch {
            Log.error(error, category: "sync.disconnect")
        }
    }

    /// Explicit sign-out/account deletion is the only time local user data and
    /// pending uploads are destroyed. Transient auth changes merely disconnect.
    func wipe() async {
        UserDefaults.standard.set(true, forKey: Self.requiresWipeKey)
        do {
            try await database.disconnectAndClear()
            let other = PowerSyncDatabase(schema: DatabaseSchema.schema, dbFilename: UserDefaults.standard.bool(forKey: Self.migratedKey) ? "diald.sqlite" : "diald-v2.sqlite")
            try await other.disconnectAndClear()
            try await other.close()
            UserDefaults.standard.removeObject(forKey: Self.requiresWipeKey)
            UserDefaults.standard.removeObject(forKey: AuthClient.ownerKey)
            connector = nil
            status = .idle
            pendingUploadCount = 0
        } catch {
            Log.error(error, category: "sync.wipe")
            issues.reportLocalClearFailure()
        }
    }
    /// Never connects legacy service checkpoints to a different service. Replay
    /// against the imported original account first, then stage a fresh database.
    /// The old cache stays untouched and readable until the new first sync commits.
    private func migrateService() async {
        isMigrating = true
        defer { isMigrating = false }
        let staged = PowerSyncDatabase(schema: DatabaseSchema.schema, dbFilename: "diald-v2.sqlite")
        do {
            _ = try await auth.api.request("api/me")
            let uploader = APIConnector(auth: auth, issues: issues, preserveRejected: true)
            while try await database.getCrudBatch() != nil {
                try await uploader.uploadData(database: database)
            }
            try await staged.connect(connector: APIConnector(auth: auth, issues: issues))
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await staged.waitForFirstSync() }
                group.addTask {
                    try await Task.sleep(nanoseconds: 30_000_000_000)
                    throw URLError(.timedOut)
                }
                _ = try await group.next()
                group.cancelAll()
            }
            // Include a save that was already in flight when the UI was disabled.
            while try await database.getCrudBatch() != nil {
                try await uploader.uploadData(database: database)
            }
            let pending = try await database.getAll(
                sql: "select id, user_id, expected_lifetime_count, state, created_at from pending_extractions",
                parameters: [], mapper: { cursor in
                    (try cursor.getString(name: "id"), try cursor.getString(name: "user_id"), try cursor.getInt(name: "expected_lifetime_count"), try cursor.getString(name: "state"), try cursor.getString(name: "created_at"))
                })
            for row in pending {
                try await staged.execute(sql: "delete from pending_extractions where id = ?", parameters: [row.0])
                try await staged.execute(sql: "insert into pending_extractions(id,user_id,expected_lifetime_count,state,created_at) values (?,?,?,?,?)", parameters: [row.0,row.1,row.2,row.3,row.4])
            }
            try await staged.disconnect()
            try await staged.close()
            UserDefaults.standard.set(true, forKey: Self.migratedKey)
            requiresReload = true
        } catch {
            try? await staged.disconnect()
            try? await staged.close()
            status = .offline
            Log.error(error, category: "sync.serviceMigration")
        }
    }

    func retryConnection() async { await connectIfNeeded() }

    func stop() async {
        authCancellables.removeAll()
        statusTask?.cancel()
        pendingCountTask?.cancel()
        await disconnect()
        try? await database.close()
    }

}
