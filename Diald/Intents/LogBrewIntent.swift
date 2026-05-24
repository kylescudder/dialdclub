import AppIntents
import Foundation

struct LogBrewIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Brew"
    static let description = IntentDescription("Open Diald ready to record a coffee extraction.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Method")
    var method: String?

    @Parameter(title: "Extraction seconds")
    var extractionSeconds: Int?

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickActionRouter.handle(.logBrew)
        return .result()
    }
}

struct StartExtractionTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Extraction Timer"
    static let description = IntentDescription("Open Diald's extraction timer.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickActionRouter.handle(.startTimer)
        return .result()
    }
}
