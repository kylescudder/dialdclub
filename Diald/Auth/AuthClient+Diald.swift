import Foundation
import PowerSync

extension AuthClient {
    func bootstrap(database: PowerSyncDatabaseProtocol) async {
        await bootstrap(offlineAccount: {
            let ids = try await database.getAll(sql: "select id from profiles union select owner_id as id from beans union select owner_id as id from brew_sessions union select user_id as id from pending_extractions", parameters: [], mapper: { try $0.getString(name: "id") })
            let owners = try Set(ids.map { raw -> UUID in
                guard let id = UUID(uuidString: raw) else { throw APIError(code: "owner_mismatch", message: "Offline account data needs recovery.") }
                return id
            })
            return (owners, try await database.getCrudBatch() != nil)
        })
    }

    func signUp(email: String, password: String, username: String) async -> SignUpResult? {
        await signUp(email: email, password: password, displayName: username)
    }

    func performSessionInvalidatingOperation<T>(_ operation: () async throws -> T) async rethrows -> T {
        try await performSessionInvalidation(operation)
    }
}
