import Foundation

/// 跟 android-native data/push/PushRepository.kt 对应，薄封装。
@MainActor
final class PushRepository {
    private let api: PushApi

    init(api: PushApi) {
        self.api = api
    }

    func register(userId: Int64, deviceToken: String, provider: String = "fcm") async {
        try? await api.register(userId: userId, deviceToken: deviceToken, provider: provider)
    }

    func unregister(userId: Int64, deviceToken: String) async {
        try? await api.unregister(userId: userId, deviceToken: deviceToken)
    }
}
