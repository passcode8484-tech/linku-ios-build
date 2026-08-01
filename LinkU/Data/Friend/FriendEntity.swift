import Foundation
import SwiftData

/// 本地缓存表，对应 android-native data/local/FriendDao.kt 背后的 Room entity。
@Model
final class FriendEntity {
    @Attribute(.unique) var friendUserId: Int64
    var friendPublicUid: String
    var friendLinkId: String?
    var nickname: String
    var avatar: String?
    var remark: String?
    var username: String?
    var status: String?
    var blocked: Bool
    var createdAt: String?

    init(from view: FriendView) {
        friendUserId = view.friendUserId
        friendPublicUid = view.friendPublicUid
        friendLinkId = view.friendLinkId
        nickname = view.nickname
        avatar = view.avatar
        remark = view.remark
        username = view.username
        status = view.status
        blocked = view.blocked
        createdAt = view.createdAt
    }

    var displayName: String {
        if let remark, !remark.isEmpty { return remark }
        return nickname
    }
}

/// 本地缓存表，对应 android-native FriendRequestDao.kt。只 upsert 不整表替换——
/// 服务端只回传当前 PENDING 的请求，upsert 才能让本地保留住"之前处理过什么"这份记录。
@Model
final class FriendRequestEntity {
    @Attribute(.unique) var id: Int64
    var fromUserId: Int64
    var fromNickname: String
    var fromAvatar: String?
    var message: String?
    var status: String
    var createdAt: String?

    init(from view: FriendRequestView) {
        id = view.id
        fromUserId = view.fromUserId
        fromNickname = view.fromNickname
        fromAvatar = view.fromAvatar
        message = view.message
        status = view.status
        createdAt = view.createdAt
    }

    func update(from view: FriendRequestView) {
        fromNickname = view.fromNickname
        fromAvatar = view.fromAvatar
        message = view.message
        status = view.status
        createdAt = view.createdAt
    }
}
