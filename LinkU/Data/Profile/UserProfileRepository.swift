import Foundation

/// 资料/隐私/账号安全相关的写操作统一入口——跟 android ProfileViewModel/EditProfileViewModel/
/// AccountSecuritySettings 那几个 ViewModel 揉在一起的精简版，UI 层不用分别记住每个接口成功后
/// 要不要顺手刷新 sessionStore.user（全部在这里做，改完资料本地缓存立刻跟上）。
@MainActor
final class UserProfileRepository {
    private let api: UserProfileApi
    private let sessionStore: SessionStore

    init(api: UserProfileApi, sessionStore: SessionStore) {
        self.api = api
        self.sessionStore = sessionStore
    }

    private func requireUserId() throws -> Int64 {
        guard let id = sessionStore.user?.id else { throw ApiException(code: -1, apiMessage: "未登录") }
        return id
    }

    func fetchPrivacy() async throws -> UserPrivacyView {
        try await api.getPrivacy(userId: try requireUserId())
    }

    @discardableResult
    func updatePrivacy(
        allowSearchByLinkId: Bool? = nil,
        allowSearchByPhone: Bool? = nil,
        allowSearchByEmail: Bool? = nil,
        allowFriendRequestFrom: String? = nil,
        allowReadReceipt: Bool? = nil
    ) async throws -> UserPrivacyView {
        try await api.updatePrivacy(
            userId: try requireUserId(),
            allowSearchByLinkId: allowSearchByLinkId,
            allowSearchByPhone: allowSearchByPhone,
            allowSearchByEmail: allowSearchByEmail,
            allowFriendRequestFrom: allowFriendRequestFrom,
            allowReadReceipt: allowReadReceipt
        )
    }

    func setNickname(_ nickname: String) async throws {
        let user = try await api.setNickname(userId: try requireUserId(), nickname: nickname)
        sessionStore.updateUser(user)
    }

    func uploadAvatar(fileData: Data, fileName: String, mimeType: String) async throws {
        let user = try await api.uploadAvatar(
            userId: try requireUserId(), fileData: fileData, fileName: fileName, mimeType: mimeType
        )
        sessionStore.updateUser(user)
    }

    func setLinkId(_ linkId: String) async throws {
        let user = try await api.setLinkId(userId: try requireUserId(), linkId: linkId)
        sessionStore.updateUser(user)
    }

    func changePhone(phone: String, code: String) async throws {
        let user = try await api.changePhone(userId: try requireUserId(), phone: phone, code: code)
        sessionStore.updateUser(user)
    }

    func changeEmail(email: String, code: String) async throws {
        let user = try await api.changeEmail(userId: try requireUserId(), email: email, code: code)
        sessionStore.updateUser(user)
    }

    func changePassword(oldPassword: String?, newPassword: String) async throws {
        let user = try await api.changePassword(userId: try requireUserId(), oldPassword: oldPassword, newPassword: newPassword)
        sessionStore.updateUser(user)
    }
}
