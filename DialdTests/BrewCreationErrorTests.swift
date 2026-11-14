import XCTest
@testable import Diald

final class BrewCreationErrorTests: XCTestCase {
    func testEveryCreationErrorHasTheExpectedPresentation() {
        XCTAssertEqual(
            BrewCreationFailurePresentation.forError(.freeLimitReached),
            .paywall
        )
        XCTAssertEqual(
            BrewCreationFailurePresentation.forError(.subscriptionVerificationPending),
            .verification(
                title: "Verifying subscription",
                message: "Apple has verified your subscription, but Diald is still confirming it with the server. Retry in a moment."
            )
        )
        XCTAssertEqual(
            BrewCreationFailurePresentation.forError(.quotaSnapshotUnavailable),
            .alert(
                title: "Finish syncing first",
                message: "Diald needs to download your extraction allowance before you can save brews offline. Make sure you're online, wait for sync to finish, and try again."
            )
        )
        XCTAssertEqual(
            BrewCreationFailurePresentation.forError(.unauthenticated),
            .alert(
                title: "Sign in again",
                message: "Your session is no longer available. Sign in again, then retry saving this brew."
            )
        )
        XCTAssertEqual(
            BrewCreationFailurePresentation.forError(.networkFailure),
            .alert(
                title: "Couldn't save brew",
                message: "Please check your connection and try again."
            )
        )
        XCTAssertEqual(
            BrewCreationFailurePresentation.forError(.serverValidationFailure),
            .alert(
                title: "Couldn't save brew",
                message: "The server rejected this brew. Please retry or contact support if the problem continues."
            )
        )
        XCTAssertEqual(
            BrewCreationFailurePresentation.forError(.unknownFailure),
            .alert(
                title: "Couldn't save brew",
                message: "Something unexpected happened. Please try again."
            )
        )
    }

    func testLocalQuotaSnapshotDistinguishesUnknownFromConfirmedZero() throws {
        XCTAssertThrowsError(try ExtractionQuotaSnapshot.requireInitializedCount(nil)) { error in
            XCTAssertEqual(error as? BrewCreationError, .quotaSnapshotUnavailable)
        }
        XCTAssertEqual(try ExtractionQuotaSnapshot.requireInitializedCount(0), 0)
    }

    func testDatabaseLimitMapsToVerificationWhileMirrorIsPending() {
        let databaseError = APIError(code: "DX001", message: "free extraction limit reached")

        XCTAssertEqual(
            BrewCreationError.classify(databaseError, subscriptionState: .free),
            .freeLimitReached
        )
        XCTAssertEqual(
            BrewCreationError.classify(databaseError, subscriptionState: .verifying),
            .subscriptionVerificationPending
        )
    }

    func testRepositoryErrorClassificationDistinguishesRequiredFailures() {
        XCTAssertEqual(
            BrewCreationError.classify(
                APIError(code: "DX002", message: "authentication required"),
                subscriptionState: .free
            ),
            .unauthenticated
        )
        XCTAssertEqual(
            BrewCreationError.classify(
                APIError(code: "temporarily_unavailable", message: "database unavailable"),
                subscriptionState: .free
            ),
            .networkFailure
        )
        XCTAssertEqual(
            BrewCreationError.classify(
                APIError(code: "42501", message: "row-level security violation"),
                subscriptionState: .free
            ),
            .serverValidationFailure
        )
        XCTAssertEqual(
            BrewCreationError.classify(
                NSError(domain: "test", code: 1),
                subscriptionState: .free
            ),
            .unknownFailure
        )
    }

    func testAuthoritativeQuotaAndSubscriptionStateResolveAvailability() {
        let exhausted = ExtractionCreationStatus(
            lifetimeCount: 5,
            freeLimit: 5,
            hasVerifiedEntitlement: false
        )
        XCTAssertEqual(
            ExtractionCreationAvailability.resolve(status: exhausted, subscriptionState: .free),
            .limitReached
        )
        XCTAssertEqual(
            ExtractionCreationAvailability.resolve(status: exhausted, subscriptionState: .verifying),
            .subscriptionVerificationPending
        )

        let verifiedSubscriber = ExtractionCreationStatus(
            lifetimeCount: 50,
            freeLimit: 5,
            hasVerifiedEntitlement: true
        )
        XCTAssertEqual(
            ExtractionCreationAvailability.resolve(
                status: verifiedSubscriber,
                subscriptionState: .active
            ),
            .allowed
        )
    }

    func testPowerSyncAcknowledgesOnlyKnownPermanentPostgresRejections() {
        XCTAssertTrue(APIConnector.isPermanentRejection(
            APIError(code: "DX001", message: "free extraction limit reached")
        ))
        XCTAssertTrue(APIConnector.isPermanentRejection(
            APIError(code: "23514", message: "check constraint failed")
        ))
        XCTAssertFalse(APIConnector.isPermanentRejection(
            APIError(code: "temporarily_unavailable", message: "database unavailable")
        ))
        XCTAssertFalse(APIConnector.isPermanentRejection(
            APIError(code: "42501", message: "row-level security violation")
        ))
        XCTAssertFalse(APIConnector.isPermanentRejection(
            APIError(code: "DX002", message: "authentication required")
        ))
        XCTAssertFalse(APIConnector.isPermanentRejection(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        ))
    }
}
