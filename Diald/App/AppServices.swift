import Combine
import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class AppServices: ObservableObject {
    nonisolated static let freeExtractionLimit = 5

    let auth: AuthClient
    let sync: PowerSyncManager
    let syncIssues: SyncIssueStore
    let billing: BillingRepository
    let beans: BeansRepository
    let brews: BrewsRepository
    let stats: StatsRepository
    let push: PushManager
    let reminders: BrewReminderManager
    let profile: ProfileRepository
    let analysis: AnalysisClient

    /// The creation allowance the shared paywall reports.
    var creationQuota: any CreationQuotaProviding { brews }

    private var cancellables = Set<AnyCancellable>()

    init() {
        let auth = AuthClient()
        let syncIssues = SyncIssueStore()
        let sync = PowerSyncManager(auth: auth, issues: syncIssues)
        let billing = BillingRepository(auth: auth)
        self.auth = auth
        self.sync = sync
        self.syncIssues = syncIssues
        self.billing = billing
        self.beans = BeansRepository(database: sync.database)
        self.brews = BrewsRepository(auth: auth, billing: billing, database: sync.database)
        self.stats = StatsRepository(database: sync.database)
        self.push = PushManager.shared
        self.reminders = BrewReminderManager.shared
        self.profile = ProfileRepository(database: sync.database)
        self.analysis = AnalysisClient()

        for child: any ObservableObject in [auth, sync, syncIssues, billing, beans, brews, stats, push, reminders, profile, analysis] {
            (child.objectWillChange as? ObservableObjectPublisher)?
                .sink { [weak self] in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }

        push.bind(auth: auth)
        auth.beforeSessionInvalidation = { [weak push] in
            await push?.deactivate()
        }
        auth.afterSessionInvalidationFailure = { [weak push] in
            await push?.activate()
        }
        billing.start()
        Task { await sync.startObservingAuth() }

        auth.$state.combineLatest(auth.$requiresReauthentication)
            .removeDuplicates { $0.0 == $1.0 && $0.1 == $1.1 }
            .sink { [weak self] state, _ in
                guard let self else { return }
                Task { @MainActor in await self.applyAuth(state: state) }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(brews.$brews, stats.$stats)
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] _, _ in self?.publishWidgetSnapshot() }
            .store(in: &cancellables)
    }

    private func applyAuth(state: AuthClient.State) async {
        guard auth.state == state else { return }
        guard case let .signedIn(userID, _) = state else {
            push.sessionEnded()
            billing.resetForSignOut()
            profile.stopWatching()
            beans.stopWatching()
            brews.stopWatching()
            stats.stopWatching()
            return
        }
        let id = userID.uuidString.lowercased()
        profile.startWatching(userID: id)
        beans.startWatching(userID: id)
        brews.startWatching(userID: id)
        stats.startWatching(userID: id)
        // Install watches before suspension so a later sign-out can stop them.
        await push.activate()
        guard auth.state == state else { return }
        await billing.syncEntitlements()
        await refreshAll(refreshRemoteRegistration: false)
    }

    func refreshAll(refreshRemoteRegistration: Bool = true) async {
        await profile.refresh()
        await beans.refresh()
        await refreshBrewData()
        if refreshRemoteRegistration {
            await push.refreshRegistration()
        }
        await reminders.refreshLocalReminderState()
    }

    func refreshBrewData() async {
        await brews.refresh()
        await stats.refresh()
    }

    func publishWidgetSnapshot() {
        let latest = brews.brews.first
        WidgetSnapshotStore.saveDashboard(
            totalBrews: stats.stats.totalBrews,
            averageRating: stats.stats.averageRating,
            averageExtractionSeconds: stats.stats.averageExtractionSeconds,
            favouriteMethodLabel: stats.stats.favouriteMethod?.label,
            latestTitle: latest?.title,
            latestMethodLabel: latest?.method.label,
            latestExtractionSeconds: latest?.extractionSeconds,
            latestRating: latest?.rating,
            latestBrewedAt: latest?.brewedAt
        )
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshotStore.dashboardWidgetKind)
    }

    func canCreateNewExtraction() async -> ExtractionCreationAvailability {
        if sync.status == .offline {
            return await localExtractionCreationAvailability()
        }
        do {
            let status = try await brews.extractionCreationStatus()
            return ExtractionCreationAvailability.resolve(
                status: status,
                subscriptionState: billing.subscriptionState
            )
        } catch {
            let classified = BrewCreationError.classify(error, subscriptionState: billing.subscriptionState)
            guard classified == .networkFailure || classified == .unknownFailure else {
                return .failed(classified)
            }
            return await localExtractionCreationAvailability()
        }
    }

    private func localExtractionCreationAvailability() async -> ExtractionCreationAvailability {
        do {
            let localStatus = try await brews.localExtractionCreationStatus()
            return ExtractionCreationAvailability.resolve(
                status: localStatus,
                subscriptionState: billing.subscriptionState
            )
        } catch {
            return .failed(BrewCreationError.classify(
                error,
                subscriptionState: billing.subscriptionState
            ))
        }
    }
}
