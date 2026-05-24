import Combine
import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class AppServices: ObservableObject {
    let auth: AuthClient
    let beans: BeansRepository
    let brews: BrewsRepository
    let stats: StatsRepository
    let notifications: NotificationManager
    let profile: ProfileRepository

    private var cancellables = Set<AnyCancellable>()

    init() {
        let auth = AuthClient()
        self.auth = auth
        self.beans = BeansRepository(auth: auth)
        self.brews = BrewsRepository(auth: auth)
        self.stats = StatsRepository(auth: auth)
        self.notifications = NotificationManager.shared
        self.profile = ProfileRepository(auth: auth)

        for child: any ObservableObject in [auth, beans, brews, stats, notifications, profile] {
            (child.objectWillChange as? ObservableObjectPublisher)?
                .sink { [weak self] in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }

        NotificationManager.shared.bind(auth: auth)

        auth.$state
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self, case .signedIn = state else { return }
                Task { await self.refreshAll() }
            }
            .store(in: &cancellables)
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
}
