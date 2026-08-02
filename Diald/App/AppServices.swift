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
    let notifications: NotificationManager
    let profile: ProfileRepository
    let aiSettings: AISettingsStore
    let analysis: AnalysisClient

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
        self.notifications = NotificationManager.shared
        self.profile = ProfileRepository(database: sync.database)
        let aiSettings = AISettingsStore()
        self.aiSettings = aiSettings
        self.analysis = AnalysisClient(settings: aiSettings)

        for child: any ObservableObject in [auth, sync, syncIssues, billing, beans, brews, stats, notifications, profile, aiSettings, analysis] {
            (child.objectWillChange as? ObservableObjectPublisher)?
                .sink { [weak self] in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }

        NotificationManager.shared.bind(auth: auth)
        billing.start()
        Task { await sync.startObservingAuth() }

        auth.$state
            .removeDuplicates()
            .sink { [weak self] state in
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
        guard case let .signedIn(userID, _) = state else {
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
        await billing.syncEntitlements()
        await refreshAll()
    }

    func refreshAll() async {
        await profile.refresh()
        await beans.refresh()
        await refreshBrewData()
        await notifications.registerIfAuthorized()
        await notifications.refreshLocalReminderState()
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
