import Foundation
import PowerSync

/// Sends PowerSync's local CRUD queue to the owner-scoped API.
/// Known permanent validation failures are acknowledged so PowerSync can roll
/// the optimistic local row back to server state. Transient failures throw and
/// therefore stay queued for automatic retry.
@MainActor
final class APIConnector: PowerSyncBackendConnectorProtocol {
    private static let writableTables = Set(["profiles", "beans", "brew_sessions"])

    private let auth: AuthClient
    private let issues: SyncIssueStore
    private let preserveRejected: Bool

    init(auth: AuthClient, issues: SyncIssueStore, preserveRejected: Bool = false) {
        self.auth = auth
        self.issues = issues
        self.preserveRejected = preserveRejected
    }

    func fetchCredentials() async throws -> PowerSyncCredentials? {
        guard let endpoint = AppSecrets.powerSyncURL?.absoluteString,
              await auth.currentAccessToken() != nil else { return nil }
        struct Token: Decodable { let token: String }
        let data = try await auth.api.request("api/auth/token")
        return PowerSyncCredentials(endpoint: endpoint, token: try JSONDecoder().decode(Token.self, from: data).token)
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
                guard !preserveRejected, Self.isPermanentRejection(error) else { throw error }
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
        let operation: String
        switch entry.op { case .put: operation = "put"; case .patch: operation = "patch"; case .delete: operation = "delete" }
        _ = try await auth.api.json("api/sync/upload", values: ["table": entry.table, "id": entry.id.lowercased(), "op": operation, "data": entry.opData ?? [:]])
    }
    nonisolated static func isPermanentRejection(_ error: Error) -> Bool {
        guard let error = error as? APIError else { return false }
        return ["DX001", "DX003", "23502", "23503", "23505", "23514"].contains(error.code)
    }
}
private enum SyncUploadError: LocalizedError {
    case unexpectedWritableTable(String)
    var errorDescription: String? { "PowerSync attempted to upload an unexpected table." }
}
