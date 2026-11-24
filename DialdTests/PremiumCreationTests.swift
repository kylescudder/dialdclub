import Foundation
import PowerSync
import XCTest
@testable import AppUnderTest

@MainActor
final class PremiumCreationTests: XCTestCase {
    func testCachedPremiumProfileAllowsCreationAndRevocationRestoresTheCap() async throws {
        let database = PowerSyncDatabase(schema: DatabaseSchema.schema, dbFilename: "premium-\(UUID().uuidString).sqlite")
        let owner = UUID().uuidString.lowercased()
        let auth = AuthClient()
        let billing = BillingRepository(auth: auth)
        let repository = BrewsRepository(auth: auth, billing: billing, database: database)
        repository.startWatching(userID: owner)
        try await database.execute(sql: "insert into profiles (id, is_premium_account) values (?, 1)", parameters: [owner])
        try await database.execute(sql: "insert into extraction_creation_quotas (id, lifetime_count) values (?, 5)", parameters: [owner])
        // No StoreKit grant or billing override: the repository must read the
        // durable account profile before the profile watch has populated billing.
        XCTAssertFalse(billing.isSubscribed)
        let premium = try await repository.localExtractionCreationStatus()
        XCTAssertTrue(premium.hasVerifiedEntitlement)
        XCTAssertEqual(ExtractionCreationAvailability.resolve(status: premium, subscriptionState: .free), .allowed)
        _ = try await repository.create(BrewDraft())
        let afterCreate = try await repository.localExtractionCreationStatus()
        XCTAssertEqual(afterCreate.lifetimeCount, 6)
        try await database.execute(sql: "update profiles set is_premium_account = 0 where id = ?", parameters: [owner])
        let revoked = try await repository.localExtractionCreationStatus()
        XCTAssertFalse(revoked.hasVerifiedEntitlement)
        XCTAssertEqual(ExtractionCreationAvailability.resolve(status: revoked, subscriptionState: .free), .limitReached)
        do {
            _ = try await repository.create(BrewDraft())
            XCTFail("Revoked premium access must respect the exhausted allowance")
        } catch {
            XCTAssertEqual(error as? BrewCreationError, .freeLimitReached)
        }
        repository.stopWatching()
        try await database.close(deleteDatabase: true)
    }
}
