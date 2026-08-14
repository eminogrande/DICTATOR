import Foundation
import Security

struct OpenRouterKeyStore {
    private let service = "de.emin.DictateMac.openrouter"
    private let account = "api-key"

    func read() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw OpenRouterKeyStoreError.keychain(status)
        }
        return value
    }

    func save(_ value: String) throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count >= 20 else { throw OpenRouterKeyStoreError.invalidKey }
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let data = Data(key.utf8)
        let status: OSStatus
        if try read() == nil {
            var item = identity
            item[kSecValueData as String] = data
            status = SecItemAdd(item as CFDictionary, nil)
        } else {
            status = SecItemUpdate(identity as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
        guard status == errSecSuccess else { throw OpenRouterKeyStoreError.keychain(status) }
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OpenRouterKeyStoreError.keychain(status)
        }
    }
}

private enum OpenRouterKeyStoreError: LocalizedError {
    case invalidKey
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidKey: "OpenRouter key is too short"
        case let .keychain(status): "Keychain error \(status)"
        }
    }
}
