import Foundation
import Security

/// API Key 的钥匙串存取。Release 使用系统钥匙串；Debug 使用本机 UserDefaults，避免频繁重签名导致反复授权。
enum KeychainStore {
    private static let service = "com.sorcerer.galt"

    #if DEBUG
    private static func debugKey(for account: String) -> String {
        "debugSecret.\(service).\(account)"
    }
    #endif

    static func get(_ account: String) -> String? {
        #if DEBUG
        let value = UserDefaults.standard.string(forKey: debugKey(for: account))
        return value?.isEmpty == false ? value : nil
        #else
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
        #endif
    }

    static func set(_ value: String, account: String) {
        #if DEBUG
        let key = debugKey(for: account)
        if value.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(value, forKey: key)
        }
        #else
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var attributes = base
        attributes[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(attributes as CFDictionary, nil)
        #endif
    }
}
