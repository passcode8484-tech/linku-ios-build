import Foundation

/// 助记词的加密存储——单独一个 Keychain service（跟登录 token、E2EE 身份隔离），
/// 对应 android-native WalletKeyStore.kt（Android Keystore 存储）。**助记词 = 资产控制权**，
/// 这是整个 app 里最敏感的一份数据，不能跟其他任何东西共用存储命名空间。
struct WalletKeyStore {
    private let keychain = KeychainStore(service: "com.linku.ios.wallet")
    private let mnemonicKeyPrefix = "mnemonic_"

    func saveMnemonic(_ mnemonic: String, forUserId userId: Int64) {
        keychain.set(mnemonic, forKey: "\(mnemonicKeyPrefix)\(userId)")
    }

    func loadMnemonic(forUserId userId: Int64) -> String? {
        keychain.get("\(mnemonicKeyPrefix)\(userId)")
    }

    func hasWallet(forUserId userId: Int64) -> Bool {
        loadMnemonic(forUserId: userId) != nil
    }

    /// 移除钱包仅删除本机存储，不影响链上资产——助记词没有单独备份的话真的找不回来了，
    /// 调用方必须在用户已经确认备份过的前提下才能调这个。
    func removeMnemonic(forUserId userId: Int64) {
        keychain.remove("\(mnemonicKeyPrefix)\(userId)")
    }
}
