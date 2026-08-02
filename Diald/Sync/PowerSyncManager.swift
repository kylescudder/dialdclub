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

    let database: PowerSyncDatabaseProtocol

    private let auth: AuthClient
    private let issues: SyncIssueStore
    private var connector: SupabaseConnector?
    private var authCancellables = Set<AnyCancellable>()
    private var statusTask: Task<Void, Never>?
    private var pendingCountTask: Task<Void, Never>?

    init(auth: AuthClient, issues: SyncIssueStore) {
        self.auth = auth
        self.issues = issues
        self.database = PowerSyncDatabase(
            schema: DatabaseSchema.schema,
            dbFilename: "diald.sqlite"
        )
    }

    deinit {
        statusTask?.cancel()
        pendingCountTask?.cancel()
    }

    func startObservingAuth() async {
        auth.$state
            .removeDuplicates()
            .sink { [weak self] state in
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
        guard connector == nil else { return }
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

        status = .connecting
        let connector = SupabaseConnector(auth: auth, issues: issues)
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
            UserDefaults.standard.removeObject(forKey: Self.requiresWipeKey)
            connector = nil
            status = .idle
            pendingUploadCount = 0
        } catch {
            Log.error(error, category: "sync.wipe")
            issues.reportLocalClearFailure()
        }
    }
}
