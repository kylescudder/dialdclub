import AppIntents

struct LogBrewIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Brew"
    static var description = IntentDescription("Open BrewLab ready to record a coffee extraction.")
    static var openAppWhenRun = true

    @Parameter(title: "Method")
    var method: String?

    @Parameter(title: "Extraction seconds")
    var extractionSeconds: Int?

    func perform() async throws -> some IntentResult {
        await MainActor.run { QuickActionRouter.handle(.logBrew) }
        return .result()
    }
}

struct StartExtractionTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Extraction Timer"
    static var description = IntentDescription("Open BrewLab's extraction timer.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run { QuickActionRouter.handle(.startTimer) }
        return .result()
    }
}
