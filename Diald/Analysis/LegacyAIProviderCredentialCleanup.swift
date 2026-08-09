import Foundation
import Security

enum LegacyAIProviderCredentialCleanup {
    private static let completionKey = "analysis.localOnlyCredentialCleanup.v1"
    private static let keychainService = "club.diald.ai"
    private static let providerIDs = [
        "openAI", "anthropic", "google", "xAI", "meta", "mistral",
        "deepseek", "qwen", "moonshot", "minimax", "perplexity",
        "bedrock", "azure", "groq", "openrouter"
    ]

    static func run(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: completionKey) else { return }

        var removedAllKeys = true
        for providerID in providerIDs {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: "\(providerID).apiKey"
            ]
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecSuccess, status != errSecItemNotFound {
                removedAllKeys = false
            }
            defaults.removeObject(forKey: "ai.endpoint.\(providerID)")
        }

        [
            "ai.provider",
            "ai.model",
            "ai.modelCatalog.v1",
            "ai.modelCatalog.labs.v1",
            "ai.modelCatalog.updatedAt"
        ].forEach { defaults.removeObject(forKey: $0) }
        if removedAllKeys {
            defaults.set(true, forKey: completionKey)
        }
    }
}
