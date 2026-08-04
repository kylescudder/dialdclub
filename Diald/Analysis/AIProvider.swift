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

    var id: String { rawValue }

    var label: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI: "gpt-5-mini"
        case .anthropic: "claude-sonnet-4-20250514"
        }
    }

    var keychainAccount: String { "\(rawValue).apiKey" }
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
        case "cohere": "circle.hexagongrid"
        case "ai21": "flask.fill"
        case "qwen": "moon.stars.fill"
        case "moonshot": "moon.fill"
        case "minimax": "arrow.up.left.and.arrow.down.right"
        case "perplexity": "sparkle.magnifyingglass"
        case "bedrock": "cube.fill"
        case "azure": "cloud.fill"
        case "groq": "bolt.fill"
        case "together": "person.2.fill"
        case "fireworks": "sparkles.rectangle.stack.fill"
        case "nvidia": "eye.fill"
        case "openrouter": "arrow.triangle.branch"
        default: "flask.fill"
        }
    }

    static let fallback: [AILab] = [
        AILab(id: "openai", name: "OpenAI", subtitle: "GPT models", provider: .openAI),
        AILab(id: "anthropic", name: "Anthropic", subtitle: "Claude models", provider: .anthropic),
        AILab(id: "google", name: "Google", subtitle: "Gemini models", provider: nil),
        AILab(id: "xai", name: "xAI", subtitle: "Grok models", provider: nil),
        AILab(id: "meta", name: "Meta", subtitle: "Llama models", provider: nil),
        AILab(id: "mistral", name: "Mistral AI", subtitle: "Mistral models", provider: nil),
        AILab(id: "deepseek", name: "DeepSeek", subtitle: "Reasoning models", provider: nil),
        AILab(id: "cohere", name: "Cohere", subtitle: "Command models", provider: nil),
        AILab(id: "ai21", name: "AI21 Labs", subtitle: "Jamba models", provider: nil),
        AILab(id: "qwen", name: "Qwen", subtitle: "Qwen models", provider: nil),
        AILab(id: "moonshot", name: "Moonshot AI", subtitle: "Kimi models", provider: nil),
        AILab(id: "minimax", name: "MiniMax", subtitle: "MiniMax models", provider: nil),
        AILab(id: "perplexity", name: "Perplexity", subtitle: "Sonar models", provider: nil),
        AILab(id: "bedrock", name: "Amazon Bedrock", subtitle: "Foundation models", provider: nil),
        AILab(id: "azure", name: "Azure AI", subtitle: "Hosted model catalog", provider: nil),
        AILab(id: "groq", name: "Groq", subtitle: "Fast inference", provider: nil),
        AILab(id: "together", name: "Together AI", subtitle: "Open models", provider: nil),
        AILab(id: "fireworks", name: "Fireworks AI", subtitle: "Open models", provider: nil),
        AILab(id: "nvidia", name: "NVIDIA NIM", subtitle: "Optimised inference", provider: nil),
        AILab(id: "openrouter", name: "OpenRouter", subtitle: "Multi-lab routing", provider: nil)
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
    @Published var openAIKey: String {
        didSet { save(key: openAIKey, for: .openAI) }
    }
    @Published var anthropicKey: String {
        didSet { save(key: anthropicKey, for: .anthropic) }
    }
    @Published var model: String {
        didSet { UserDefaults.standard.set(model, forKey: "ai.model") }
    }

    init() {
        let savedProvider = UserDefaults.standard.string(forKey: "ai.provider")
            .flatMap(AIProvider.init(rawValue:)) ?? .openAI
        provider = savedProvider
        openAIKey = KeychainAPIKeys.load(account: AIProvider.openAI.keychainAccount)
        anthropicKey = KeychainAPIKeys.load(account: AIProvider.anthropic.keychainAccount)
        model = UserDefaults.standard.string(forKey: "ai.model") ?? savedProvider.defaultModel
    }

    var activeAPIKey: String {
        apiKey(for: provider)
    }

    func apiKey(for provider: AIProvider) -> String {
        switch provider {
        case .openAI: openAIKey
        case .anthropic: anthropicKey
        }
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
        switch provider {
        case .openAI: openAIKey = ""
        case .anthropic: anthropicKey = ""
        }
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
