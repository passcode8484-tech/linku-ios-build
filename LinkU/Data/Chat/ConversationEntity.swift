import Foundation
import SwiftData

/// 本地会话表，对应 android-native data/local/ 里的 Conversation 相关 Room entity。
/// 群聊(type == "GROUP")相关字段留到 M5 用到时再加。
@Model
final class ConversationEntity {
    @Attribute(.unique) var id: Int64
    var type: String
    var title: String
    var avatar: String?
    var lastMessage: String?
    var lastMessageType: String?
    var unreadCount: Int
    var pinned: Bool
    var muted: Bool
    var draftText: String?
    var peerUserId: Int64?
    var updatedAt: String?
    var online: Bool

    init(from view: ConversationSummary) {
        id = view.id
        type = view.type
        title = view.title
        avatar = view.avatar
        lastMessage = view.lastMessage
        lastMessageType = view.lastMessageType
        unreadCount = view.unreadCount
        pinned = view.pinned
        muted = view.muted
        draftText = view.draftText
        peerUserId = view.peerUserId
        updatedAt = view.updatedAt
        online = view.online
    }

    func update(from view: ConversationSummary) {
        type = view.type
        title = view.title
        avatar = view.avatar
        lastMessage = view.lastMessage
        lastMessageType = view.lastMessageType
        unreadCount = view.unreadCount
        pinned = view.pinned
        muted = view.muted
        draftText = view.draftText
        peerUserId = view.peerUserId
        updatedAt = view.updatedAt
        online = view.online
    }
}
