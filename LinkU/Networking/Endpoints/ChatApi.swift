import Foundation

/// 跟 android-native data/remote/ChatApi.kt 对应，M3/M4/M5 用到的接口。收藏/搜索/群公告/
/// 群角色管理/入群申请/邀请链接这些留到之后用到时再加。
struct ChatApi {
    let client: ApiClient

    func listConversations(userId: Int64, archived: Bool = false, limit: Int = 20) async throws -> [ConversationSummary] {
        try await client.getJSON(
            "/api/im/conversations",
            query: ["userId": String(userId), "archived": String(archived), "limit": String(limit)]
        ).dataOrThrow()
    }

    func createSingleConversation(ownerUserId: Int64, peerUserId: Int64, title: String) async throws -> ConversationCreateResult {
        try await client.postForm(
            "/api/im/conversations/single",
            fields: ["ownerUserId": String(ownerUserId), "peerUserId": String(peerUserId), "title": title]
        ).dataOrThrow()
    }

    func createGroupConversation(ownerUserId: Int64, title: String, memberUserIds: [Int64]) async throws -> ConversationCreateResult {
        try await client.postForm(
            "/api/im/conversations/group",
            fields: [
                "ownerUserId": String(ownerUserId), "title": title,
                "memberUserIds": memberUserIds.map(String.init).joined(separator: ","),
            ]
        ).dataOrThrow()
    }

    func conversationDetail(conversationId: Int64, userId: Int64) async throws -> ConversationDetail {
        try await client.getJSON(
            "/api/im/conversations/detail",
            query: ["conversationId": String(conversationId), "userId": String(userId)]
        ).dataOrThrow()
    }

    func listMessages(conversationId: Int64, userId: Int64, beforeId: Int64? = nil, limit: Int = 30) async throws -> [MessageView] {
        try await client.getJSON(
            "/api/im/messages",
            query: [
                "conversationId": String(conversationId),
                "userId": String(userId),
                "beforeId": beforeId.map(String.init),
                "limit": String(limit),
            ]
        ).dataOrThrow()
    }

    func sendMessage(
        conversationId: Int64,
        senderUserId: Int64,
        type: String = "TEXT",
        content: String,
        replyMessageId: Int64? = nil,
        policyMode: String? = nil,
        policyTtlSec: Int? = nil,
        policyBurnDelaySec: Int? = nil,
        mentionedUserIds: String? = nil
    ) async throws -> MessageView {
        try await client.postForm(
            "/api/im/messages/send",
            fields: [
                "conversationId": String(conversationId),
                "senderUserId": String(senderUserId),
                "type": type,
                "content": content,
                "replyMessageId": replyMessageId.map(String.init),
                "policyMode": policyMode,
                "policyTtlSec": policyTtlSec.map(String.init),
                "policyBurnDelaySec": policyBurnDelaySec.map(String.init),
                "mentionedUserIds": mentionedUserIds,
            ]
        ).dataOrThrow()
    }

    func purgeForEveryone(conversationId: Int64, messageId: Int64, userId: Int64) async throws -> Int {
        try await client.postForm(
            "/api/im/messages/purge",
            fields: ["conversationId": String(conversationId), "messageId": String(messageId), "userId": String(userId)]
        ).dataOrThrow()
    }

    func notifyMessageExpired(conversationId: Int64, messageId: Int64, userId: Int64, reason: String) async throws -> Int {
        try await client.postForm(
            "/api/im/messages/lifecycle/notify",
            fields: [
                "conversationId": String(conversationId), "messageId": String(messageId),
                "userId": String(userId), "reason": reason,
            ]
        ).dataOrThrow()
    }

    func markRead(conversationId: Int64, userId: Int64) async throws {
        let response: ApiResponse<Int> = try await client.postForm(
            "/api/im/messages/read",
            fields: ["conversationId": String(conversationId), "userId": String(userId)]
        )
        _ = try response.dataOrThrow()
    }

    func updateReceipt(conversationId: Int64, messageId: Int64, userId: Int64, status: String) async throws -> MessageReceiptView {
        try await client.postForm(
            "/api/im/messages/receipt",
            fields: [
                "conversationId": String(conversationId), "messageId": String(messageId),
                "userId": String(userId), "status": status,
            ]
        ).dataOrThrow()
    }

    func typing(conversationId: Int64, userId: Int64, typing: Bool) async throws {
        let response: ApiResponse<TypingEvent> = try await client.postForm(
            "/api/im/messages/typing",
            fields: ["conversationId": String(conversationId), "userId": String(userId), "typing": String(typing)]
        )
        _ = try response.dataOrThrow()
    }

    // MARK: - 消息操作 (M4)

    /// 返回受影响行数——服务端超过 2 分钟撤回窗口或非本人消息时会静默返回 0，不能当成功处理。
    func recallMessage(messageId: Int64, userId: Int64) async throws -> Int {
        try await client.postForm(
            "/api/im/messages/recall",
            fields: ["messageId": String(messageId), "userId": String(userId)]
        ).dataOrThrow()
    }

    func editMessage(conversationId: Int64, messageId: Int64, userId: Int64, content: String) async throws -> MessageView {
        try await client.postForm(
            "/api/im/messages/edit",
            fields: [
                "conversationId": String(conversationId), "messageId": String(messageId),
                "userId": String(userId), "content": content,
            ]
        ).dataOrThrow()
    }

    func addReaction(conversationId: Int64, messageId: Int64, userId: Int64, reaction: String) async throws -> [MessageReactionView] {
        try await client.postForm(
            "/api/im/messages/reaction/add",
            fields: [
                "conversationId": String(conversationId), "messageId": String(messageId),
                "userId": String(userId), "reaction": reaction,
            ]
        ).dataOrThrow()
    }

    func removeReaction(conversationId: Int64, messageId: Int64, userId: Int64, reaction: String) async throws -> [MessageReactionView] {
        try await client.postForm(
            "/api/im/messages/reaction/remove",
            fields: [
                "conversationId": String(conversationId), "messageId": String(messageId),
                "userId": String(userId), "reaction": reaction,
            ]
        ).dataOrThrow()
    }

    func pinMessage(conversationId: Int64, messageId: Int64, operatorUserId: Int64) async throws -> [PinnedMessageView] {
        try await client.postForm(
            "/api/im/messages/pin",
            fields: [
                "conversationId": String(conversationId), "messageId": String(messageId),
                "operatorUserId": String(operatorUserId),
            ]
        ).dataOrThrow()
    }

    func unpinMessage(conversationId: Int64, messageId: Int64) async throws -> [PinnedMessageView] {
        try await client.postForm(
            "/api/im/messages/unpin",
            fields: ["conversationId": String(conversationId), "messageId": String(messageId)]
        ).dataOrThrow()
    }

    func pinnedMessages(conversationId: Int64, limit: Int = 10) async throws -> [PinnedMessageView] {
        try await client.getJSON(
            "/api/im/messages/pinned",
            query: ["conversationId": String(conversationId), "limit": String(limit)]
        ).dataOrThrow()
    }

    // MARK: - 媒体 (M4)

    func uploadMedia(conversationId: Int64, userId: Int64, fileData: Data, fileName: String, mimeType: String) async throws -> MediaUploadView {
        try await client.uploadMultipart(
            "/api/im/media/upload",
            fields: ["conversationId": String(conversationId), "userId": String(userId)],
            fileFieldName: "file",
            fileData: fileData,
            fileName: fileName,
            mimeType: mimeType
        ).dataOrThrow()
    }

    /// 文件本体走鉴权下载接口拿原始字节——objectKey 以 chat/ 开头，走公共媒体接口会被服务端拒绝。
    func downloadMedia(objectKey: String, userId: Int64) async throws -> Data {
        try await client.downloadRaw(
            "/api/im/media/download",
            query: ["objectKey": objectKey, "userId": String(userId)]
        )
    }

    // MARK: - 群成员管理 (M5)

    func inviteMember(conversationId: Int64, targetUserId: Int64) async throws -> [ConversationMemberView] {
        try await client.postForm(
            "/api/im/groups/members/invite",
            fields: ["conversationId": String(conversationId), "targetUserId": String(targetUserId)]
        ).dataOrThrow()
    }

    func removeMember(conversationId: Int64, targetUserId: Int64) async throws -> [ConversationMemberView] {
        try await client.postForm(
            "/api/im/groups/members/remove",
            fields: ["conversationId": String(conversationId), "targetUserId": String(targetUserId)]
        ).dataOrThrow()
    }

    // MARK: - 群管理 (群公告/角色/禁言/转让/加群方式/邀请链接)

    func groupAnnouncement(conversationId: Int64) async throws -> GroupAnnouncementView {
        try await client.getJSON(
            "/api/im/groups/announcement",
            query: ["conversationId": String(conversationId)]
        ).dataOrThrow()
    }

    func updateGroupAnnouncement(conversationId: Int64, operatorUserId: Int64, content: String) async throws -> GroupAnnouncementView {
        try await client.postForm(
            "/api/im/groups/announcement",
            fields: ["conversationId": String(conversationId), "operatorUserId": String(operatorUserId), "content": content]
        ).dataOrThrow()
    }

    func updateGroupAvatar(conversationId: Int64, operatorUserId: Int64, avatar: String) async throws -> String {
        try await client.postForm(
            "/api/im/groups/avatar",
            fields: ["conversationId": String(conversationId), "operatorUserId": String(operatorUserId), "avatar": avatar]
        ).dataOrThrow()
    }

    func updateGroupTitle(conversationId: Int64, operatorUserId: Int64, title: String) async throws -> String {
        try await client.postForm(
            "/api/im/groups/title",
            fields: ["conversationId": String(conversationId), "operatorUserId": String(operatorUserId), "title": title]
        ).dataOrThrow()
    }

    func updateMemberRole(conversationId: Int64, targetUserId: Int64, role: String) async throws -> [ConversationMemberView] {
        try await client.postForm(
            "/api/im/groups/members/role",
            fields: ["conversationId": String(conversationId), "targetUserId": String(targetUserId), "role": role]
        ).dataOrThrow()
    }

    func muteMember(conversationId: Int64, targetUserId: Int64, minutes: Int) async throws -> [ConversationMemberView] {
        try await client.postForm(
            "/api/im/groups/members/mute",
            fields: ["conversationId": String(conversationId), "targetUserId": String(targetUserId), "minutes": String(minutes)]
        ).dataOrThrow()
    }

    func transferGroupOwner(conversationId: Int64, targetUserId: Int64) async throws -> [ConversationMemberView] {
        try await client.postForm(
            "/api/im/groups/members/transfer-owner",
            fields: ["conversationId": String(conversationId), "targetUserId": String(targetUserId)]
        ).dataOrThrow()
    }

    func updateJoinPolicy(conversationId: Int64, joinPolicy: String) async throws -> Int {
        try await client.postForm(
            "/api/im/groups/join-policy",
            fields: ["conversationId": String(conversationId), "joinPolicy": joinPolicy]
        ).dataOrThrow()
    }

    func createGroupInviteToken(conversationId: Int64) async throws -> GroupInviteTokenView {
        try await client.postForm(
            "/api/im/groups/invite-token",
            fields: ["conversationId": String(conversationId)]
        ).dataOrThrow()
    }

    func previewGroupInvite(token: String) async throws -> GroupInvitePreviewView {
        try await client.getJSON(
            "/api/im/groups/invite-preview",
            query: ["token": token]
        ).dataOrThrow()
    }

    func joinGroupByToken(token: String, message: String?) async throws -> String {
        try await client.postForm(
            "/api/im/groups/join-by-token",
            fields: ["token": token, "message": message]
        ).dataOrThrow()
    }

    func listGroupJoinRequests(conversationId: Int64, limit: Int = 50) async throws -> [GroupJoinRequestView] {
        try await client.getJSON(
            "/api/im/groups/join-requests",
            query: ["conversationId": String(conversationId), "limit": String(limit)]
        ).dataOrThrow()
    }

    func approveGroupJoinRequest(conversationId: Int64, requestId: Int64) async throws {
        let response: ApiResponse<EmptyData> = try await client.postForm(
            "/api/im/groups/join-requests/approve",
            fields: ["conversationId": String(conversationId), "requestId": String(requestId)]
        )
        try response.throwIfFailed()
    }

    func rejectGroupJoinRequest(conversationId: Int64, requestId: Int64) async throws {
        let response: ApiResponse<EmptyData> = try await client.postForm(
            "/api/im/groups/join-requests/reject",
            fields: ["conversationId": String(conversationId), "requestId": String(requestId)]
        )
        try response.throwIfFailed()
    }

    // MARK: - 持币门槛 (M9)

    func updateTokenGate(
        conversationId: Int64, chain: String, tokenAddress: String?, minAmount: String, symbol: String, decimals: Int
    ) async throws -> Int {
        try await client.postForm(
            "/api/im/groups/token-gate",
            fields: [
                "conversationId": String(conversationId), "chain": chain, "tokenAddress": tokenAddress,
                "minAmount": minAmount, "symbol": symbol, "decimals": String(decimals),
            ]
        ).dataOrThrow()
    }

    func clearTokenGate(conversationId: Int64) async throws -> Int {
        try await client.postForm(
            "/api/im/groups/token-gate/clear",
            fields: ["conversationId": String(conversationId)]
        ).dataOrThrow()
    }

    // MARK: - 收藏 (M10)

    func addFavorite(messageId: Int64, userId: Int64) async throws -> Int {
        try await client.postForm(
            "/api/im/messages/favorite/add",
            fields: ["messageId": String(messageId), "userId": String(userId)]
        ).dataOrThrow()
    }

    func removeFavorite(messageId: Int64, userId: Int64) async throws -> Int {
        try await client.postForm(
            "/api/im/messages/favorite/remove",
            fields: ["messageId": String(messageId), "userId": String(userId)]
        ).dataOrThrow()
    }

    func favorites(userId: Int64, limit: Int = 50) async throws -> [FavoriteMessageView] {
        try await client.getJSON(
            "/api/im/messages/favorites",
            query: ["userId": String(userId), "limit": String(limit)]
        ).dataOrThrow()
    }

    func updateFavoriteNote(messageId: Int64, userId: Int64, note: String?) async throws -> Int {
        try await client.postForm(
            "/api/im/messages/favorite/note",
            fields: ["messageId": String(messageId), "userId": String(userId), "note": note]
        ).dataOrThrow()
    }
}
