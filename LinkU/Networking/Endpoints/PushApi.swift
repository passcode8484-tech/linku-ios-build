import Foundation

/// 跟 android-native data/remote/PushApi.kt 对应。
struct PushApi {
    let client: ApiClient

    func register(userId: Int64, deviceToken: String, platform: String = "ios", provider: String = "fcm") async throws {
        let response: ApiResponse<EmptyData> = try await client.postForm(
            "/api/push/register",
            fields: ["userId": String(userId), "deviceToken": deviceToken, "platform": platform, "provider": provider]
        )
        try response.throwIfFailed()
    }

    func unregister(userId: Int64, deviceToken: String) async throws {
        let response: ApiResponse<EmptyData> = try await client.postForm(
            "/api/push/unregister",
            fields: ["userId": String(userId), "deviceToken": deviceToken]
        )
        try response.throwIfFailed()
    }
}
