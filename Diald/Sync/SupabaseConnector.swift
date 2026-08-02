import Foundation
import PowerSync
import Supabase

/// Sends PowerSync's local CRUD queue to the existing Supabase write path.
/// Known permanent validation failures are acknowledged so PowerSync can roll
/// the optimistic local row back to server state. Transient failures throw and
/// therefore stay queued for automatic retry.
final class SupabaseConnector: PowerSyncBackendConnectorProtocol, @unchecked Sendable {
    private static let writableTables = Set(["profiles", "beans", "brew_sessions"])

    private let auth: AuthClient
    private let issues: SyncIssueStore

    init(auth: AuthClient, issues: SyncIssueStore) {
        self.auth = auth
        self.issues = issues
    }

    func fetchCredentials() async throws -> PowerSyncCredentials? {
        guard let endpoint = AppSecrets.powerSyncURL?.absoluteString,
              let token = await auth.currentAccessToken() else {
            return nil
        }
        return PowerSyncCredentials(endpoint: endpoint, token: token)
    }

    func uploadData(database: PowerSyncDatabaseProtocol) async throws {
        guard let batch = try await database.getCrudBatch() else { return }

        for entry in batch.crud {
            guard Self.writableTables.contains(entry.table) else {
                throw SyncUploadError.unexpectedWritableTable(entry.table)
            }

            do {
                try await upload(entry)
                if entry.table == "brew_sessions", entry.op == .put {
                    try? await database.execute(
                        sql: "update pending_extractions set state = 'accepted' where id = ?",
                        parameters: [entry.id]
                    )
                }
            } catch {
                guard Self.isPermanentRejection(error) else { throw error }
                Log.error(error, category: "sync.upload.rejected")
                if entry.table == "brew_sessions" {
                    try? await database.execute(
                        sql: "delete from pending_extractions where id = ?",
                        parameters: [entry.id]
                    )
                    let classified = BrewCreationError.classify(error, subscriptionState: .free)
                    await issues.reportRejectedBrew(classified)
                } else {
                    await issues.reportRejectedChange(table: entry.table)
                }
                // Completing this batch acknowledges the rejected operation.
                // PowerSync then restores the row from its server-state copy.
            }
        }

        try await batch.complete()
    }

    private func upload(_ entry: CrudEntry) async throws {
        let table = auth.supabase.from(entry.table)
        switch entry.op {
        case .put:
            var payload = entry.opData ?? [:]
            sanitize(&payload, table: entry.table)
            payload["id"] = entry.id
            if entry.table == "brew_sessions" {
                do {
                    // A plain insert is required here: Postgres runs Diald's
                    // lifetime-quota BEFORE INSERT trigger even on an upsert
                    // conflict, which would consume/reject the same UUID twice.
                    try await table.insert(payload).execute()
                } catch {
                    if Self.isUniqueViolation(error), try await serverBrewExists(id: entry.id) {
                        return // Idempotent replay after a later batch item failed.
                    }
                    throw error
                }
            } else {
                try await table.upsert(payload).execute()
            }
        case .patch:
            guard var payload = entry.opData else { return }
            sanitize(&payload, table: entry.table)
            guard !payload.isEmpty else { return }
            try await table.update(payload).eq("id", value: entry.id).execute()
        case .delete:
            try await table.delete().eq("id", value: entry.id).execute()
        }
    }

    private func serverBrewExists(id: String) async throws -> Bool {
        struct ExistingID: Decodable { let id: String }
        let rows: [ExistingID] = try await auth.supabase
            .from("brew_sessions")
            .select("id")
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value
        return !rows.isEmpty
    }

    private func sanitize<Value>(_ payload: inout [String: Value], table: String) {
        if table == "profiles" {
            payload.removeValue(forKey: "created_at")
        }
    }

    static func isPermanentRejection(_ error: Error) -> Bool {
        guard let error = error as? PostgrestError else { return false }
        if ["DX001", "DX003"].contains(error.code) {
            return true
        }
        return ["23502", "23503", "23505", "23514"].contains(error.code)
    }

    private static func isUniqueViolation(_ error: Error) -> Bool {
        (error as? PostgrestError)?.code == "23505"
    }
}

private enum SyncUploadError: LocalizedError {
    case unexpectedWritableTable(String)

    var errorDescription: String? {
        switch self {
        case .unexpectedWritableTable(let table):
            "PowerSync attempted to upload an unexpected table: \(table)"
        }
    }
}
