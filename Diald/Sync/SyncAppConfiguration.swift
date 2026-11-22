import Foundation
import PowerSync

/// Diald's values for the shared sync core (`PowerSyncManager`, `APIConnector`,
/// `SyncIssueStore`). The local schema lives in `DatabaseSchema.swift`.
enum SyncAppConfiguration {
    static let databaseFilename = "diald-v2.sqlite"

    /// Every account that owns local rows or pending creations.
    static let offlineOwnerQuery = """
        select id from profiles
        union select owner_id as id from beans
        union select owner_id as id from brew_sessions
        union select user_id as id from pending_extractions
        """

    /// Tables PowerSync may upload. Read-only snapshots (quota, entitlement)
    /// must never enter the CRUD queue.
    static let writableTables = Set(["profiles", "beans", "brew_sessions"])

    /// `DX001` lifetime limit, `DX003` invalid extraction, and Postgres
    /// not-null, foreign-key, unique and check violations.
    static let permanentRejectionCodes: Set<String> = ["DX001", "DX003", "23502", "23503", "23505", "23514"]

    static let localClearFailureMessage =
        "Diald signed out but could not clear its offline database. It will retry before another account can sync on this device."

    /// An accepted brew insert confirms its pending extraction reservation.
    @MainActor
    static func didUpload(_ entry: CrudEntry, database: PowerSyncDatabaseProtocol) async throws {
        guard entry.table == "brew_sessions", entry.op == .put else { return }
        _ = try? await database.execute(
            sql: "update pending_extractions set state = 'accepted' where id = ?",
            parameters: [entry.id]
        )
    }

    /// A rejected brew releases its reservation; PowerSync restores the row.
    @MainActor
    static func didReject(
        _ entry: CrudEntry,
        error: Error,
        database: PowerSyncDatabaseProtocol,
        issues: SyncIssueStore
    ) async throws {
        if entry.table == "brew_sessions" {
            _ = try? await database.execute(
                sql: "delete from pending_extractions where id = ?",
                parameters: [entry.id]
            )
            issues.reportRejectedBrew(BrewCreationError.classify(error, subscriptionState: .free))
        } else {
            issues.reportRejectedChange(table: entry.table)
        }
    }
}
