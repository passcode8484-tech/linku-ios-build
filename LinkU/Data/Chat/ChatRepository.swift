import Foundation
import SwiftData

/// 对应 android-native data/chat/ChatRepository.kt。M3(单聊文字) + M4(消息操作/图片文件消息) +
/// M5(群聊 Sender Key)。
@MainActor
final class ChatRepository {
    private let api: ChatApi
    private let socket: ChatSocketClient
    private let modelContext: ModelContext
    private let sessionStore: SessionStore
    private let e2ee: E2eeSessionManager
    private let publicMediaApi: PublicMediaApi

    /// 消息销毁（TTL/阅后即焚）本地到期定时器，按 messageId 去重——跟 android expiryJobs 一个用途。
    private var expiryTasks: [Int64: Task<Void, Never>] = [:]

    init(
        api: ChatApi,
        socket: ChatSocketClient,
        modelContext: ModelContext,
        sessionStore: SessionStore,
        e2ee: E2eeSessionManager,
        publicMediaApi: PublicMediaApi
    ) {
        self.api = api
        self.socket = socket
        self.modelContext = modelContext
        self.sessionStore = sessionStore
        self.e2ee = e2ee
        self.publicMediaApi = publicMediaApi

        socket.onEvent { [weak self] frame in
            Task { @MainActor in await self?.handleSocketFrame(frame) }
        }
    }

    private var currentUserId: Int64? { sessionStore.user?.id }

    @discardableResult
    func refreshConversations() async throws -> [ConversationSummary] {
        guard let userId = currentUserId else { return [] }
        let summaries = try await api.listConversations(userId: userId)
        replaceAllConversations(summaries)
        return summaries
    }

    /// 单聊会话不存在就建一个——服务端对同一对 (ownerUserId, peerUserId) 幂等，重复调用不会建出
    /// 两个会话。
    func openOrCreateSingleConversation(peerUserId: Int64, title: String) async throws -> Int64 {
        guard let userId = currentUserId else {
            throw ApiException(code: -1, apiMessage: "未登录")
        }
        let result = try await api.createSingleConversation(ownerUserId: userId, peerUserId: peerUserId, title: title)
        return result.id
    }

    /// 新建的会话本地缓存里还没有，创建成功后立刻拉一次列表落库——不然要等下次自然刷新才会
    /// 出现在会话列表里。
    func createGroupConversation(title: String, memberUserIds: [Int64]) async throws -> Int64 {
        guard let userId = currentUserId else { throw ApiException(code: -1, apiMessage: "未登录") }
        let id = try await api.createGroupConversation(ownerUserId: userId, title: title, memberUserIds: memberUserIds).id
        try? await refreshConversations()
        return id
    }

    func conversationDetail(conversationId: Int64) async throws -> ConversationDetail {
        guard let userId = currentUserId else { throw ApiException(code: -1, apiMessage: "未登录") }
        return try await api.conversationDetail(conversationId: conversationId, userId: userId)
    }

    func inviteMember(conversationId: Int64, targetUserId: Int64) async throws -> [ConversationMemberView] {
        try await api.inviteMember(conversationId: conversationId, targetUserId: targetUserId)
    }

    func removeMember(conversationId: Int64, targetUserId: Int64) async throws -> [ConversationMemberView] {
        try await api.removeMember(conversationId: conversationId, targetUserId: targetUserId)
    }

    // MARK: - 已读回执/输入状态

    /// 阅读回执要不要发，跟 android 一样看当前用户自己的隐私设置——这里没有像 android 那样把
    /// allowReadReceipt 缓存在内存单例里，每次由调用方（ChatThreadView）在打开会话时查一次
    /// UserProfileRepository.fetchPrivacy() 自己决定要不要调这个方法，仓库这层只管发请求本身。
    /// 阅后即焚消息标已读这一下，服务端会顺手把接收方自己这份删掉——本地立刻跟着摘掉，不用等
    /// MESSAGE_PURGED 广播回声（发送方那边才需要等 MESSAGE_LIFECYCLE，见 handleSocketFrame）。
    func updateReceipt(conversationId: Int64, messageId: Int64, status: String) async throws {
        guard let userId = currentUserId else { return }
        _ = try await api.updateReceipt(conversationId: conversationId, messageId: messageId, userId: userId, status: status)
        if status == "READ" {
            let descriptor = FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.id == messageId })
            if let cached = try? modelContext.fetch(descriptor).first, cached.policyMode == "BURN_AFTER_READ" {
                removeMessageLocally(messageId: messageId)
            }
        }
    }

    // MARK: - 消息销毁（TTL/阅后即焚/手动删除给所有人）

    /// 手动"删除给所有人"——跟撤回不同，没有 2 分钟时间窗限制这一说（具体权限服务端把关），
    /// 调用方（ChatThreadView 消息操作菜单）自己决定要不要在 UI 上加一次二次确认。
    func purgeForEveryone(conversationId: Int64, messageId: Int64) async throws {
        guard let userId = currentUserId else { return }
        _ = try await api.purgeForEveryone(conversationId: conversationId, messageId: messageId, userId: userId)
        removeMessageLocally(messageId: messageId)
    }

    /// 只处理 TTL——阅后即焚要等对方已读之后服务端广播 MESSAGE_LIFECYCLE 才知道具体到期时间，
    /// 发送/收到那一刻算不出来；TTL 的到期时间发送那一刻服务端就已经定好了，直接用
    /// （sent/received 的 MessageView 都带 policyExpireAt，双方各自本地各调度一次）。
    private func schedulePolicyExpiry(_ view: MessageView) {
        guard view.policyMode == "TTL", let expireAtRaw = view.policyExpireAt else { return }
        scheduleExpiry(messageId: view.id, conversationId: view.conversationId, expireAtISO: expireAtRaw, reason: "TTL")
    }

    private func scheduleExpiry(messageId: Int64, conversationId: Int64, expireAtISO: String, reason: String) {
        guard expiryTasks[messageId] == nil, let expireAt = Self.parseServerLocalDateTime(expireAtISO) else { return }
        expiryTasks[messageId] = Task { [weak self] in
            let delay = expireAt.timeIntervalSinceNow
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled, let self else { return }
            let userId = self.currentUserId
            self.removeMessageLocally(messageId: messageId)
            if let userId {
                try? await self.api.notifyMessageExpired(conversationId: conversationId, messageId: messageId, userId: userId, reason: reason)
            }
        }
    }

    /// 撤回之外的"消息彻底没了"统一走这里——摘本地 SwiftData 缓存、取消可能还在跑的到期定时器，
    /// 不然重启 App 冷启动重新拉取消息列表时，已经删掉的消息会因为定时器还残留而"复活"。
    private func removeMessageLocally(messageId: Int64) {
        expiryTasks.removeValue(forKey: messageId)?.cancel()
        let descriptor = FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.id == messageId })
        guard let existing = try? modelContext.fetch(descriptor).first else { return }
        modelContext.delete(existing)
        try? modelContext.save()
    }

    /// 服务端 LocalDateTime 序列化的时间字符串不带时区偏移——部署配置固定 Asia/Shanghai
    /// （deploy/infra/docker-compose.yml TZ=Asia/Shanghai），必须显式按这个时区解析，不能假设
    /// 用户手机系统时区跟服务端一致。分钟/秒之外的小数位数服务端不同版本可能不一样，按精度从高到低
    /// 依次尝试。
    private static func parseServerLocalDateTime(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }

    func sendTyping(conversationId: Int64, typing: Bool) async {
        guard let userId = currentUserId else { return }
        try? await api.typing(conversationId: conversationId, userId: userId, typing: typing)
    }

    // MARK: - 群管理

    func groupAnnouncement(conversationId: Int64) async throws -> GroupAnnouncementView {
        try await api.groupAnnouncement(conversationId: conversationId)
    }

    func updateGroupAnnouncement(conversationId: Int64, content: String) async throws -> GroupAnnouncementView {
        guard let userId = currentUserId else { throw ApiException(code: -1, apiMessage: "未登录") }
        return try await api.updateGroupAnnouncement(conversationId: conversationId, operatorUserId: userId, content: content)
    }

    /// 群头像走公开媒体上传（跟朋友圈图片同一个接口，明文不加密——群头像本来就是公开可见内容），
    /// 拿到 objectKey 再传给 updateGroupAvatar 落库,两步都失败/成功是分开的，中间那步网络抖动
    /// 失败了不会把服务端已有头像清空,直接抛错让 UI 层重试就行。
    func updateGroupAvatar(conversationId: Int64, fileData: Data, fileName: String, mimeType: String) async throws -> String {
        guard let userId = currentUserId else { throw ApiException(code: -1, apiMessage: "未登录") }
        let uploaded = try await publicMediaApi.upload(
            userId: userId, kind: "group_avatar", fileData: fileData, fileName: fileName, mimeType: mimeType
        )
        return try await api.updateGroupAvatar(conversationId: conversationId, operatorUserId: userId, avatar: uploaded.objectKey)
    }

    func updateGroupTitle(conversationId: Int64, title: String) async throws -> String {
        guard let userId = currentUserId else { throw ApiException(code: -1, apiMessage: "未登录") }
        return try await api.updateGroupTitle(conversationId: conversationId, operatorUserId: userId, title: title)
    }

    func updateMemberRole(conversationId: Int64, targetUserId: Int64, role: String) async throws -> [ConversationMemberView] {
        try await api.updateMemberRole(conversationId: conversationId, targetUserId: targetUserId, role: role)
    }

    func muteMember(conversationId: Int64, targetUserId: Int64, minutes: Int) async throws -> [ConversationMemberView] {
        try await api.muteMember(conversationId: conversationId, targetUserId: targetUserId, minutes: minutes)
    }

    func transferGroupOwner(conversationId: Int64, targetUserId: Int64) async throws -> [ConversationMemberView] {
        try await api.transferGroupOwner(conversationId: conversationId, targetUserId: targetUserId)
    }

    func updateJoinPolicy(conversationId: Int64, joinPolicy: String) async throws {
        _ = try await api.updateJoinPolicy(conversationId: conversationId, joinPolicy: joinPolicy)
    }

    func createGroupInviteToken(conversationId: Int64) async throws -> GroupInviteTokenView {
        try await api.createGroupInviteToken(conversationId: conversationId)
    }

    func previewGroupInvite(token: String) async throws -> GroupInvitePreviewView {
        try await api.previewGroupInvite(token: token)
    }

    /// 通过邀请链接/二维码加群——服务端可能是直接入群（AUTO 加群方式），也可能是提交了一条待审批
    /// 申请（APPROVAL 加群方式），两种情况用同一个接口，区别只在返回文案，UI 层不用关心区分。
    func joinGroupByToken(token: String, message: String? = nil) async throws -> String {
        try await api.joinGroupByToken(token: token, message: message)
    }

    func groupJoinRequests(conversationId: Int64) async throws -> [GroupJoinRequestView] {
        try await api.listGroupJoinRequests(conversationId: conversationId)
    }

    func approveGroupJoinRequest(conversationId: Int64, requestId: Int64) async throws {
        try await api.approveGroupJoinRequest(conversationId: conversationId, requestId: requestId)
    }

    func rejectGroupJoinRequest(conversationId: Int64, requestId: Int64) async throws {
        try await api.rejectGroupJoinRequest(conversationId: conversationId, requestId: requestId)
    }

    func updateTokenGate(
        conversationId: Int64, chain: String, tokenAddress: String?, minAmount: String, symbol: String, decimals: Int
    ) async throws {
        _ = try await api.updateTokenGate(
            conversationId: conversationId, chain: chain, tokenAddress: tokenAddress,
            minAmount: minAmount, symbol: symbol, decimals: decimals
        )
    }

    func clearTokenGate(conversationId: Int64) async throws {
        _ = try await api.clearTokenGate(conversationId: conversationId)
    }

    // MARK: - 收藏 (M10)

    func addFavorite(messageId: Int64) async throws {
        guard let userId = currentUserId else { throw ApiException(code: -1, apiMessage: "未登录") }
        _ = try await api.addFavorite(messageId: messageId, userId: userId)
    }

    func removeFavorite(messageId: Int64) async throws {
        guard let userId = currentUserId else { throw ApiException(code: -1, apiMessage: "未登录") }
        _ = try await api.removeFavorite(messageId: messageId, userId: userId)
    }

    func updateFavoriteNote(messageId: Int64, note: String?) async throws {
        guard let userId = currentUserId else { throw ApiException(code: -1, apiMessage: "未登录") }
        _ = try await api.updateFavoriteNote(messageId: messageId, userId: userId, note: note)
    }

    /// 收藏列表——服务端 `content` 字段是 E2EE 密文信封，Double Ratchet 消息解一次链位就往前走一格，
    /// 收藏页每次打开都重新调用一次真正的会话解密会导致后续正常消息解不开。跟本地聊天记录缓存
    /// 共享同一份已经解好的 plaintext（本地没有才退回一次性尝试解密，走 e2ee.decryptContent 自带的
    /// 失败兜底文案，不在这里另外拼一份）。
    func favorites(limit: Int = 50) async throws -> [FavoriteMessageView] {
        guard let userId = currentUserId else { throw ApiException(code: -1, apiMessage: "未登录") }
        let raw = try await api.favorites(userId: userId, limit: limit)
        var resolved: [FavoriteMessageView] = []
        for item in raw {
            resolved.append(await resolveFavoriteDisplay(item, currentUserId: userId))
        }
        return resolved
    }

    private func resolveFavoriteDisplay(_ favorite: FavoriteMessageView, currentUserId userId: Int64) async -> FavoriteMessageView {
        var favorite = favorite
        let targetId = favorite.messageId
        let descriptor = FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.id == targetId })
        if let cached = try? modelContext.fetch(descriptor).first, let plaintext = cached.plaintext {
            favorite.content = plaintext
            return favorite
        }
        guard let raw = favorite.content, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return favorite
        }
        if favorite.senderUserId == userId, let own = e2ee.readOwnPlaintext(messageId: favorite.messageId) {
            favorite.content = own
            return favorite
        }
        favorite.content = await e2ee.decryptContent(
            senderUserId: favorite.senderUserId, content: raw, conversationId: favorite.conversationId
        )
        return favorite
    }

    /// 群成员名单变化后调用（拉人/踢人/每次打开群聊顺手核对一遍）——本机记录的成员指纹没变就是
    /// 纯本地开销的空操作；变了才轮换本机 Sender Key 并把新的分发消息发到群里，让其他成员的客户端
    /// 能重新建立会话跟上最新成员名单。
    func syncGroupMembership(conversationId: Int64, memberUserIds: [Int64]) async {
        guard let userId = currentUserId else { return }
        guard let distribution = try? await e2ee.handleGroupMembershipChange(conversationId: conversationId, memberUserIds: memberUserIds) else {
            return
        }
        _ = try? await deliver(
            conversationId: conversationId, senderUserId: userId, type: "TEXT",
            encryptedContent: distribution, replyMessageId: nil
        )
    }

    /// 单聊要知道对方 userId 才能建 Signal 会话，群聊只要 conversationId。本地缓存优先，
    /// 缓存里没有（比如冷启动第一次发消息）就现查一次服务端。
    private func resolveConversationTypeAndPeer(conversationId: Int64) async throws -> (type: String, peerUserId: Int64?) {
        let descriptor = FetchDescriptor<ConversationEntity>(predicate: #Predicate { $0.id == conversationId })
        if let cached = try? modelContext.fetch(descriptor).first {
            return (cached.type, cached.peerUserId)
        }
        let detail = try await conversationDetail(conversationId: conversationId)
        let peer = detail.type == "SINGLE" ? detail.members.first(where: { $0.userId != currentUserId })?.userId : nil
        return (detail.type, peer)
    }

    /// 发消息前加密——群聊如果本机 Sender Key 还没广播过，先把分发信封当一条普通消息发出去
    /// （对端会自动识别并吞掉，不会展示成聊天气泡），再发真正加密后的内容。
    private func encryptOutgoingContent(conversationId: Int64, senderUserId: Int64, content: String, type: String) async throws -> String {
        let (conversationType, peerUserId) = try await resolveConversationTypeAndPeer(conversationId: conversationId)
        if conversationType == "GROUP" {
            if let distribution = try? await e2ee.ensureGroupSenderKeyDistribution(conversationId: conversationId) {
                _ = try? await deliver(
                    conversationId: conversationId, senderUserId: senderUserId, type: "TEXT",
                    encryptedContent: distribution, replyMessageId: nil
                )
            }
            return try await e2ee.encryptOutgoingGroup(conversationId: conversationId, content: content, kind: type)
        }
        guard let peer = peerUserId else {
            throw ApiException(code: -1, apiMessage: "单聊会话缺少对方 userId，无法建立加密会话")
        }
        return try await e2ee.encryptOutgoingSingle(peerUserId: peer, content: content, kind: type)
    }

    func loadMessages(conversationId: Int64, beforeId: Int64? = nil) async throws {
        guard let userId = currentUserId else { return }
        let views = try await api.listMessages(conversationId: conversationId, userId: userId, beforeId: beforeId)
        for view in views {
            await upsertIncomingMessage(view)
        }
    }

    func sendText(
        conversationId: Int64,
        text: String,
        replyMessageId: Int64? = nil,
        policyMode: String? = nil,
        policyTtlSec: Int? = nil,
        policyBurnDelaySec: Int? = nil,
        mentionedUserIds: [Int64]? = nil
    ) async throws {
        guard let userId = currentUserId else { return }
        let encrypted = try await encryptOutgoingContent(conversationId: conversationId, senderUserId: userId, content: text, type: "TEXT")
        let mentionedIdsField = (mentionedUserIds?.isEmpty == false) ? mentionedUserIds!.map(String.init).joined(separator: ",") : nil
        let sent = try await deliver(
            conversationId: conversationId, senderUserId: userId, type: "TEXT",
            encryptedContent: encrypted, replyMessageId: replyMessageId,
            policyMode: policyMode, policyTtlSec: policyTtlSec, policyBurnDelaySec: policyBurnDelaySec,
            mentionedUserIds: mentionedIdsField
        )
        // Double Ratchet 加密不可逆，自己发的消息在加密前先把明文缓存下来，翻聊天记录直接读缓存。
        e2ee.rememberOwnPlaintext(messageId: sent.id, plaintext: text)
        upsertLocalMessage(sent, plaintext: text)
        schedulePolicyExpiry(sent)
    }

    /// 图片/文件消息：文件本体走独立一次性 AES-GCM 密钥加密上传，密钥/IV 随 PlainMediaPayload
    /// 一起被 Signal 加密进消息 content——服务端只存得到加密字节，物理上读不到明文。
    func sendMedia(
        conversationId: Int64,
        kind: String,
        fileData: Data,
        fileName: String,
        mimeType: String,
        durationMs: Int64? = nil,
        replyMessageId: Int64? = nil
    ) async throws {
        guard let userId = currentUserId else { return }
        let fileKey = E2eeFileCrypto.generateKey()
        let fileIv = E2eeFileCrypto.generateIv()
        let encryptedData = try E2eeFileCrypto.encryptData(fileData, key: fileKey, iv: fileIv)
        let uploaded = try await api.uploadMedia(
            conversationId: conversationId, userId: userId,
            fileData: encryptedData, fileName: fileName, mimeType: "application/octet-stream"
        )
        let plainContent = PlainMediaPayload.encode(
            kind: kind, objectKey: uploaded.objectKey, mime: mimeType, size: uploaded.size,
            durationMs: durationMs, fileName: fileName,
            fileKey: E2eeFileCrypto.encodeKey(fileKey), fileIv: E2eeFileCrypto.encodeKey(fileIv)
        )
        let encrypted = try await encryptOutgoingContent(conversationId: conversationId, senderUserId: userId, content: plainContent, type: kind)
        let sent = try await deliver(
            conversationId: conversationId, senderUserId: userId, type: kind,
            encryptedContent: encrypted, replyMessageId: replyMessageId
        )
        e2ee.rememberOwnPlaintext(messageId: sent.id, plaintext: plainContent)
        upsertLocalMessage(sent, plaintext: plainContent)
    }

    /// 下载 + 解密媒体文件到本地缓存，命中缓存直接返回——objectKey 哈希做文件名，跟安卓端
    /// 的本地缓存策略一个思路。老消息/明文时代发的没有 fileKey/fileIv，直接当明文字节用。
    /// 只查本地缓存命中与否，不发网络请求——"仅 Wi-Fi 自动下载"这类限流开关只应该拦网络下载，
    /// 已经缓存过的图片不管当前网络类型都应该能直接看，拦了反而是体验倒退（跟 android 那边
    /// wifi-only 判断写在缓存命中检查之前、连本地已有的图都一并拦住比,这里特意分开两步）。
    nonisolated static func cachedMediaURL(objectKey: String, suggestedExtension: String) -> URL? {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let fileName = "media_\(abs(objectKey.hashValue)).\(suggestedExtension)"
        let targetURL = cacheDir.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: targetURL.path) ? targetURL : nil
    }

    func downloadAndDecryptMedia(objectKey: String, fileKey: String?, fileIv: String?, suggestedExtension: String) async throws -> URL {
        guard let userId = currentUserId else { throw ApiException(code: -1, apiMessage: "未登录") }
        if let cached = Self.cachedMediaURL(objectKey: objectKey, suggestedExtension: suggestedExtension) {
            return cached
        }
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let fileName = "media_\(abs(objectKey.hashValue)).\(suggestedExtension)"
        let targetURL = cacheDir.appendingPathComponent(fileName)
        let downloaded = try await api.downloadMedia(objectKey: objectKey, userId: userId)
        let plaintext: Data
        if let fileKey, let fileIv, !fileKey.isEmpty, !fileIv.isEmpty {
            plaintext = try E2eeFileCrypto.decryptData(
                downloaded, key: E2eeFileCrypto.decodeKey(fileKey), iv: E2eeFileCrypto.decodeKey(fileIv)
            )
        } else {
            plaintext = downloaded
        }
        try plaintext.write(to: targetURL)
        return targetURL
    }

    /// 优先走已经建立好的 WS 连接发消息——比每条消息都走一次 HTTP 握手快；连接不可用或者
    /// 发送抛错就自动退回 HTTP，两条路径服务端最终都是同一个实现。
    private func deliver(
        conversationId: Int64,
        senderUserId: Int64,
        type: String,
        encryptedContent: String,
        replyMessageId: Int64?,
        policyMode: String? = nil,
        policyTtlSec: Int? = nil,
        policyBurnDelaySec: Int? = nil,
        mentionedUserIds: String? = nil
    ) async throws -> MessageView {
        // 消息销毁策略/@提及这几个字段目前只走 HTTP 路径——WS SEND_MESSAGE 是 M3 时期只为普通
        // 文字消息设计的，服务端那条 action 数据结构没有对应字段；不为了这两个次要功能去动更
        // 基础的 WS 协议，带这些字段的消息固定走 HTTP，跟普通消息比无非是多一次握手延迟。
        if policyMode == nil, mentionedUserIds == nil, socket.isConnected,
           let sent = try? await socket.sendChatMessage(
               conversationId: conversationId, senderUserId: senderUserId, type: type,
               content: encryptedContent, replyMessageId: replyMessageId
           ) {
            return sent
        }
        return try await api.sendMessage(
            conversationId: conversationId, senderUserId: senderUserId, type: type,
            content: encryptedContent, replyMessageId: replyMessageId,
            policyMode: policyMode, policyTtlSec: policyTtlSec, policyBurnDelaySec: policyBurnDelaySec,
            mentionedUserIds: mentionedUserIds
        )
    }

    func markRead(conversationId: Int64) async {
        guard let userId = currentUserId else { return }
        try? await api.markRead(conversationId: conversationId, userId: userId)
        clearUnreadLocally(conversationId: conversationId)
    }

    // MARK: - 消息操作 (M4)

    /// 返回受影响行数——服务端超过 2 分钟撤回窗口或非本人消息时会静默返回 0，调用方要自己判断。
    @discardableResult
    func recallMessage(messageId: Int64) async throws -> Int {
        guard let userId = currentUserId else { return 0 }
        let affected = try await api.recallMessage(messageId: messageId, userId: userId)
        if affected > 0 { markRecalledLocally(messageId: messageId) }
        return affected
    }

    func editMessage(conversationId: Int64, messageId: Int64, content: String) async throws {
        guard let userId = currentUserId else { return }
        let encrypted = try await encryptOutgoingContent(conversationId: conversationId, senderUserId: userId, content: content, type: "TEXT")
        let edited = try await api.editMessage(conversationId: conversationId, messageId: messageId, userId: userId, content: encrypted)
        e2ee.rememberOwnPlaintext(messageId: messageId, plaintext: content)
        upsertLocalMessage(edited, plaintext: content)
    }

    /// **不走服务端 /messages/forward**——那个接口是把密文原样复制进另一个会话，
    /// 而密文是绑定在原会话那条 Double Ratchet 链上的，换个会话大概率解不开（windows-native
    /// 那边已经确认过这是服务端的真实 bug，见项目记录）。改成本地先解出明文，
    /// 再当成一条全新消息加密发到目标会话，跟安卓/windows-native 后来的修复方式一致。
    func forwardMessage(sourceMessageId: Int64, targetConversationId: Int64) async throws {
        let descriptor = FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.id == sourceMessageId })
        guard let source = try? modelContext.fetch(descriptor).first, let plaintext = source.plaintext else {
            throw ApiException(code: -1, apiMessage: "原消息不可读，无法转发")
        }
        if PlainMediaPayload.tryParse(plaintext) != nil {
            // 媒体消息的 plaintext 就是 PlainMediaPayload JSON（objectKey 指向同一份服务端密文文件，
            // fileKey/fileIv 已经包含在里面）——原样当内容重新走 Signal 加密发一遍即可，不用重新上传文件。
            let userId = try requireUserId()
            let encrypted = try await encryptOutgoingContent(
                conversationId: targetConversationId, senderUserId: userId, content: plaintext, type: source.type
            )
            _ = try await deliver(
                conversationId: targetConversationId, senderUserId: userId, type: source.type,
                encryptedContent: encrypted, replyMessageId: nil
            )
        } else {
            try await sendText(conversationId: targetConversationId, text: plaintext)
        }
    }

    func addReaction(conversationId: Int64, messageId: Int64, reaction: String) async throws -> [MessageReactionView] {
        guard let userId = currentUserId else { return [] }
        return try await api.addReaction(conversationId: conversationId, messageId: messageId, userId: userId, reaction: reaction)
    }

    func removeReaction(conversationId: Int64, messageId: Int64, reaction: String) async throws -> [MessageReactionView] {
        guard let userId = currentUserId else { return [] }
        return try await api.removeReaction(conversationId: conversationId, messageId: messageId, userId: userId, reaction: reaction)
    }

    func pinMessage(conversationId: Int64, messageId: Int64) async throws -> [PinnedMessageView] {
        guard let userId = currentUserId else { return [] }
        return try await api.pinMessage(conversationId: conversationId, messageId: messageId, operatorUserId: userId)
    }

    func unpinMessage(conversationId: Int64, messageId: Int64) async throws -> [PinnedMessageView] {
        try await api.unpinMessage(conversationId: conversationId, messageId: messageId)
    }

    func pinnedMessages(conversationId: Int64) async throws -> [PinnedMessageView] {
        try await api.pinnedMessages(conversationId: conversationId)
    }

    private func requireUserId() throws -> Int64 {
        guard let userId = currentUserId else { throw ApiException(code: -1, apiMessage: "未登录") }
        return userId
    }

    private func markRecalledLocally(messageId: Int64) {
        let descriptor = FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.id == messageId })
        guard let existing = try? modelContext.fetch(descriptor).first else { return }
        existing.recalled = true
        try? modelContext.save()
    }

    // MARK: - WS 推送

    private func handleSocketFrame(_ frame: ChatSocketFrame) async {
        // 服务端广播新消息用的事件名是 MESSAGE_CREATED（不是猜的，读 android-native
        // ChatThreadViewModel.kt 的 observeRealtime() 核对过）。已读回执/输入状态/在线状态在
        // ChatThreadView 里单独订阅（只有打开着的那个会话页面关心），这里只处理新消息本体
        // 和消息销毁（阅后即焚/限时消息/手动删除给所有人，三条路径服务端共用 MESSAGE_PURGED 广播）。
        guard let data = frame.data else { return }
        switch frame.event {
        case "MESSAGE_CREATED":
            guard let jsonData = try? JSONSerialization.data(withJSONObject: data),
                  let view = try? JSONDecoder().decode(MessageView.self, from: jsonData)
            else { return }
            await upsertIncomingMessage(view)
        case "MESSAGE_LIFECYCLE":
            guard let jsonData = try? JSONSerialization.data(withJSONObject: data),
                  let event = try? JSONDecoder().decode(MessageLifecycleView.self, from: jsonData),
                  event.action == "BURN_SCHEDULED", let expireAt = event.expireAt
            else { return }
            scheduleExpiry(messageId: event.messageId, conversationId: event.conversationId, expireAtISO: expireAt, reason: "BURN_AFTER_READ")
        case "MESSAGE_PURGED":
            guard let jsonData = try? JSONSerialization.data(withJSONObject: data),
                  let event = try? JSONDecoder().decode(MessagePurgedView.self, from: jsonData)
            else { return }
            removeMessageLocally(messageId: event.messageId)
        default:
            break
        }
    }

    // MARK: - 本地缓存

    private func upsertIncomingMessage(_ view: MessageView) async {
        guard let userId = currentUserId else { return }
        let plaintext: String?
        if view.senderUserId == userId, let cached = e2ee.readOwnPlaintext(messageId: view.id) {
            plaintext = cached
        } else {
            plaintext = await e2ee.decryptToContentString(
                senderUserId: view.senderUserId, content: view.content, conversationId: view.conversationId
            )
        }
        upsertLocalMessage(view, plaintext: plaintext)
        schedulePolicyExpiry(view)
    }

    private func upsertLocalMessage(_ view: MessageView, plaintext: String?) {
        let targetId = view.id
        let descriptor = FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.id == targetId })
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.update(from: view, plaintext: plaintext)
        } else {
            modelContext.insert(MessageEntity(from: view, plaintext: plaintext))
        }
        try? modelContext.save()
        updateConversationPreview(conversationId: view.conversationId, preview: plaintext, type: view.type)
    }

    /// 会话列表"最新消息"预览——媒体消息的 plaintext 是 PlainMediaPayload JSON，不是给人看的文字，
    /// 这里要转成"[图片]"这类友好文案，不能直接把 JSON 字符串糊到列表上。
    private func updateConversationPreview(conversationId: Int64, preview: String?, type: String) {
        let descriptor = FetchDescriptor<ConversationEntity>(predicate: #Predicate { $0.id == conversationId })
        guard let conversation = try? modelContext.fetch(descriptor).first else { return }
        let displayPreview = preview.flatMap(PlainMediaPayload.listPreview) ?? preview
        conversation.lastMessage = displayPreview
        conversation.lastMessageType = type
        try? modelContext.save()
    }

    private func clearUnreadLocally(conversationId: Int64) {
        let descriptor = FetchDescriptor<ConversationEntity>(predicate: #Predicate { $0.id == conversationId })
        guard let conversation = try? modelContext.fetch(descriptor).first else { return }
        conversation.unreadCount = 0
        try? modelContext.save()
    }

    private func replaceAllConversations(_ summaries: [ConversationSummary]) {
        for view in summaries {
            let targetId = view.id
            let descriptor = FetchDescriptor<ConversationEntity>(predicate: #Predicate { $0.id == targetId })
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.update(from: view)
            } else {
                modelContext.insert(ConversationEntity(from: view))
            }
        }
        try? modelContext.save()
    }
}
