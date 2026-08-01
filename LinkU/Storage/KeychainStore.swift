import Foundation
import Security

/// 通用 Keychain 字符串读写封装（对应 android-native 里 EncryptedSharedPreferences 的角色）。
/// 会话 token、钱包助记词等敏感数据都通过这个存取，不落 UserDefaults。
struct KeychainStore {
    private let service: String

    init(service: String = "com.linku.ios") {
        self.service = service
    }

    func set(_ value: String, forKey key: String) {
        let data = Data(value.utf8)
        var query = baseQuery(key: key)
        query[kSecValueData as String] = data

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let attributesToUpdate: [String: Any] = [kSecValueData as String: data]
            SecItemUpdate(baseQuery(key: key) as CFDictionary, attributesToUpdate as CFDictionary)
        }
    }

    func get(_ key: String) -> String? {
        var query = baseQuery(key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func remove(_ key: String) {
        SecItemDelete(baseQuery(key: key) as CFDictionary)
    }

    /// 列出这个 service 下所有条目的 key（不取值）——E2eeKeyStore.deleteAll 这类"按前缀批量清空"
    /// 场景要用，Keychain 没有原生的按前缀查询，只能整表列出来自己过滤。
    func allKeys() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    private func baseQuery(key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
