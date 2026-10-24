import Foundation
import Security

protocol PushInstallationIDStoring: Sendable {
    func read(account: String) throws -> String?
    func write(account: String, value: String) throws
}

struct KeychainPushInstallationIDProvider: PushInstallationIDProviding {
    static let account = "push-gateway.installation-id"

    private let store: any PushInstallationIDStoring

    init(store: any PushInstallationIDStoring = SecurityPushInstallationIDStore()) {
        self.store = store
    }

    func installationID() throws -> UUID {
        if let stored = try store.read(account: Self.account),
           let identifier = UUID(uuidString: stored) {
            return identifier
        }

        let identifier = UUID()
        try store.write(account: Self.account, value: identifier.uuidString.lowercased())
        return identifier
    }
}

struct SecurityPushInstallationIDStore: PushInstallationIDStoring {
    private let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "club.diald") {
        self.service = service
    }

    func read(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw PushInstallationIDStoreError.keychainStatus(status)
        }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw PushInstallationIDStoreError.invalidStoredValue
        }
        return value
    }

    func write(account: String, value: String) throws {
        let key: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(key as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw PushInstallationIDStoreError.keychainStatus(updateStatus)
        }

        var insertion = key
        attributes.forEach { insertion[$0.key] = $0.value }
        let addStatus = SecItemAdd(insertion as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw PushInstallationIDStoreError.keychainStatus(addStatus)
        }
    }
}

enum PushInstallationIDStoreError: Error, Equatable {
    case keychainStatus(OSStatus)
    case invalidStoredValue
}
