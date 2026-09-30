import Foundation
import Security

/// Stocke les jetons obtenus par l'app elle-même (source `.app`) dans le Trousseau.
enum AppKeychainStore {
    private static let service = "com.chris.claude-usage"
    private static let account = "oauth"

    private static var baseQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
    }

    static func load() -> OAuthCredentials? {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(OAuthCredentials.self, from: data)
    }

    @discardableResult
    static func save(_ credentials: OAuthCredentials) -> Bool {
        guard let data = try? JSONEncoder().encode(credentials) else { return false }
        let update: [CFString: Any] = [kSecValueData: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var add = baseQuery
        add[kSecValueData] = data
        add[kSecAttrLabel] = "Claude Usage – jeton OAuth"
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
