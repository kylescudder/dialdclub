import SwiftUI

struct RootView: View {
    @EnvironmentObject private var services: AppServices

    var body: some View {
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

private struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Today", systemImage: "timer") }
            BeansView()
                .tabItem { Label("Beans", systemImage: "leaf") }
            StatsView()
                .tabItem { Label("Stats", systemImage: "chart.xyaxis.line") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Theme.Colors.green)
    }
}
