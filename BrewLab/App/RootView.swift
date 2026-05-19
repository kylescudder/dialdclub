import SwiftUI

struct RootView: View {
    @EnvironmentObject private var services: AppServices

    var body: some View {
        Group {
            switch services.auth.state {
            case .loading:
                LoadingView()
            case .signedOut:
                SignInView()
            case .signedIn:
                MainTabView()
            }
        }
    }
}

private struct MainTabView: View {
    @State private var selection: MainTab = .today
    @State private var showingAddBrew = false
    @State private var startTimerOnOpen = false

    var body: some View {
        TabView(selection: $selection) {
            DashboardView()
                .tabItem { Label("Today", systemImage: "timer") }
                .tag(MainTab.today)
            BeansView()
                .tabItem { Label("Beans", systemImage: "leaf") }
                .tag(MainTab.beans)
            StatsView()
                .tabItem { Label("Stats", systemImage: "chart.xyaxis.line") }
                .tag(MainTab.stats)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(MainTab.settings)
        }
        .tint(Theme.Colors.green)
        .onAppear { QuickActionRouter.activate() }
        .sheet(isPresented: $showingAddBrew) {
            AddBrewView(startTimerOnAppear: startTimerOnOpen)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openLogBrew)) { _ in
            selection = .today
            startTimerOnOpen = false
            showingAddBrew = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openStartTimer)) { _ in
            selection = .today
            startTimerOnOpen = true
            showingAddBrew = true
        }
    }
}

private enum MainTab: Hashable {
    case today, beans, stats, settings
}
