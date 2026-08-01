import FirebaseMessaging
import Foundation

/// 对应 android-native data/push/PushTokenManager.kt。FCM 只有在真正接入 Firebase 项目
/// （GoogleService-Info.plist 配好、Firebase 控制台上传了 APNs Auth Key）之后才能拿到 token——
/// 在那之前这里的调用会静默失败，不影响其余功能正常使用。
@MainActor
final class PushTokenManager {
    private let sessionStore: SessionStore
    private let pushRepository: PushRepository

    init(sessionStore: SessionStore, pushRepository: PushRepository) {
        self.sessionStore = sessionStore
        self.pushRepository = pushRepository
    }

    func ensureRegistered() async {
        guard let userId = sessionStore.user?.id else { return }
        guard let token = await fetchToken() else { return }
        await pushRepository.register(userId: userId, deviceToken: token)
    }

    /// MessagingDelegate.didReceiveRegistrationToken 回调转发过来的新 token。
    func onNewToken(_ token: String) async {
        guard let userId = sessionStore.user?.id else { return }
        await pushRepository.register(userId: userId, deviceToken: token)
    }

    /// 用 completion-handler API 包一层 continuation，而不是指望 Swift 自动把
    /// `tokenWithCompletion:` 桥接成 `async throws` 版本——两种写法运行时行为一样，
    /// 但这样不用赌自动桥接在这个具体 SDK 版本上一定生效。
    private func fetchToken() async -> String? {
        await withCheckedContinuation { continuation in
            Messaging.messaging().token { token, _ in
                continuation.resume(returning: token)
            }
        }
    }
}
