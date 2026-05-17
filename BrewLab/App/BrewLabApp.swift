import SwiftUI

@main
struct BrewLabApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var services = AppServices()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(services)
                .task { await services.bootstrap() }
                .onOpenURL { url in
                    QuickActionRouter.shared.handle(url: url)
                }
        }
    }
}
