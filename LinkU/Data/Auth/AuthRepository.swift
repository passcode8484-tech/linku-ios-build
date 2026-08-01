import Foundation

/// 对应 android-native data/auth/AuthRepository.kt。邀请码归因（InviteAttributionStore）
/// 等归因相关逻辑不在 M1 范围内，先留 TODO，不在这里假装实现。
@MainActor
final class AuthRepository {
    private let api: AuthApi
    private let sessionStore: SessionStore
    private let chatSocketClient: ChatSocketClient

    init(api: AuthApi, sessionStore: SessionStore, chatSocketClient: ChatSocketClient) {
        self.api = api
        self.sessionStore = sessionStore
        self.chatSocketClient = chatSocketClient
    }

    func sendCode(account: String, kind: AuthAccountKind, scene: String) async throws -> VerificationCodeResult {
        switch kind {
        case .email: return try await api.sendEmailCode(email: account, scene: scene)
        case .phone: return try await api.sendPhoneCode(phone: account, scene: scene)
        }
    }

    func register(
        account: String,
        kind: AuthAccountKind,
        code: String,
        password: String?,
        nickname: String?
    ) async throws -> AuthResult {
        // TODO(attribution): inviteCode 归因等 InviteAttributionStore 落地后接入，现在固定传 nil。
        let result: AuthResult
        switch kind {
        case .email:
            result = try await api.register(
                username: nil, email: account, phone: nil,
                password: password, code: code, nickname: nickname, inviteCode: nil
            )
        case .phone:
            result = try await api.register(
                username: nil, email: nil, phone: account,
                password: password, code: code, nickname: nickname, inviteCode: nil
            )
        }
        sessionStore.save(token: result.token, user: result.user, account: account)
        chatSocketClient.connect(token: result.token)
        return result
    }

    func loginByPassword(account: String, password: String) async throws -> AuthResult {
        let result = try await api.loginByPassword(account: account, password: password)
        sessionStore.save(token: result.token, user: result.user, account: account)
        chatSocketClient.connect(token: result.token)
        return result
    }

    func loginByCode(account: String, kind: AuthAccountKind, code: String) async throws -> AuthResult {
        let result: AuthResult
        switch kind {
        case .email: result = try await api.loginByEmailCode(email: account, code: code)
        case .phone: result = try await api.loginByPhoneCode(phone: account, code: code)
        }
        sessionStore.save(token: result.token, user: result.user, account: account)
        chatSocketClient.connect(token: result.token)
        return result
    }

    /// 本地缓存（会话/联系人/聊天记录）退出登录后不清——跟微信一样，重新登录同一账号还能立刻看到。
    @discardableResult
    func restoreSession() async -> AuthResult? {
        guard let token = sessionStore.token else { return nil }
        do {
            let result = try await api.currentSession()
            chatSocketClient.connect(token: token)
            return result
        } catch {
            sessionStore.clear()
            return nil
        }
    }

    func logout() async {
        if sessionStore.token != nil {
            try? await api.logout()
        }
        sessionStore.clear()
        chatSocketClient.disconnect()
    }
}
