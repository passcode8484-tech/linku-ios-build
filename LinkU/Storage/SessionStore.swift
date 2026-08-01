import Foundation

/// 对应 android-native data/auth/SessionStore.kt。跟安卓那边"token 也是明文存 DataStore，
/// 只有钱包助记词才上 EncryptedSharedPreferences"的取舍不同——iOS 上 Keychain 几乎零成本，
/// 所以这里 token 直接放 Keychain；user 资料/上次登录账号这些非敏感信息仍用 UserDefaults，
/// 跟安卓一样"退出登录后账号还留着，方便直接重新输密码"。
@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var token: String?
    @Published private(set) var user: UserView?
    @Published private(set) var lastAccount: String?

    private let keychain = KeychainStore()
    private let defaults = UserDefaults.standard
    private let userDefaultsKey = "linku.session.user"
    private let lastAccountKey = "linku.session.lastAccount"
    private let tokenKeychainKey = "linku.session.token"
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init() {
        self.token = keychain.get(tokenKeychainKey)
        self.lastAccount = defaults.string(forKey: lastAccountKey)
        if let raw = defaults.data(forKey: userDefaultsKey) {
            self.user = try? decoder.decode(UserView.self, from: raw)
        }
    }

    func save(token: String, user: UserView, account: String? = nil) {
        keychain.set(token, forKey: tokenKeychainKey)
        self.token = token
        updateUser(user)
        if let account, !account.trimmingCharacters(in: .whitespaces).isEmpty {
            defaults.set(account, forKey: lastAccountKey)
            self.lastAccount = account
        }
    }

    /// 改昵称/头像这类资料更新只换缓存的 user，不涉及 token。
    func updateUser(_ user: UserView) {
        self.user = user
        if let data = try? encoder.encode(user) {
            defaults.set(data, forKey: userDefaultsKey)
        }
    }

    /// 只清会话，不清 lastAccount——退出登录后登录页还能预填上次的账号。
    func clear() {
        keychain.remove(tokenKeychainKey)
        token = nil
        user = nil
        defaults.removeObject(forKey: userDefaultsKey)
    }
}

extension SessionStore: AuthTokenProviding {
    func currentToken() async -> String? { token }
}
