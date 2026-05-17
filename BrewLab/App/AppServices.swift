import Combine
import Foundation
import SwiftUI

@MainActor
final class AppServices: ObservableObject {
    let auth: AuthClient
    let beans: BeansRepository
    let brews: BrewsRepository
    let stats: StatsRepository
    let notifications: NotificationManager

    private var cancellables = Set<AnyCancellable>()

    init() {
        let auth = AuthClient()
        self.auth = auth
        self.beans = BeansRepository(auth: auth)
        self.brews = BrewsRepository(auth: auth)
        self.stats = StatsRepository(auth: auth)
        self.notifications = NotificationManager(auth: auth)

        for child: any ObservableObject in [auth, beans, brews, stats, notifications] {
            (child.objectWillChange as? ObservableObjectPublisher)?
                .sink { [weak self] in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }

        auth.$state
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self, case .signedIn = state else { return }
                Task { await self.refreshAll() }
            }
            .store(in: &cancellables)
    }

    func bootstrap() async {
        await auth.restoreSession()
    }

    func refreshAll() async {
        await beans.refresh()
        await brews.refresh()
        await stats.refresh()
        await notifications.registerIfAuthorized()
    }
}
