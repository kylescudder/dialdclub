import Foundation

struct AnalysisFilters {
    var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    var endDate = Date()
    var beanID: UUID?
    var method: BrewMethod?
    var minimumRating: Int?
    var includeNotes = true

    func matches(_ brew: BrewSession) -> Bool {
        if brew.brewedAt < startDate { return false }
        if brew.brewedAt > Calendar.current.date(byAdding: .day, value: 1, to: endDate) ?? endDate { return false }
        if let beanID, brew.beanID != beanID { return false }
        if let method, brew.method != method { return false }
        if let minimumRating, (brew.rating ?? 0) < minimumRating { return false }
        return true
    }
}

@MainActor
final class AnalysisClient: ObservableObject {
    @Published private(set) var isLoading = false
    @Published var lastError: String?

    private let settings: AISettingsStore
    private let session: URLSession

    init(settings: AISettingsStore, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    func analyse(brews: [BrewSession], beans: [CoffeeBean], filters: AnalysisFilters) async -> String? {
        lastError = nil
        guard settings.hasActiveAPIKey else {
            lastError = "Add an API key in AI settings before running an analysis."
            return nil
        }

        let selectedBrews = brews.filter(filters.matches).sorted { $0.brewedAt < $1.brewedAt }
        guard !selectedBrews.isEmpty else {
            lastError = "No brews match those filters."
            return nil
        }

        isLoading = true
        defer { isLoading = false }

        let prompt = promptText(brews: selectedBrews, beans: beans, filters: filters)
        do {
            switch settings.provider {
            case .openAI:
                return try await requestOpenAI(prompt: prompt)
            case .anthropic:
                return try await requestAnthropic(prompt: prompt)
            }
        } catch {
            lastError = error.localizedDescription
            Log.error(error, category: "analysis.ai")
            return nil
        }
    }

    private func requestOpenAI(prompt: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/responses")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(settings.activeAPIKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": cleanedModel,
            "input": prompt,
            "max_output_tokens": 1200
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await data(for: request)
        if let text = try extractOpenAIText(from: data) { return text }
        throw AnalysisError.unreadableResponse
    }

    private func requestAnthropic(prompt: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(settings.activeAPIKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let body: [String: Any] = [
            "model": cleanedModel,
            "max_tokens": 1200,
            "system": "You are a concise coffee coach. Give specific, testable brew improvements from the user's logged data.",
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await data(for: request)
        if let text = try extractAnthropicText(from: data) { return text }
        throw AnalysisError.unreadableResponse
    }

    private func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? "The provider returned an error."
            throw AnalysisError.provider(message)
        }
        return data
    }

    private var cleanedModel: String {
        let value = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? settings.provider.defaultModel : value
    }

    private func promptText(brews: [BrewSession], beans: [CoffeeBean], filters: AnalysisFilters) -> String {
        let formatter = ISO8601DateFormatter()
        let beanNames = Dictionary(uniqueKeysWithValues: beans.map { ($0.id, $0.displayName) })
        let rows = brews.map { brew in
            [
                "date=\(formatter.string(from: brew.brewedAt))",
                "title=\(brew.title)",
                "method=\(brew.method.label)",
                "bean=\(brew.beanID.flatMap { beanNames[$0] } ?? "None")",
                "dose_g=\(String(format: "%.1f", brew.doseGrams))",
                "yield_g=\(brew.yieldGrams.map { String(format: "%.1f", $0) } ?? "n/a")",
                "water_g=\(brew.waterGrams.map { String(format: "%.1f", $0) } ?? "n/a")",
                "temp_c=\(brew.waterTemperatureC.map { String(format: "%.1f", $0) } ?? "n/a")",
                "time_s=\(brew.extractionSeconds)",
                "rating=\(brew.rating.map(String.init) ?? "unrated")",
                "grind=\(brew.grindSetting ?? "n/a")",
                filters.includeNotes ? "notes=\(brew.notes ?? "")" : nil
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        }
        .joined(separator: "\n")

        return """
        Analyse these Diald coffee brew logs and suggest how to improve future results.
        Focus on patterns, outliers, practical dial-in changes, and next experiments.
        Return: 1) what is working, 2) issues to fix, 3) the next 3 brew experiments, 4) data worth tracking better.

        Filters: start=\(formatter.string(from: filters.startDate)), end=\(formatter.string(from: filters.endDate)), method=\(filters.method?.label ?? "Any"), minimumRating=\(filters.minimumRating.map(String.init) ?? "Any")
        Brew rows:
        \(rows)
        """
    }

    private func extractOpenAIText(from data: Data) throws -> String? {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let text = object?["output_text"] as? String, !text.isEmpty { return text }
        guard let output = object?["output"] as? [[String: Any]] else { return nil }
        return output.compactMap { item -> String? in
            guard let content = item["content"] as? [[String: Any]] else { return nil }
            return content.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
        .nilIfBlank
    }

    private func extractAnthropicText(from data: Data) throws -> String? {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = object?["content"] as? [[String: Any]] else { return nil }
        return content.compactMap { $0["text"] as? String }
            .joined(separator: "\n")
            .nilIfBlank
    }
}

private enum AnalysisError: LocalizedError {
    case provider(String)
    case unreadableResponse

    var errorDescription: String? {
        switch self {
        case let .provider(message): message
        case .unreadableResponse: "The provider response did not include readable text."
        }
    }
}
