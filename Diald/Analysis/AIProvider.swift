import Foundation
import Security

private enum KeychainAPIKeys {
    static func save(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "club.diald.ai",
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    static func load(account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "club.diald.ai",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return "" }
        return value
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "club.diald.ai",
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case openAI
    case anthropic
    case google
    case xAI
    case meta
    case mistral
    case deepseek
    case qwen
    case moonshot
    case minimax
    case perplexity
    case bedrock
    case azure
    case groq
    case openrouter

    var id: String { rawValue }

    var label: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .google: "Google"
        case .xAI: "xAI"
        case .meta: "Meta"
        case .mistral: "Mistral AI"
        case .deepseek: "DeepSeek"
        case .qwen: "Qwen"
        case .moonshot: "Moonshot AI"
        case .minimax: "MiniMax"
        case .perplexity: "Perplexity"
        case .bedrock: "Amazon Bedrock"
        case .azure: "Azure AI"
        case .groq: "Groq"
        case .openrouter: "OpenRouter"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI: "gpt-5-mini"
        case .anthropic: "claude-sonnet-4-20250514"
        case .google: "gemini-2.5-flash"
        case .xAI: "grok-4.1-fast"
        case .meta: "Llama-4-Maverick-17B-128E-Instruct-FP8"
        case .mistral: "mistral-large-latest"
        case .deepseek: "deepseek-chat"
        case .qwen: "qwen-plus"
        case .moonshot: "kimi-k2.5"
        case .minimax: "MiniMax-M2.5"
        case .perplexity: "sonar-pro"
        case .bedrock: "amazon.nova-pro-v1:0"
        case .azure: "gpt-4.1-mini"
        case .groq: "llama-3.3-70b-versatile"
        case .openrouter: "openai/gpt-4.1-mini"
        }
    }

    var keychainAccount: String { "\(rawValue).apiKey" }

    var defaultEndpoint: String {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .anthropic: "https://api.anthropic.com/v1"
        case .google: "https://generativelanguage.googleapis.com/v1beta"
        case .xAI: "https://api.x.ai/v1"
        case .meta: "https://api.llama.com/v1"
        case .mistral: "https://api.mistral.ai/v1"
        case .deepseek: "https://api.deepseek.com/v1"
        case .qwen: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
        case .moonshot: "https://api.moonshot.ai/v1"
        case .minimax: "https://api.minimax.io/v1"
        case .perplexity: "https://api.perplexity.ai"
        case .bedrock, .azure: ""
        case .groq: "https://api.groq.com/openai/v1"
        case .openrouter: "https://openrouter.ai/api/v1"
        }
    }

    var needsEndpoint: Bool { self == .bedrock || self == .azure }
}

struct AILab: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let provider: AIProvider?

    var isConnected: Bool { provider != nil }

    var symbol: String {
        switch id {
        case "openai": "sparkles"
        case "anthropic": "a.circle.fill"
        case "google": "circle.grid.cross"
        case "xai": "xmark"
        case "meta": "infinity"
        case "mistral": "wind"
        case "deepseek": "wave.3.right"
        case "qwen": "moon.stars.fill"
        case "moonshot": "moon.fill"
        case "minimax": "arrow.up.left.and.arrow.down.right"
        case "perplexity": "sparkle.magnifyingglass"
        case "bedrock": "cube.fill"
        case "azure": "cloud.fill"
        case "groq": "bolt.fill"
        case "openrouter": "arrow.triangle.branch"
        default: "flask.fill"
        }
    }

    static let fallback: [AILab] = [
        AILab(id: "openai", name: "OpenAI", subtitle: "GPT models", provider: .openAI),
        AILab(id: "anthropic", name: "Anthropic", subtitle: "Claude models", provider: .anthropic),
        AILab(id: "google", name: "Google", subtitle: "Gemini models", provider: .google),
        AILab(id: "xai", name: "xAI", subtitle: "Grok models", provider: .xAI),
        AILab(id: "meta", name: "Meta", subtitle: "Llama models", provider: .meta),
        AILab(id: "mistral", name: "Mistral AI", subtitle: "Mistral models", provider: .mistral),
        AILab(id: "deepseek", name: "DeepSeek", subtitle: "Reasoning models", provider: .deepseek),
        AILab(id: "qwen", name: "Qwen", subtitle: "Qwen models", provider: .qwen),
        AILab(id: "moonshot", name: "Moonshot AI", subtitle: "Kimi models", provider: .moonshot),
        AILab(id: "minimax", name: "MiniMax", subtitle: "MiniMax models", provider: .minimax),
        AILab(id: "perplexity", name: "Perplexity", subtitle: "Sonar models", provider: .perplexity),
        AILab(id: "bedrock", name: "Amazon Bedrock", subtitle: "Foundation models", provider: .bedrock),
        AILab(id: "azure", name: "Azure AI", subtitle: "Hosted model catalog", provider: .azure),
        AILab(id: "groq", name: "Groq", subtitle: "Fast inference", provider: .groq),
        AILab(id: "openrouter", name: "OpenRouter", subtitle: "Multi-lab routing", provider: .openrouter)
    ]
}

@MainActor
final class AISettingsStore: ObservableObject {
    @Published var provider: AIProvider {
        didSet {
            UserDefaults.standard.set(provider.rawValue, forKey: "ai.provider")
            model = provider.defaultModel
        }
    }
    @Published private var apiKeys: [AIProvider: String]
    @Published var model: String {
        didSet { UserDefaults.standard.set(model, forKey: "ai.model") }
    }

    init() {
        let savedProvider = UserDefaults.standard.string(forKey: "ai.provider")
            .flatMap(AIProvider.init(rawValue:)) ?? .openAI
        provider = savedProvider
        apiKeys = Dictionary(uniqueKeysWithValues: AIProvider.allCases.map {
            ($0, KeychainAPIKeys.load(account: $0.keychainAccount))
        })
        model = UserDefaults.standard.string(forKey: "ai.model") ?? savedProvider.defaultModel
    }

    var activeAPIKey: String {
        apiKey(for: provider)
    }

    func apiKey(for provider: AIProvider) -> String {
        apiKeys[provider, default: ""]
    }

    var hasActiveAPIKey: Bool {
        hasAPIKey(for: provider)
    }

    func hasAPIKey(for provider: AIProvider) -> Bool {
        !apiKey(for: provider).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func resetModelToProviderDefault() {
        model = provider.defaultModel
    }

    func clearKey(for provider: AIProvider) {
        setAPIKey("", for: provider)
    }

    func setAPIKey(_ key: String, for provider: AIProvider) {
        apiKeys[provider] = key
        save(key: key, for: provider)
    }

    func endpoint(for provider: AIProvider) -> String {
        UserDefaults.standard.string(forKey: "ai.endpoint.\(provider.rawValue)") ?? provider.defaultEndpoint
    }

    func setEndpoint(_ endpoint: String, for provider: AIProvider) {
        UserDefaults.standard.set(endpoint.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "ai.endpoint.\(provider.rawValue)")
        objectWillChange.send()
    }

    func canAnalyse(with provider: AIProvider) -> Bool {
        hasAPIKey(for: provider) && (!provider.needsEndpoint || !endpoint(for: provider).isEmpty)
    }

    private func save(key: String, for provider: AIProvider) {
        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            KeychainAPIKeys.delete(account: provider.keychainAccount)
        } else {
            KeychainAPIKeys.save(cleaned, account: provider.keychainAccount)
        }
    }
}
