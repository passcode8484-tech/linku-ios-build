import Foundation

/// 跟 android-native data/remote/E2eeApi.kt 逐接口对应。服务端 E2eeController 早就全套做好了
/// （只存公钥，服务端物理上读不到明文），不需要服务端配合改一行代码。
struct E2eeApi {
    let client: ApiClient

    func registerDevice(userId: Int64, deviceId: String, registrationId: Int, identityKeyPublic: String) async throws {
        let response: ApiResponse<E2eeDeviceView> = try await client.postForm(
            "/api/im/e2ee/devices/register",
            fields: [
                "userId": String(userId),
                "deviceId": deviceId,
                "registrationId": String(registrationId),
                "identityKeyPublic": identityKeyPublic,
            ]
        )
        _ = try response.dataOrThrow()
    }

    /// oneTimePreKeys 是 JSON 数组字符串：[{"keyId":1,"publicKey":"<base64>"},...]。
    func uploadPreKeys(
        userId: Int64,
        deviceId: String,
        signedPreKeyId: Int,
        signedPreKeyPublic: String,
        signedPreKeySignature: String,
        oneTimePreKeys: String,
        kyberPreKeyId: Int?,
        kyberPreKeyPublic: String?,
        kyberPreKeySignature: String?
    ) async throws {
        let response: ApiResponse<EmptyData> = try await client.postForm(
            "/api/im/e2ee/prekeys/upload",
            fields: [
                "userId": String(userId),
                "deviceId": deviceId,
                "signedPreKeyId": String(signedPreKeyId),
                "signedPreKeyPublic": signedPreKeyPublic,
                "signedPreKeySignature": signedPreKeySignature,
                "oneTimePreKeys": oneTimePreKeys,
                "kyberPreKeyId": kyberPreKeyId.map(String.init),
                "kyberPreKeyPublic": kyberPreKeyPublic,
                "kyberPreKeySignature": kyberPreKeySignature,
            ]
        )
        try response.throwIfFailed()
    }

    /// 取一个 One-Time PreKey 建会话——服务端会把这个 key 标记成已用，同一个 key 不会发两次。
    func fetchPreKeyBundle(targetUserId: Int64, deviceId: String? = nil) async throws -> E2eePreKeyBundleView {
        try await client.getJSON(
            "/api/im/e2ee/prekeys/bundle",
            query: ["targetUserId": String(targetUserId), "deviceId": deviceId]
        ).dataOrThrow()
    }

    /// 跟 fetchPreKeyBundle 一样但不消耗 One-Time PreKey——只用来核对身份/签名，不建会话。
    func peekPreKeyBundle(targetUserId: Int64, deviceId: String? = nil) async throws -> E2eePreKeyBundleView {
        try await client.getJSON(
            "/api/im/e2ee/prekeys/bundle/peek",
            query: ["targetUserId": String(targetUserId), "deviceId": deviceId]
        ).dataOrThrow()
    }

    func listDevices(userId: Int64) async throws -> [E2eeDeviceView] {
        try await client.getJSON("/api/im/e2ee/devices", query: ["userId": String(userId)]).dataOrThrow()
    }
}
