import Combine
import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class AppServices: ObservableObject {
    static let freeExtractionLimit = 5

    let auth: AuthClient
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
        let billing = BillingRepository(auth: auth)
        self.auth = auth
        self.billing = billing
        self.beans = BeansRepository(auth: auth)
        self.brews = BrewsRepository(auth: auth)
        self.stats = StatsRepository(auth: auth)
        self.notifications = NotificationManager.shared
        self.profile = ProfileRepository(auth: auth)
        let aiSettings = AISettingsStore()
        self.aiSettings = aiSettings
        self.analysis = AnalysisClient(settings: aiSettings)

        for child: any ObservableObject in [auth, billing, beans, brews, stats, notifications, profile, aiSettings, analysis] {
            (child.objectWillChange as? ObservableObjectPublisher)?
                .sink { [weak self] in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }

        NotificationManager.shared.bind(auth: auth)
        billing.start()

        auth.$state
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self else { return }
                Task { @MainActor in await self.applyAuth(state: state) }
            }
            .store(in: &cancellables)
    }

    private func applyAuth(state: AuthClient.State) async {
        guard case .signedIn = state else {
            billing.resetForSignOut()
            return
        }
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
        publishWidgetSnapshot()
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

    func canCreateNewExtraction() async -> Bool {
        guard !billing.isSubscribed else { return true }
        let count = await brews.createdExtractionCount()
        return count < Self.freeExtractionLimit
    }
}
