import Foundation
import StoreKit
import UIKit

@MainActor
final class BillingRepository: ObservableObject {
    static let supporterMonthlyProductID = "club.diald.supporter.monthly"

    @Published private(set) var subscriptionProduct: Product?
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var hasLocalSubscription = false
    @Published private(set) var subscriptionState: SubscriptionAccessState = .free
    @Published private(set) var lastError: String?

    var isSubscribed: Bool { subscriptionState == .active }
    var isVerifyingSubscription: Bool { subscriptionState == .verifying }
    var verificationStatusMessage: String { Self.verificationPendingMessage }

    private let auth: AuthClient
    private var transactionTask: Task<Void, Never>?

    init(auth: AuthClient) {
        self.auth = auth
    }

    deinit { transactionTask?.cancel() }

    func start() {
        transactionTask?.cancel()
        transactionTask = Task { [weak self] in
            guard let self else { return }
            for await result in Transaction.updates {
                await self.handle(result)
            }
        }
        Task {
            await loadProducts()
            if auth.currentUserID != nil {
                await syncEntitlements()
            }
        }
    }

    func resetForSignOut() {
        hasLocalSubscription = false
        subscriptionState = .free
        lastError = nil
    }

    func loadProducts() async {
        isLoadingProducts = true
        lastError = nil
        defer { isLoadingProducts = false }
        do {
            let products = try await Product.products(for: [Self.supporterMonthlyProductID])
            subscriptionProduct = products.first
        } catch {
            lastError = error.localizedDescription
            Log.error(error, category: "billing.products")
        }
    }

    @discardableResult
    func purchase() async -> Bool {
        guard let product = subscriptionProduct else {
            await loadProducts()
            guard subscriptionProduct != nil else { return false }
            return await purchase()
        }
        guard let userID = auth.currentUserID else { return false }

        do {
            let result = try await product.purchase(options: [.appAccountToken(userID)])
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification,
                      transaction.productID == Self.supporterMonthlyProductID,
                      transaction.isActiveSubscriptionEntitlement else {
                    lastError = "The purchase could not be verified by Apple."
                    return false
                }

                hasLocalSubscription = true
                subscriptionState = .verifying
                if await confirmWithServer(
                    transaction,
                    jwsRepresentation: verification.jwsRepresentation
                ) {
                    await transaction.finish()
                    subscriptionState = .active
                    lastError = nil
                    return true
                }
                return false
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            Log.error(error, category: "billing.purchase")
            return false
        }
    }

    @discardableResult
    func restorePurchases() async -> Bool {
        do {
            try await AppStore.sync()
            await syncEntitlements()
            return isSubscribed
        } catch {
            lastError = error.localizedDescription
            Log.error(error, category: "billing.restore")
            return false
        }
    }

    func manageSubscriptions() async {
        do {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
                return
            }
            try await AppStore.showManageSubscriptions(in: scene)
            await syncEntitlements()
        } catch {
            lastError = error.localizedDescription
            Log.error(error, category: "billing.manageSubscriptions")
        }
    }

    func syncEntitlements() async {
        lastError = nil
        var foundActiveLocalEntitlement = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.supporterMonthlyProductID,
                  transaction.isActiveSubscriptionEntitlement else { continue }

            foundActiveLocalEntitlement = true
            hasLocalSubscription = true
            subscriptionState = .verifying
            if await confirmWithServer(
                transaction,
                jwsRepresentation: result.jwsRepresentation
            ) {
                subscriptionState = .active
                lastError = nil
                return
            }
        }

        if foundActiveLocalEntitlement {
            subscriptionState = .verifying
            lastError = Self.verificationPendingMessage
        } else {
            hasLocalSubscription = false
            subscriptionState = .free
            lastError = nil
        }
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result,
              transaction.productID == Self.supporterMonthlyProductID,
              transaction.isActiveSubscriptionEntitlement else { return }

        hasLocalSubscription = true
        subscriptionState = .verifying
        if await confirmWithServer(transaction, jwsRepresentation: result.jwsRepresentation) {
            await transaction.finish()
            subscriptionState = .active
            lastError = nil
        }
    }

    private func confirmWithServer(
        _ transaction: Transaction,
        jwsRepresentation: String
    ) async -> Bool {
        var finalError: Error?
        for attempt in 0..<3 {
            do {
                let response = try await sync(jwsRepresentation: jwsRepresentation)
                guard response.verified, response.active else {
                    throw BillingSyncError.entitlementNotActive
                }
                return true
            } catch {
                finalError = error
                guard error.isRetryableBillingSyncError, attempt < 2 else { break }
                let delayNanoseconds = UInt64(500_000_000 * (1 << attempt))
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
        }

        if let finalError {
            Log.error(finalError, category: "billing.syncTransaction")
        }
        subscriptionState = .verifying
        lastError = Self.verificationPendingMessage
        return false
    }

    private func sync(jwsRepresentation: String) async throws -> TransactionSyncResponse {
        guard let token = await auth.currentAccessToken() else {
            throw BillingSyncError.unauthenticated
        }

        let url = AppSecrets.supabaseURL
            .appendingPathComponent("functions")
            .appendingPathComponent("v1")
            .appendingPathComponent("iap-sync-transaction")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(AppSecrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(TransactionSyncRequest(
            signedTransactionInfo: jwsRepresentation,
            source: "ios"
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BillingSyncError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw BillingSyncError.badStatus(http.statusCode)
        }
        return try JSONDecoder().decode(TransactionSyncResponse.self, from: data)
    }

    private static let verificationPendingMessage =
        "Apple verified your subscription, but Diald is still confirming it with the server. Tap Retry verification in a moment."
}

private struct TransactionSyncRequest: Encodable {
    let signedTransactionInfo: String
    let source: String
}

private struct TransactionSyncResponse: Decodable {
    let verified: Bool
    let active: Bool
}

private enum BillingSyncError: LocalizedError {
    case unauthenticated
    case invalidResponse
    case badStatus(Int)
    case entitlementNotActive

    var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return "Subscription confirmation requires an active sign-in."
        case .invalidResponse:
            return "Subscription confirmation returned an invalid response."
        case .badStatus(let status):
            return "Subscription confirmation failed with status \(status)."
        case .entitlementNotActive:
            return "The server could not confirm an active subscription."
        }
    }

    var isRetryable: Bool {
        switch self {
        case .badStatus(let status):
            return status == 408 || status == 429 || status >= 500
        case .invalidResponse:
            return true
        case .unauthenticated, .entitlementNotActive:
            return false
        }
    }
}

private extension Error {
    var isRetryableBillingSyncError: Bool {
        if let syncError = self as? BillingSyncError {
            return syncError.isRetryable
        }
        if self is URLError || (self as NSError).domain == NSURLErrorDomain {
            return true
        }
        return false
    }
}

private extension Transaction {
    var isActiveSubscriptionEntitlement: Bool {
        guard revocationDate == nil else { return false }
        if let expirationDate {
            return expirationDate > Date()
        }
        return true
    }
}
