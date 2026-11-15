import SwiftUI
import Combine

@main
struct DialdApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = AppSession()
    @AppStorage("appearance") private var appearance: Appearance = .system

    init() {
        AppBootstrap.configureSentry()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session.services)
                .id(session.generation)
                .preferredColorScheme(appearance.colorScheme)
                .tint(Theme.Colors.accent)
        }
    }
}

@MainActor
final class AppSession: ObservableObject {
    @Published var services = AppServices()
    @Published private(set) var generation = UUID()
    private var reload: AnyCancellable?
    init() { observe() }
    private func observe() {
        reload = services.sync.$requiresReload.filter { $0 }.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                services.profile.stopWatching()
                services.beans.stopWatching()
                services.brews.stopWatching()
                services.stats.stopWatching()
                await services.sync.stop()
                services = AppServices()
                generation = UUID()
                observe()
            }
        }
    }
}
