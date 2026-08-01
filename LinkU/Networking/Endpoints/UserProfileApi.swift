import Foundation

/// 跟 android-native data/remote/UserProfileApi.kt 逐接口对应——M10 的账号资料/隐私/安全设置。
struct UserProfileApi {
    let client: ApiClient

    func getPrivacy(userId: Int64) async throws -> UserPrivacyView {
        try await client.getJSON(
            "/api/user/profile/privacy",
            query: ["userId": String(userId)]
        ).dataOrThrow()
    }

    func updatePrivacy(
        userId: Int64,
        allowSearchByLinkId: Bool? = nil,
        allowSearchByPhone: Bool? = nil,
        allowSearchByEmail: Bool? = nil,
        allowFriendRequestFrom: String? = nil,
        allowReadReceipt: Bool? = nil
    ) async throws -> UserPrivacyView {
        try await client.postForm(
            "/api/user/profile/privacy",
            fields: [
                "userId": String(userId),
                "allowSearchByLinkId": allowSearchByLinkId.map(String.init),
                "allowSearchByPhone": allowSearchByPhone.map(String.init),
                "allowSearchByEmail": allowSearchByEmail.map(String.init),
                "allowFriendRequestFrom": allowFriendRequestFrom,
                "allowReadReceipt": allowReadReceipt.map(String.init),
            ]
        ).dataOrThrow()
    }

    func setNickname(userId: Int64, nickname: String) async throws -> UserView {
        try await client.postForm(
            "/api/user/profile/nickname",
            fields: ["userId": String(userId), "nickname": nickname]
        ).dataOrThrow()
    }

    func uploadAvatar(userId: Int64, fileData: Data, fileName: String, mimeType: String) async throws -> UserView {
        try await client.uploadMultipart(
            "/api/user/profile/avatar",
            fields: ["userId": String(userId)],
            fileFieldName: "file",
            fileData: fileData,
            fileName: fileName,
            mimeType: mimeType
        ).dataOrThrow()
    }

    func setLinkId(userId: Int64, linkId: String) async throws -> UserView {
        try await client.postForm(
            "/api/user/profile/link-id",
            fields: ["userId": String(userId), "linkId": linkId]
        ).dataOrThrow()
    }

    func changePhone(userId: Int64, phone: String, code: String) async throws -> UserView {
        try await client.postForm(
            "/api/user/profile/phone",
            fields: ["userId": String(userId), "phone": phone, "code": code]
        ).dataOrThrow()
    }

    func changeEmail(userId: Int64, email: String, code: String) async throws -> UserView {
        try await client.postForm(
            "/api/user/profile/email",
            fields: ["userId": String(userId), "email": email, "code": code]
        ).dataOrThrow()
    }

    func changePassword(userId: Int64, oldPassword: String?, newPassword: String) async throws -> UserView {
        try await client.postForm(
            "/api/user/profile/password",
            fields: ["userId": String(userId), "oldPassword": oldPassword, "newPassword": newPassword]
        ).dataOrThrow()
    }
}
