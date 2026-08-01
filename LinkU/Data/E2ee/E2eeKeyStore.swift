import Foundation

/// E2EE 身份/会话/群密钥的加密存储，对应 android-native E2eeKeyStore.kt——单独用一个
/// Keychain service（跟登录 token、钱包助记词隔离），只管"存取"，不关心具体存的是什么
/// （身份密钥对/PreKey/会话/Sender Key 都是外面序列化成 base64 字符串再存进来）。
final class E2eeKeyStore {
    private let keychain = KeychainStore(service: "com.linku.ios.e2ee")

    func key(userId: Int64, suffix: String) -> String { "u\(userId)_\(suffix)" }

    func read(userId: Int64, suffix: String) -> String? {
        keychain.get(key(userId: userId, suffix: suffix))
    }

    func write(userId: Int64, suffix: String, value: String) {
        keychain.set(value, forKey: key(userId: userId, suffix: suffix))
    }

    func delete(userId: Int64, suffix: String) {
        keychain.remove(key(userId: userId, suffix: suffix))
    }

    /// 换加密身份（比如用户主动重置）时整套清掉——身份/会话/PreKey/Sender Key 一个都不留。
    func deleteAll(userId: Int64) {
        let prefix = "u\(userId)_"
        for existingKey in keychain.allKeys() where existingKey.hasPrefix(prefix) {
            keychain.remove(existingKey)
        }
    }

    /// 数有多少条 suffix 以 suffixPrefix 开头的记录——LinkuSignalProtocolStore.needsPreKeyUpload
    /// 用来判断"one-time prekey 是不是要见底了"，不需要额外再维护一份计数索引。
    func count(userId: Int64, suffixPrefix: String) -> Int {
        let prefix = key(userId: userId, suffix: suffixPrefix)
        return keychain.allKeys().filter { $0.hasPrefix(prefix) }.count
    }
}
