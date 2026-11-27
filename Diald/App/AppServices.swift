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
    private(set) var beans: BeansRepository
    private(set) var brews: BrewsRepository
    private(set) var stats: StatsRepository
    let push: PushManager
    private(set) var reminders: BrewReminderManager
    private(set) var profile: ProfileRepository
    let analysis: AnalysisClient

    /// The creation allowance the shared paywall reports.
    var creationQuota: any CreationQuotaProviding { brews }

    private var cancellables = Set<AnyCancellable>()
    private var accountCancellables = Set<AnyCancellable>()

    init(auth: AuthClient = AuthClient(), databaseFilename: String = SyncAppConfiguration.databaseFilename) {
        let syncIssues = SyncIssueStore()
        let sync = PowerSyncManager(auth: auth, issues: syncIssues, databaseFilename: databaseFilename)
        let billing = BillingRepository(auth: auth)
        self.auth = auth
        self.sync = sync
        self.syncIssues = syncIssues
        self.billing = billing
        self.beans = BeansRepository(database: sync.database)
        self.brews = BrewsRepository(auth: auth, billing: billing, database: sync.database)
        self.stats = StatsRepository(database: sync.database)
        self.push = PushManager.shared
        self.reminders = BrewReminderManager()
        self.profile = ProfileRepository(database: sync.database)
        self.analysis = AnalysisClient()

        for child: any ObservableObject in [auth, sync, syncIssues, billing, push, analysis] {
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
        auth.deleteLocalAccount = { [weak self, weak sync] in
            try await sync?.deleteAccountData()
            await self?.reminders.replaceLocalReminders([])
        }
        sync.accountDatabaseDidChange = { [weak self] in await self?.replaceAccountRepositories() }
        bindAccountPublishers()
        billing.start()
        Task { await sync.startObservingAuth() }

        auth.$state.combineLatest(auth.$requiresReauthentication)
            .removeDuplicates { $0.0 == $1.0 && $0.1 == $1.1 }
            .sink { [weak self] state, _ in
                guard let self else { return }
                Task { @MainActor in await self.applyAuth(state: state) }
            }
            .store(in: &cancellables)

    }

    private func replaceAccountRepositories() async {
        await reminders.suspend()
        profile.stopWatching()
        beans.stopWatching()
        brews.stopWatching()
        stats.stopWatching()
        billing.resetForSignOut()
        reminders = BrewReminderManager(owner: sync.accountID, legacyOwner: auth.legacyOwnerID)
        profile = ProfileRepository(database: sync.database)
        beans = BeansRepository(database: sync.database)
        brews = BrewsRepository(auth: auth, billing: billing, database: sync.database)
        stats = StatsRepository(database: sync.database)
        bindAccountPublishers()
        publishWidgetSnapshot()
        objectWillChange.send()
    }

    private func bindAccountPublishers() {
        accountCancellables.removeAll()
        profile.$profile
            .map { $0?.isPremiumAccount == true }
            .removeDuplicates()
            .sink { [weak billing] granted in billing?.setAccessOverride(granted) }
            .store(in: &accountCancellables)
        for child: any ObservableObject in [beans, brews, stats, profile, reminders] {
            (child.objectWillChange as? ObservableObjectPublisher)?
                .sink { [weak self] in self?.objectWillChange.send() }
                .store(in: &accountCancellables)
        }
        Publishers.CombineLatest(brews.$brews, stats.$stats)
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] _, _ in self?.publishWidgetSnapshot() }
            .store(in: &accountCancellables)
    }

    private func applyAuth(state: AuthClient.State) async {
        guard auth.state == state else { return }
        Analytics.authStateChanged(state)
        guard auth.canAccessMainApp, case let .signedIn(userID, _) = state else {
            push.sessionEnded()
            billing.resetForSignOut()
            profile.stopWatching()
            beans.stopWatching()
            brews.stopWatching()
            stats.stopWatching()
            await reminders.suspend()
            publishWidgetSnapshot()
            return
        }
        let id = userID.uuidString.lowercased()
        profile.startWatching(userID: id)
        beans.startWatching(userID: id)
        brews.startWatching(userID: id)
        stats.startWatching(userID: id)
        await reminders.resume()
        guard auth.state == state else { return }
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
