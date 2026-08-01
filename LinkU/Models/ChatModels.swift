import Foundation

/// 跟 android-native remote/dto/ChatDtos.kt 逐字段对应。群聊相关字段留到 M5 再加。
struct ConversationCreateResult: Codable, Equatable {
    let id: Int64
}

struct MessageReactionView: Codable, Equatable {
    let messageId: Int64
    let reaction: String
    let count: Int64
}

struct PinnedMessageView: Codable, Equatable, Identifiable {
    let messageId: Int64
    let conversationId: Int64
    let senderUserId: Int64
    let content: String?
    let operatorUserId: Int64?
    let pinnedAt: String?

    var id: Int64 { messageId }
}

struct FavoriteMessageView: Codable, Equatable, Identifiable {
    let messageId: Int64
    let conversationId: Int64
    let senderUserId: Int64
    let messageType: String?
    var content: String?
    let messageCreatedAt: String?
    let favoriteCreatedAt: String?
    var note: String?
    var noteUpdatedAt: String?

    var id: Int64 { messageId }
}

struct MessageReceiptView: Codable, Equatable {
    let messageId: Int64
    let userId: Int64
    let status: String
    let updatedAt: String?
}

struct TypingEvent: Codable, Equatable {
    let conversationId: Int64
    let userId: Int64
    let typing: Bool
}

struct GroupAnnouncementView: Codable, Equatable {
    let conversationId: Int64
    let content: String?
    let operatorUserId: Int64?
    let updatedAt: String?
}

struct GroupInviteTokenView: Codable, Equatable {
    let conversationId: Int64
    let token: String
    let expiresAt: String?
}

struct GroupInvitePreviewView: Codable, Equatable {
    let conversationId: Int64
    let title: String
    let avatar: String?
    let memberCount: Int
    let alreadyMember: Bool
    let joinPolicy: String

    enum CodingKeys: String, CodingKey {
        case conversationId, title, avatar, memberCount, alreadyMember, joinPolicy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        conversationId = try container.decode(Int64.self, forKey: .conversationId)
        title = try container.decode(String.self, forKey: .title)
        avatar = try container.decodeIfPresent(String.self, forKey: .avatar)
        memberCount = try container.decodeIfPresent(Int.self, forKey: .memberCount) ?? 0
        alreadyMember = try container.decodeIfPresent(Bool.self, forKey: .alreadyMember) ?? false
        joinPolicy = try container.decodeIfPresent(String.self, forKey: .joinPolicy) ?? "APPROVAL"
    }
}

struct GroupJoinRequestView: Codable, Equatable, Identifiable {
    let id: Int64
    let conversationId: Int64
    let userId: Int64
    let nickname: String?
    let avatar: String?
    let message: String?
    let status: String
    let createdAt: String?
}

struct MediaUploadView: Codable, Equatable {
    let objectKey: String
    let size: Int64
}

struct ConversationMemberView: Codable, Equatable, Identifiable {
    let userId: Int64
    let role: String
    let nickname: String?
    let avatar: String?
    let mutedUntil: String?
    let joinedAt: String?

    var id: Int64 { userId }
}

struct ConversationDetail: Codable, Equatable {
    let id: Int64
    let type: String
    let title: String
    let avatar: String?
    let unreadCount: Int
    let pinned: Bool
    let muted: Bool
    let draftText: String?
    let members: [ConversationMemberView]
    let online: Bool
    let joinPolicy: String?

    enum CodingKeys: String, CodingKey {
        case id, type, title, avatar, unreadCount, pinned, muted, draftText, members, online, joinPolicy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        title = try container.decode(String.self, forKey: .title)
        avatar = try container.decodeIfPresent(String.self, forKey: .avatar)
        unreadCount = try container.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
        pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        muted = try container.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        draftText = try container.decodeIfPresent(String.self, forKey: .draftText)
        members = try container.decodeIfPresent([ConversationMemberView].self, forKey: .members) ?? []
        online = try container.decodeIfPresent(Bool.self, forKey: .online) ?? false
        joinPolicy = try container.decodeIfPresent(String.self, forKey: .joinPolicy)
    }
}

struct ConversationSummary: Codable, Equatable, Identifiable {
    let id: Int64
    let type: String // "SINGLE" | "GROUP"
    let title: String
    let avatar: String?
    let lastMessage: String?
    let lastMessageType: String?
    let unreadCount: Int
    let pinned: Bool
    let muted: Bool
    let draftText: String?
    let peerUserId: Int64?
    let updatedAt: String?
    let online: Bool

    enum CodingKeys: String, CodingKey {
        case id, type, title, avatar, lastMessage, lastMessageType, unreadCount, pinned, muted
        case draftText, peerUserId, updatedAt, online
    }

    // 服务端好几个字段带默认值，缺省时按同样的默认值兜底（跟 FriendView.blocked 一个道理）。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        title = try container.decode(String.self, forKey: .title)
        avatar = try container.decodeIfPresent(String.self, forKey: .avatar)
        lastMessage = try container.decodeIfPresent(String.self, forKey: .lastMessage)
        lastMessageType = try container.decodeIfPresent(String.self, forKey: .lastMessageType)
        unreadCount = try container.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0
        pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        muted = try container.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        draftText = try container.decodeIfPresent(String.self, forKey: .draftText)
        peerUserId = try container.decodeIfPresent(Int64.self, forKey: .peerUserId)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        online = try container.decodeIfPresent(Bool.self, forKey: .online) ?? false
    }
}

struct MessageView: Codable, Equatable, Identifiable {
    let id: Int64
    let conversationId: Int64
    let senderUserId: Int64
    let senderNickname: String?
    let senderAvatar: String?
    let type: String
    let content: String
    let status: String?
    let replyMessageId: Int64?
    let recalled: Bool
    let policyMode: String?
    let policyTtlSec: Int?
    let policyBurnDelaySec: Int?
    let policyExpireAt: String?
    let mentionedUserIds: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, conversationId, senderUserId, senderNickname, senderAvatar, type, content, status
        case replyMessageId, recalled, policyMode, policyTtlSec, policyBurnDelaySec, policyExpireAt
        case mentionedUserIds, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        conversationId = try container.decode(Int64.self, forKey: .conversationId)
        senderUserId = try container.decode(Int64.self, forKey: .senderUserId)
        senderNickname = try container.decodeIfPresent(String.self, forKey: .senderNickname)
        senderAvatar = try container.decodeIfPresent(String.self, forKey: .senderAvatar)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "TEXT"
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status)
        replyMessageId = try container.decodeIfPresent(Int64.self, forKey: .replyMessageId)
        recalled = try container.decodeIfPresent(Bool.self, forKey: .recalled) ?? false
        policyMode = try container.decodeIfPresent(String.self, forKey: .policyMode)
        policyTtlSec = try container.decodeIfPresent(Int.self, forKey: .policyTtlSec)
        policyBurnDelaySec = try container.decodeIfPresent(Int.self, forKey: .policyBurnDelaySec)
        policyExpireAt = try container.decodeIfPresent(String.self, forKey: .policyExpireAt)
        mentionedUserIds = try container.decodeIfPresent(String.self, forKey: .mentionedUserIds)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }
}

/// WS "MESSAGE_LIFECYCLE" 事件负载——阅后即焚消息被对方读过之后，服务端广播这个通知发送方也该
/// 定时清掉自己那份了（发送方这份不会自动过期，靠这条广播才知道具体到期时间）。
struct MessageLifecycleView: Codable, Equatable {
    let messageId: Int64
    let conversationId: Int64
    let action: String
    let expireAt: String?
    let reason: String?
}

/// WS "MESSAGE_PURGED" 事件负载——手动"删除给所有人"、TTL 到期、阅后即焚到期三条路径共用同一个广播。
struct MessagePurgedView: Codable, Equatable {
    let messageId: Int64
    let conversationId: Int64
    let operatorUserId: Int64?
    let reason: String?
}
