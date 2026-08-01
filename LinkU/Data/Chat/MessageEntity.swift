import Foundation
import SwiftData

/// 本地消息表。`content` 原样存服务端字段(单聊是 E2EE 密文信封 JSON)，`plaintext` 是收到/发出时
/// 就解密好缓存下来的展示文本——聊天页直接读 plaintext，不用每次进页面重新解密一遍。
/// 消息操作(回复/撤回/编辑/表情/置顶)相关字段留到 M4 用到时再加。
@Model
final class MessageEntity {
    @Attribute(.unique) var id: Int64
    var conversationId: Int64
    var senderUserId: Int64
    var senderNickname: String?
    var senderAvatar: String?
    var type: String
    var content: String
    var plaintext: String?
    var status: String?
    var replyMessageId: Int64?
    var recalled: Bool
    var policyMode: String?
    var policyExpireAt: String?
    var createdAt: String?

    init(from view: MessageView, plaintext: String?) {
        id = view.id
        conversationId = view.conversationId
        senderUserId = view.senderUserId
        senderNickname = view.senderNickname
        senderAvatar = view.senderAvatar
        type = view.type
        content = view.content
        self.plaintext = plaintext
        status = view.status
        replyMessageId = view.replyMessageId
        recalled = view.recalled
        policyMode = view.policyMode
        policyExpireAt = view.policyExpireAt
        createdAt = view.createdAt
    }

    func update(from view: MessageView, plaintext: String?) {
        senderNickname = view.senderNickname
        senderAvatar = view.senderAvatar
        type = view.type
        content = view.content
        self.plaintext = plaintext
        status = view.status
        replyMessageId = view.replyMessageId
        recalled = view.recalled
        policyMode = view.policyMode
        policyExpireAt = view.policyExpireAt
        createdAt = view.createdAt
    }
}
