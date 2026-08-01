import Foundation

/// 跟 android-native remote/dto/AuthDtos.kt 逐字段对应。
struct UserView: Codable, Equatable, Identifiable {
    let id: Int64
    let publicUid: String
    let linkId: String?
    let linkIdChangedAt: String?
    let username: String?
    let email: String?
    let phone: String?
    let nickname: String
    let avatar: String?
    let momentsCover: String?
    let status: String
    let createdAt: String?
}

struct AuthResult: Codable, Equatable {
    let token: String
    let loginType: String
    let expiresAt: String?
    let user: UserView
}

struct VerificationCodeResult: Codable, Equatable {
    let target: String
    let type: String
    let scene: String
    let expiresAt: String?
    let debugCode: String?
}

struct UserPrivacyView: Codable, Equatable {
    let allowSearchByLinkId: Bool
    let allowSearchByPhone: Bool
    let allowSearchByEmail: Bool
    let allowFriendRequestFrom: String?
    let allowReadReceipt: Bool
}
