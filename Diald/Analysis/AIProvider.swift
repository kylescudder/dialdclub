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

enum AIProvider: String, CaseIterable, Identifiable {
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

@MainActor
final class AISettingsStore: ObservableObject {
    @Published var provider: AIProvider {
        didSet {
            UserDefaults.standard.set(provider.rawValue, forKey: "ai.provider")
            if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                model = provider.defaultModel
            }
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
        switch provider {
        case .openAI: openAIKey
        case .anthropic: anthropicKey
        }
    }

    var hasActiveAPIKey: Bool {
        !activeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func resetModelToProviderDefault() {
        model = provider.defaultModel
    }

    func clearActiveKey() {
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
