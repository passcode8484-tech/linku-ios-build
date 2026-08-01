import Foundation

/// 跟 android-native remote/dto/FriendDtos.kt 逐字段对应。
struct FriendView: Codable, Equatable, Identifiable {
    let friendUserId: Int64
    let friendPublicUid: String
    let friendLinkId: String?
    let nickname: String
    let avatar: String?
    let remark: String?
    let username: String?
    let status: String?
    let blocked: Bool
    let createdAt: String?

    var id: Int64 { friendUserId }

    var displayName: String {
        if let remark, !remark.isEmpty { return remark }
        return nickname
    }

    // `blocked` 在服务端是带默认值的字段，Kotlin 那边缺省时会当 false 处理；
    // Swift 的 Codable 对非 Optional 字段缺省 key 会直接抛错，手动兜底成 false 保持一致行为。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        friendUserId = try container.decode(Int64.self, forKey: .friendUserId)
        friendPublicUid = try container.decode(String.self, forKey: .friendPublicUid)
        friendLinkId = try container.decodeIfPresent(String.self, forKey: .friendLinkId)
        nickname = try container.decode(String.self, forKey: .nickname)
        avatar = try container.decodeIfPresent(String.self, forKey: .avatar)
        remark = try container.decodeIfPresent(String.self, forKey: .remark)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        blocked = try container.decodeIfPresent(Bool.self, forKey: .blocked) ?? false
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }

    init(
        friendUserId: Int64,
        friendPublicUid: String,
        friendLinkId: String?,
        nickname: String,
        avatar: String?,
        remark: String?,
        username: String?,
        status: String?,
        blocked: Bool,
        createdAt: String?
    ) {
        self.friendUserId = friendUserId
        self.friendPublicUid = friendPublicUid
        self.friendLinkId = friendLinkId
        self.nickname = nickname
        self.avatar = avatar
        self.remark = remark
        self.username = username
        self.status = status
        self.blocked = blocked
        self.createdAt = createdAt
    }
}

struct FriendRequestView: Codable, Equatable, Identifiable {
    let id: Int64
    let fromUserId: Int64
    let fromNickname: String
    let fromAvatar: String?
    let message: String?
    let status: String
    let createdAt: String?
}

struct UserSearchView: Codable, Equatable, Identifiable {
    let publicUid: String
    let linkId: String?
    let nickname: String
    let avatar: String?
    let username: String?

    var id: String { publicUid }
}
