import Foundation

struct AIModel: Codable, Identifiable, Hashable {
    let id: String
    let provider: AIProvider
    let displayName: String
    let description: String

    init(id: String, provider: AIProvider, displayName: String? = nil, description: String? = nil) {
        self.id = id
        self.provider = provider
        self.displayName = displayName ?? id
        self.description = description ?? provider.label
    }

    static let fallback: [AIModel] = [
        AIModel(id: "gpt-5-mini", provider: .openAI, displayName: "GPT-5 mini", description: "OpenAI · fast, capable"),
        AIModel(id: "gpt-5", provider: .openAI, displayName: "GPT-5", description: "OpenAI · deeper analysis"),
        AIModel(id: "claude-sonnet-4-20250514", provider: .anthropic, displayName: "Claude Sonnet 4", description: "Anthropic · balanced analysis"),
        AIModel(id: "claude-opus-4-20250514", provider: .anthropic, displayName: "Claude Opus 4", description: "Anthropic · deepest analysis")
    ]
}

@MainActor
final class AIModelCatalog: ObservableObject {
    @Published private(set) var models: [AIModel]
    @Published private(set) var labs: [AILab]
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastRefreshError: String?

    private let auth: AuthClient
    private let session: URLSession
    private let defaults: UserDefaults

    private static let cacheKey = "ai.modelCatalog.v1"
    private static let labsCacheKey = "ai.modelCatalog.labs.v1"
    private static let cacheDateKey = "ai.modelCatalog.updatedAt"

    init(auth: AuthClient, session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.auth = auth
        self.session = session
        self.defaults = defaults
        models = Self.loadCachedModels(from: defaults) ?? AIModel.fallback
        labs = Self.loadCachedLabs(from: defaults) ?? AILab.fallback
        lastUpdated = defaults.object(forKey: Self.cacheDateKey) as? Date
    }

    func models(for provider: AIProvider) -> [AIModel] {
        models.filter { $0.provider == provider }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    var connectedLabs: [AILab] {
        labs.filter(\.isConnected)
    }

    var unconnectedLabs: [AILab] {
        labs.filter { !$0.isConnected }
    }

    /// A refresh never removes the bundled and persisted catalog, so browsing models
    /// remains useful before setup and while the device has no connection.
    func refresh(force: Bool = false) async {
        guard !isRefreshing, AppSecrets.supabaseConfigurationError == nil else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let accessToken = await auth.currentAccessToken() else {
            lastRefreshError = "Sign in to check for the newest models."
            return
        }

        var components = URLComponents(url: AppSecrets.supabaseURL
            .appendingPathComponent("functions")
            .appendingPathComponent("v1")
            .appendingPathComponent("ai-model-catalog"), resolvingAgainstBaseURL: false)!
        if force {
            components.queryItems = [URLQueryItem(name: "refresh", value: "true")]
        }
        guard let endpoint = components.url else { return }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(AppSecrets.supabaseAnonKey, forHTTPHeaderField: "apikey")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                throw AIModelCatalogError.unavailable
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let catalog = try decoder.decode(CatalogResponse.self, from: data)
            guard !catalog.models.isEmpty else { throw AIModelCatalogError.empty }

            models = catalog.models
            if let responseLabs = catalog.labs, !responseLabs.isEmpty {
                labs = responseLabs
            }
            lastUpdated = catalog.updatedAt ?? Date()
            lastRefreshError = nil
            saveCache()
        } catch {
            lastRefreshError = "Using saved models — tap refresh to retry when you’re online."
            Log.error(error, category: "analysis.models")
        }
    }

    private func saveCache() {
        guard let data = try? JSONEncoder().encode(models) else { return }
        defaults.set(data, forKey: Self.cacheKey)
        if let labsData = try? JSONEncoder().encode(labs) {
            defaults.set(labsData, forKey: Self.labsCacheKey)
        }
        defaults.set(lastUpdated, forKey: Self.cacheDateKey)
    }

    private static func loadCachedModels(from defaults: UserDefaults) -> [AIModel]? {
        guard let data = defaults.data(forKey: cacheKey),
              let models = try? JSONDecoder().decode([AIModel].self, from: data),
              !models.isEmpty else { return nil }
        return models
    }

    private static func loadCachedLabs(from defaults: UserDefaults) -> [AILab]? {
        guard let data = defaults.data(forKey: labsCacheKey),
              let labs = try? JSONDecoder().decode([AILab].self, from: data),
              !labs.isEmpty else { return nil }
        return labs
    }
}

private struct CatalogResponse: Decodable {
    let models: [AIModel]
    let labs: [AILab]?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case models
        case labs
        case updatedAt = "updated_at"
    }
}

private enum AIModelCatalogError: LocalizedError {
    case unavailable
    case empty

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "The model catalog is unavailable."
        case .empty:
            return "The model catalog did not include any models."
        }
    }
}
