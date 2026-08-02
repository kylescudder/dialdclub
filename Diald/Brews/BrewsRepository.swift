import Combine
import Foundation
import PowerSync
import Supabase

@MainActor
final class BrewsRepository: ObservableObject {
    @Published private(set) var brews: [BrewSession] = []
    @Published private(set) var isLoading = false

    private let auth: AuthClient
    private let billing: BillingRepository
    private let database: PowerSyncDatabaseProtocol
    private var brewWatchTask: Task<Void, Never>?
    private var quotaWatchTask: Task<Void, Never>?
    private var userID: String?

    init(auth: AuthClient, billing: BillingRepository, database: PowerSyncDatabaseProtocol) {
        self.auth = auth
        self.billing = billing
        self.database = database
    }

    deinit {
        brewWatchTask?.cancel()
        quotaWatchTask?.cancel()
    }

    func startWatching(userID: String) {
        guard self.userID != userID || brewWatchTask == nil else { return }
        self.userID = userID
        brewWatchTask?.cancel()
        quotaWatchTask?.cancel()
        isLoading = true

        let database = database
        brewWatchTask = Task { [weak self] in
            do {
                let stream = try database.watch(
                    sql: Self.selectSQL,
                    parameters: [userID],
                    mapper: BrewSession.from(cursor:)
                )
                for try await rows in stream {
                    guard !Task.isCancelled else { return }
                    self?.brews = rows.compactMap { $0 }
                    self?.isLoading = false
                }
            } catch {
                self?.isLoading = false
                Log.error(error, category: "brews.watch")
            }
        }

        quotaWatchTask = Task { [weak self] in
            do {
                let stream = try database.watch(
                    sql: "select lifetime_count from extraction_creation_quotas where id = ?",
                    parameters: [userID],
                    mapper: { try $0.getInt(name: "lifetime_count") }
                )
                for try await rows in stream {
                    guard !Task.isCancelled, let count = rows.first else { continue }
                    await self?.reconcileAcceptedPendingExtractions(serverLifetimeCount: count)
                }
            } catch {
                Log.error(error, category: "brews.quotaWatch")
            }
        }
    }

    func stopWatching() {
        brewWatchTask?.cancel()
        quotaWatchTask?.cancel()
        brewWatchTask = nil
        quotaWatchTask = nil
        userID = nil
        brews = []
        isLoading = false
    }

    func refresh() async {
        guard let userID else { return }
        do {
            let rows = try await database.getAll(
                sql: Self.selectSQL,
                parameters: [userID],
                mapper: BrewSession.from(cursor:)
            )
            brews = rows.compactMap { $0 }
            isLoading = false
        } catch {
            Log.error(error, category: "brews.refresh")
        }
    }

    func create(_ draft: BrewDraft) async throws {
        guard let userID else { throw BrewCreationError.unauthenticated }

        let brewID = UUID().uuidString.lowercased()
        let now = Date().iso8601
        let beanID = draft.beanID?.uuidString.lowercased()
        let grindSetting = draft.grindSetting.nilIfBlank
        let notes = draft.notes.nilIfBlank
        let cachedStatus = try? await localExtractionCreationStatus()
        let allowsUnlimited = billing.subscriptionState == .active
            || cachedStatus?.hasVerifiedEntitlement == true
        let freeLimit = AppServices.freeExtractionLimit
        do {
            try await database.writeTransaction { transaction in
                let serverCount = try transaction.getOptional(
                    sql: "select lifetime_count from extraction_creation_quotas where id = ?",
                    parameters: [userID],
                    mapper: { try $0.getInt(name: "lifetime_count") }
                ) ?? 0
                let pendingCount = try transaction.getOptional(
                    sql: """
                    select count(*) as count from pending_extractions
                    where user_id = ? and expected_lifetime_count > ?
                    """,
                    parameters: [userID, serverCount],
                    mapper: { try $0.getInt(name: "count") }
                ) ?? 0
                let expectedLifetimeCount = serverCount + pendingCount + 1
                guard allowsUnlimited || expectedLifetimeCount <= freeLimit else {
                    throw BrewCreationError.freeLimitReached
                }

                try transaction.execute(
                    sql: """
                    insert into pending_extractions
                      (id, user_id, expected_lifetime_count, state, created_at)
                    values (?, ?, ?, 'queued', ?)
                    """,
                    parameters: [brewID, userID, expectedLifetimeCount, now]
                )
                try transaction.execute(
                    sql: """
                    insert into brew_sessions
                      (id, owner_id, bean_id, method, title, dose_grams, yield_grams,
                       water_grams, grind_setting, water_temperature_c,
                       extraction_seconds, rating, notes, brewed_at, created_at, updated_at)
                    values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    parameters: [
                        brewID,
                        userID,
                        beanID,
                        draft.method.rawValue,
                        draft.title,
                        draft.doseGrams,
                        draft.yieldGrams,
                        draft.waterGrams,
                        grindSetting,
                        draft.waterTemperatureC,
                        draft.extractionSeconds,
                        draft.rating,
                        notes,
                        draft.brewedAt.iso8601,
                        now,
                        now,
                    ]
                )
            }
        } catch {
            Log.error(error, category: "brews.create")
            throw BrewCreationError.classify(error, subscriptionState: billing.subscriptionState)
        }
    }

    func update(_ brew: BrewSession, with draft: BrewDraft) async {
        do {
            try await database.execute(
                sql: """
                update brew_sessions set
                  bean_id = ?, method = ?, title = ?, dose_grams = ?, yield_grams = ?,
                  water_grams = ?, grind_setting = ?, water_temperature_c = ?,
                  extraction_seconds = ?, rating = ?, notes = ?, brewed_at = ?, updated_at = ?
                where id = ?
                """,
                parameters: [
                    draft.beanID?.uuidString.lowercased(),
                    draft.method.rawValue,
                    draft.title,
                    draft.doseGrams,
                    draft.yieldGrams,
                    draft.waterGrams,
                    draft.grindSetting.nilIfBlank,
                    draft.waterTemperatureC,
                    draft.extractionSeconds,
                    draft.rating,
                    draft.notes.nilIfBlank,
                    draft.brewedAt.iso8601,
                    Date().iso8601,
                    brew.id.uuidString.lowercased(),
                ]
            )
        } catch {
            Log.error(error, category: "brews.update")
        }
    }

    /// Prefer the transactional server status while online. AppServices falls
    /// back to `localExtractionCreationStatus` for offline operation.
    func extractionCreationStatus() async throws -> ExtractionCreationStatus {
        guard auth.currentUserID != nil else { throw BrewCreationError.unauthenticated }
        do {
            let rows: [ExtractionCreationStatus] = try await auth.supabase
                .rpc("get_extraction_creation_status")
                .execute()
                .value
            guard let status = rows.first else { throw BrewCreationError.serverValidationFailure }
            return try await statusIncludingLocalPending(status)
        } catch {
            Log.error(error, category: "brews.creationStatus")
            throw BrewCreationError.classify(error, subscriptionState: billing.subscriptionState)
        }
    }

    func localExtractionCreationStatus() async throws -> ExtractionCreationStatus {
        guard let userID else { throw BrewCreationError.unauthenticated }
        let serverCount = try await database.getOptional(
            sql: "select lifetime_count from extraction_creation_quotas where id = ?",
            parameters: [userID],
            mapper: { try $0.getInt(name: "lifetime_count") }
        ) ?? 0
        let pendingCount = try await database.getOptional(
            sql: """
            select count(*) as count from pending_extractions
            where user_id = ? and expected_lifetime_count > ?
            """,
            parameters: [userID, serverCount],
            mapper: { try $0.getInt(name: "count") }
        ) ?? 0
        let entitlementRows = try await database.getAll(
            sql: """
            select product_id, bundle_id, status, expires_at, revoked_at,
                   environment, signed_at, verified_at, verification_source
            from iap_entitlements where id = ?
            """,
            parameters: [userID],
            mapper: OfflineEntitlementSnapshot.from(cursor:)
        )
        let entitlement = entitlementRows.compactMap { $0 }.first
        return ExtractionCreationStatus(
            lifetimeCount: serverCount + pendingCount,
            freeLimit: AppServices.freeExtractionLimit,
            hasVerifiedEntitlement: entitlement?.isCurrentlyVerified == true
        )
    }

    func createdExtractionCount() async throws -> Int {
        (try await localExtractionCreationStatus()).lifetimeCount
    }

    func softDelete(_ brew: BrewSession) async {
        do {
            let now = Date().iso8601
            try await database.execute(
                sql: "update brew_sessions set deleted_at = ?, updated_at = ? where id = ?",
                parameters: [now, now, brew.id.uuidString.lowercased()]
            )
        } catch {
            Log.error(error, category: "brews.delete")
        }
    }

    private func reconcileAcceptedPendingExtractions(serverLifetimeCount: Int) async {
        do {
            try await database.execute(
                sql: """
                delete from pending_extractions
                where state = 'accepted' and expected_lifetime_count <= ?
                """,
                parameters: [serverLifetimeCount]
            )
        } catch {
            Log.error(error, category: "brews.pendingReconcile")
        }
    }

    private func statusIncludingLocalPending(
        _ status: ExtractionCreationStatus
    ) async throws -> ExtractionCreationStatus {
        guard let userID else { throw BrewCreationError.unauthenticated }
        let pendingCount = try await database.getOptional(
            sql: """
            select count(*) as count from pending_extractions
            where user_id = ? and expected_lifetime_count > ?
            """,
            parameters: [userID, status.lifetimeCount],
            mapper: { try $0.getInt(name: "count") }
        ) ?? 0
        return ExtractionCreationStatus(
            lifetimeCount: status.lifetimeCount + pendingCount,
            freeLimit: status.freeLimit,
            hasVerifiedEntitlement: status.hasVerifiedEntitlement
        )
    }

    private static let selectSQL = """
        select * from brew_sessions
        where owner_id = ? and deleted_at is null
        order by brewed_at desc
        limit 80
        """
}

struct BrewDraft: Sendable {
    var beanID: UUID?
    var method: BrewMethod = .espresso
    var title = "Dial-in"
    var doseGrams = 18.0
    var yieldGrams: Double? = 36.0
    var waterGrams: Double?
    var grindSetting = ""
    var waterTemperatureC: Double? = 93
    var extractionSeconds = 0
    var rating: Int? = 4
    var notes = ""
    var brewedAt = Date()

    init() {}

    init(brew: BrewSession) {
        beanID = brew.beanID
        method = brew.method
        title = brew.title
        doseGrams = brew.doseGrams
        yieldGrams = brew.yieldGrams
        waterGrams = brew.waterGrams
        grindSetting = brew.grindSetting ?? ""
        waterTemperatureC = brew.waterTemperatureC
        extractionSeconds = brew.extractionSeconds
        rating = brew.rating
        notes = brew.notes ?? ""
        brewedAt = brew.brewedAt
    }
}

private struct OfflineEntitlementSnapshot: Sendable {
    let productID: String
    let bundleID: String?
    let status: String
    let expiresAt: Date?
    let revokedAt: Date?
    let environment: String?
    let signedAt: Date?
    let verifiedAt: Date?
    let verificationSource: String?

    var isCurrentlyVerified: Bool {
        productID == BillingRepository.supporterMonthlyProductID
            && bundleID == "club.diald"
            && status == "active"
            && revokedAt == nil
            && signedAt != nil
            && verifiedAt != nil
            && ["Production", "Sandbox"].contains(environment ?? "")
            && ["device", "notification"].contains(verificationSource ?? "")
            && (expiresAt.map { $0 > Date() } == true)
    }

    static func from(cursor: SqlCursor) -> OfflineEntitlementSnapshot? {
        do {
            return OfflineEntitlementSnapshot(
                productID: try cursor.getString(name: "product_id"),
                bundleID: try cursor.getStringOptional(name: "bundle_id"),
                status: try cursor.getString(name: "status"),
                expiresAt: parseISO8601Date(try cursor.getStringOptional(name: "expires_at")),
                revokedAt: parseISO8601Date(try cursor.getStringOptional(name: "revoked_at")),
                environment: try cursor.getStringOptional(name: "environment"),
                signedAt: parseISO8601Date(try cursor.getStringOptional(name: "signed_at")),
                verifiedAt: parseISO8601Date(try cursor.getStringOptional(name: "verified_at")),
                verificationSource: try cursor.getStringOptional(name: "verification_source")
            )
        } catch {
            return nil
        }
    }
}
