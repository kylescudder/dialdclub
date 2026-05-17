import AppIntents

struct BrewLabShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogBrewIntent(),
            phrases: [
                "Log a brew in \(.applicationName)",
                "Track coffee extraction in \(.applicationName)"
            ],
            shortTitle: "Log brew",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: StartExtractionTimerIntent(),
            phrases: [
                "Start extraction timer in \(.applicationName)",
                "Time my coffee in \(.applicationName)"
            ],
            shortTitle: "Start timer",
            systemImageName: "stopwatch"
        )
    }
}
