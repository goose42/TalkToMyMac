import Foundation
import Security

/// Keeps a remote provider's API key in the login Keychain rather than UserDefaults, so it
/// never sits in a plain-text preferences file.
struct APIKeyStore: Sendable {
    private let service = "com.talktomymac.dictate"
    let account: String

    static let groq = APIKeyStore(account: "groq")
    static let openRouter = APIKeyStore(account: "openrouter")

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// The saved key, or nil if none is saved.
    func load() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Saves `key`, replacing any existing one. Returns false if the Keychain refused.
    @discardableResult
    func save(_ key: String) -> Bool {
        let data = Data(key.utf8)
        let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = baseQuery
            query[kSecValueData as String] = data
            return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
