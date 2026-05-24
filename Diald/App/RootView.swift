import SwiftUI

struct RootView: View {
    @EnvironmentObject private var services: AppServices
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch services.auth.state {
            case .unknown:
                LoadingView()
            case .signedOut:
                NavigationStack { SignInView() }
            case .signedIn:
                if services.auth.isPasswordRecovery {
                    NavigationStack { SignInView() }
                } else {
                    MainTabView()
                }
            }
        }
        .task { await services.auth.bootstrap() }
        .onOpenURL { url in handle(url: url) }
        .onAppear { QuickActionRouter.activate() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                QuickActionRouter.activate()
            }
        }
        .sheet(isPresented: Binding(
            get: { services.auth.isPasswordRecovery },
            set: { services.auth.isPasswordRecovery = $0 }
        )) {
            ResetPasswordSheet()
                .presentationDetents([.medium, .large])
        }
    }

    private func handle(url: URL) {
        QuickActionRouter.handle(url: url, auth: services.auth)
    }
}

struct MainTabView: View {
    @State private var selection: MainTab = .today
    @State private var showingAddBrew = false
    @State private var startTimerOnOpen = false

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { DashboardView() }
                .tabItem { Label("Today", systemImage: "timer") }
                .tag(MainTab.today)
            NavigationStack { BeansView() }
                .tabItem { Label("Beans", systemImage: "leaf") }
                .tag(MainTab.beans)
            NavigationStack { StatsView() }
                .tabItem { Label("Stats", systemImage: "chart.xyaxis.line") }
                .tag(MainTab.stats)
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(MainTab.settings)
        }
        .tint(Theme.Colors.green)
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
