import XCTest
import PowerSync
@testable import Diald

@MainActor
final class OfflineUpgradeTests: XCTestCase {
    func testOfflineUpgradeKeepsOriginalOwnerAndPendingWrites() async throws {
        let database = PowerSyncDatabase(schema: DatabaseSchema.schema, dbFilename: "upgrade-test-\(UUID().uuidString).sqlite")
        let owner = "11111111-1111-4111-8111-111111111111"
        let suite = "offline-upgrade-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try await database.execute(sql: "insert into profiles(id,display_name) values (?,?)", parameters: [owner,"Offline account"])
        try await database.execute(sql: "insert into beans(id,owner_id,name,roaster) values (?,?,?,?)", parameters: [UUID().uuidString.lowercased(),owner,"Queued beans","Test"])
        let before = try await database.getAll(sql: "select data from ps_crud order by id", parameters: [], mapper: { try $0.getString(name: "data") })
        let auth = AuthClient(sessionStore: MemorySessionStore(), defaults: defaults)
        await auth.bootstrap(database: database)
        XCTAssertEqual(auth.currentUserID?.uuidString.lowercased(), owner)
        XCTAssertTrue(auth.requiresReauthentication)
        let token = await auth.currentAccessToken()
        XCTAssertNil(token)
        let after = try await database.getAll(sql: "select data from ps_crud order by id", parameters: [], mapper: { try $0.getString(name: "data") })
        XCTAssertEqual(after, before)
        XCTAssertFalse(before.isEmpty)
        try await database.close(deleteDatabase: true)
    }

    func testAmbiguousLegacyOwnersCannotExposeCachedDataOrUpload() async throws {
        let database = PowerSyncDatabase(schema: DatabaseSchema.schema, dbFilename: "ambiguous-upgrade-\(UUID().uuidString).sqlite")
        let suite = "offline-upgrade-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for _ in 0..<2 {
            try await database.execute(sql: "insert into profiles(id,display_name) values (?,?)", parameters: [UUID().uuidString.lowercased(),"Test"])
        }
        let auth = AuthClient(sessionStore: MemorySessionStore(), defaults: defaults)
        await auth.bootstrap(database: database)
        XCTAssertEqual(auth.state, .signedOut)
        XCTAssertNotNil(auth.lastError)
        let token = await auth.currentAccessToken()
        XCTAssertNil(token)
        try await database.close(deleteDatabase: true)
    }
}

@MainActor
private final class MemorySessionStore: SessionStore {
    private var data: Data?
    func read() throws -> Data? { data }
    func write(_ data: Data?) throws { self.data = data }
}
