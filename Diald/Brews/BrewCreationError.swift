import Foundation
import Supabase

enum BrewCreationError: Error, Equatable, Identifiable {
    case freeLimitReached
    case subscriptionVerificationPending
    case unauthenticated
    case networkFailure
    case serverValidationFailure
    case unknownFailure

    var id: String {
        switch self {
        case .freeLimitReached: "freeLimitReached"
        case .subscriptionVerificationPending: "subscriptionVerificationPending"
        case .unauthenticated: "unauthenticated"
        case .networkFailure: "networkFailure"
        case .serverValidationFailure: "serverValidationFailure"
        case .unknownFailure: "unknownFailure"
        }
    }

    static func classify(
        _ error: Error,
        subscriptionState: SubscriptionAccessState
    ) -> BrewCreationError {
        if let creationError = error as? BrewCreationError {
            return creationError
        }

        if let postgrestError = error as? PostgrestError {
            switch postgrestError.code {
            case "DX001":
                return subscriptionState == .verifying
                    ? .subscriptionVerificationPending
                    : .freeLimitReached
            case "DX002":
                return .unauthenticated
            case "DX003", "DX004", "DX005", "42501":
                return .serverValidationFailure
            case "PGRST000", "PGRST001", "PGRST002", "PGRST003":
                return .networkFailure
            default:
                return .serverValidationFailure
            }
        }

        let nsError = error as NSError
        if error is URLError || nsError.domain == NSURLErrorDomain {
            return .networkFailure
        }
        return .unknownFailure
    }
}

enum BrewCreationFailurePresentation: Equatable {
    case paywall
    case verification(title: String, message: String)
    case alert(title: String, message: String)

    static func forError(_ error: BrewCreationError) -> BrewCreationFailurePresentation {
        switch error {
        case .freeLimitReached:
            return .paywall
        case .subscriptionVerificationPending:
            return .verification(
                title: "Verifying subscription",
                message: "Apple has verified your subscription, but Diald is still confirming it with the server. Retry in a moment."
            )
        case .unauthenticated:
            return .alert(
                title: "Sign in again",
                message: "Your session is no longer available. Sign in again, then retry saving this brew."
            )
        case .networkFailure:
            return .alert(
                title: "Couldn't save brew",
                message: "Please check your connection and try again."
            )
        case .serverValidationFailure:
            return .alert(
                title: "Couldn't save brew",
                message: "The server rejected this brew. Please retry or contact support if the problem continues."
            )
        case .unknownFailure:
            return .alert(
                title: "Couldn't save brew",
                message: "Something unexpected happened. Please try again."
            )
        }
    }
}

struct ExtractionCreationStatus: Decodable, Equatable {
    let lifetimeCount: Int
    let freeLimit: Int
    let hasVerifiedEntitlement: Bool

    enum CodingKeys: String, CodingKey {
        case lifetimeCount = "lifetime_count"
        case freeLimit = "free_limit"
        case hasVerifiedEntitlement = "has_verified_entitlement"
    }
}

enum ExtractionCreationAvailability: Equatable {
    case allowed
    case limitReached
    case subscriptionVerificationPending
    case failed(BrewCreationError)

    static func resolve(
        status: ExtractionCreationStatus,
        subscriptionState: SubscriptionAccessState
    ) -> ExtractionCreationAvailability {
        if status.hasVerifiedEntitlement || status.lifetimeCount < status.freeLimit {
            return .allowed
        }
        return subscriptionState == .verifying
            ? .subscriptionVerificationPending
            : .limitReached
    }
}
