import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// 对应 android-native ui/chat/ChatThreadScreen.kt。M3(文字收发) + M4(回复/撤回/编辑/转发/
/// 表情回应/置顶 + 图片/文件消息) + M5(群聊，靠 isGroup 控制发送者昵称展示，加解密路由在
/// ChatRepository 内部按会话类型分支，这个视图不用关心) + 已读回执/输入状态/在线状态
/// （单聊专属订阅，见 subscribeRealtimeExtras；MESSAGE_RECEIPT/TYPING/PRESENCE 三个 WS 事件）+
/// 消息销毁（TTL/阅后即焚/删除给所有人）+ @提及 + 语音消息录制/播放。视频消息录制不在范围内——
/// android 那边也没有这个功能，不是漏搬（见 project_ios_native 记忆里的说明）。
struct ChatThreadView: View {
    let container: AppContainer
    let conversationId: Int64
    let isGroup: Bool
    let title: String

    @Query private var messages: [MessageEntity]
    @Query(sort: \ConversationEntity.updatedAt, order: .reverse) private var allConversations: [ConversationEntity]

    @State private var inputText = ""
    @State private var errorMessage: String?
    @State private var sending = false
    @State private var replyTarget: MessageEntity?
    @State private var editingMessage: MessageEntity?
    @State private var forwardSource: MessageEntity?
    @State private var photosPickerItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var pinnedMessageIds: Set<Int64> = []
    @State private var showGroupInfo = false
    @State private var typingUserIds: Set<Int64> = []
    @State private var typingClearTasks: [Int64: Task<Void, Never>] = [:]
    @State private var peerOnline = false
    @State private var lastReadMessageId: Int64 = 0
    @State private var allowReadReceipt = true
    @State private var typingSendTask: Task<Void, Never>?
    @State private var wasComposerBlank = true
    @State private var reportedReadUpTo: Int64 = 0
    @State private var realtimeSubscriptionToken: UUID?
    @State private var purgeTarget: MessageEntity?
    @State private var showSendOptions = false
    @State private var groupMembers: [ConversationMemberView] = []
    @State private var pendingMentions: Set<Int64> = []
    @State private var voiceRecorder = VoiceRecorder()
    @State private var isRecording = false
    @State private var isStartingRecording = false
    @State private var willCancelRecording = false

    init(container: AppContainer, conversationId: Int64, isGroup: Bool = false, title: String) {
        self.container = container
        self.conversationId = conversationId
        self.isGroup = isGroup
        self.title = title
        _messages = Query(
            filter: #Predicate<MessageEntity> { $0.conversationId == conversationId },
            sort: \MessageEntity.id
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(messages) { message in
                            messageRow(message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in scrollToBottom(proxy) }
                .onAppear { scrollToBottom(proxy) }
            }

            if let replyTarget {
                HStack {
                    Rectangle().fill(LinkuBrand.primary).frame(width: 3)
                    Text(replyPreviewText(replyTarget)).font(.footnote).lineLimit(1)
                    Spacer()
                    Button {
                        self.replyTarget = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }

            if editingMessage != nil {
                HStack {
                    Text("正在编辑消息").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("取消") { cancelEdit() }.font(.caption)
                }
                .padding(.horizontal)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(LinkuBrand.danger)
                    .padding(.horizontal)
            }

            if isRecording {
                HStack {
                    Image(systemName: willCancelRecording ? "trash.fill" : "mic.fill")
                    Text(willCancelRecording ? "松开手指取消发送" : "上滑取消发送")
                }
                .font(.footnote)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(willCancelRecording ? LinkuBrand.danger : Color.black.opacity(0.75))
            }

            if !typingUserIds.isEmpty {
                Text(typingBannerText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !mentionCandidates.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(mentionCandidates) { member in
                            Button {
                                insertMention(member)
                            } label: {
                                Text(member.nickname ?? "用户\(member.userId)")
                                    .font(.footnote)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(.thinMaterial, in: Capsule())
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 4)
            }

            composer
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(title).font(.headline)
                    if !isGroup, peerOnline {
                        Text("在线").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            if isGroup {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showGroupInfo = true } label: { Image(systemName: "person.3") }
                }
            } else {
                // 通话目前只支持单聊 1:1（服务端 CallSessionView 是 callerId/calleeId 两方模型，
                // 群聊多方通话没有做），群聊不显示这两个按钮。
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { container.callCoordinator.startOutgoingCall(conversationId: conversationId, mediaType: "VIDEO") } label: {
                        Image(systemName: "video")
                    }
                    Button { container.callCoordinator.startOutgoingCall(conversationId: conversationId, mediaType: "AUDIO") } label: {
                        Image(systemName: "phone")
                    }
                }
            }
        }
        .task {
            await container.chatRepository.markRead(conversationId: conversationId)
            try? await container.chatRepository.loadMessages(conversationId: conversationId)
            await loadPinned()
            if isGroup {
                await syncGroupMembership()
                groupMembers = (try? await container.chatRepository.conversationDetail(conversationId: conversationId).members) ?? []
            }
            allowReadReceipt = (try? await container.userProfileRepository.fetchPrivacy().allowReadReceipt) ?? true
            peerOnline = allConversations.first(where: { $0.id == conversationId })?.online ?? false
            subscribeRealtimeExtras()
            reportReadReceiptIfNeeded()
        }
        .onChange(of: messages.count) { _, _ in reportReadReceiptIfNeeded() }
        .onDisappear {
            typingClearTasks.values.forEach { $0.cancel() }
            typingSendTask?.cancel()
            if let realtimeSubscriptionToken {
                container.chatSocketClient.removeEventHandler(realtimeSubscriptionToken)
            }
            if !wasComposerBlank {
                Task { await container.chatRepository.sendTyping(conversationId: conversationId, typing: false) }
            }
        }
        .sheet(isPresented: $showGroupInfo) {
            NavigationStack { GroupInfoView(container: container, conversationId: conversationId) }
        }
        .sheet(item: $forwardSource) { message in
            NavigationStack {
                List(allConversations.filter { $0.id != conversationId }) { conversation in
                    Button {
                        Task { await forward(message, to: conversation) }
                    } label: {
                        Text(conversation.title)
                    }
                }
                .navigationTitle("转发给")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("取消") { forwardSource = nil }
                    }
                }
            }
        }
        .onChange(of: photosPickerItem) { _, newValue in
            guard let newValue else { return }
            Task { await sendPickedImage(newValue) }
        }
        .onChange(of: inputText) { _, newValue in
            handleComposerChange(newValue)
        }
        .confirmationDialog(
            "删除给所有人后，对话双方都将看不到这条消息，且无法恢复",
            isPresented: Binding(get: { purgeTarget != nil }, set: { if !$0 { purgeTarget = nil } }),
            titleVisibility: .visible
        ) {
            if let target = purgeTarget {
                Button("删除给所有人", role: .destructive) { Task { await purge(target) } }
                Button("取消", role: .cancel) { purgeTarget = nil }
            }
        }
        .confirmationDialog("发送方式", isPresented: $showSendOptions, titleVisibility: .visible) {
            Button("正常发送") { Task { await send() } }
            Button("阅后即焚") { Task { await send(policyMode: "BURN_AFTER_READ") } }
            Button("限时 30 秒") { Task { await send(policyMode: "TTL", policyTtlSec: 30) } }
            Button("限时 1 分钟") { Task { await send(policyMode: "TTL", policyTtlSec: 60) } }
            Button("限时 1 小时") { Task { await send(policyMode: "TTL", policyTtlSec: 3600) } }
            Button("取消", role: .cancel) {}
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result {
                Task { await sendPickedFile(url) }
            }
        }
    }

    // MARK: - 消息行

    @ViewBuilder
    private func messageRow(_ message: MessageEntity) -> some View {
        let isMine = message.senderUserId == container.sessionStore.user?.id
        HStack {
            if isMine { Spacer(minLength: 40) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
                if pinnedMessageIds.contains(message.id) {
                    Label("已置顶", systemImage: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let policyLabel = disappearingLabel(for: message) {
                    Label(policyLabel, systemImage: message.policyMode == "BURN_AFTER_READ" ? "flame" : "timer")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                // 群聊气泡上方带发送者昵称，跟 Telegram/微信群聊惯例一致，单聊不需要。
                if isGroup, !isMine {
                    Text(message.senderNickname ?? "用户\(message.senderUserId)")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
                bubbleContent(message, isMine: isMine)
                // 已读回执只在 1:1 有明确语义（群聊"谁读了"要展示一份成员列表，服务端这块的
                // 数据模型也没有为群聊场景设计，这里跟 android 的 peerOnline 判断一样只用于单聊）。
                if isMine, !isGroup, message.id <= lastReadMessageId, !message.recalled {
                    Text("已读")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if !isMine { Spacer(minLength: 40) }
        }
        .contextMenu { contextMenuItems(for: message, isMine: isMine) }
    }

    private var typingBannerText: String {
        isGroup ? "有人正在输入…" : "对方正在输入…"
    }

    /// 光标固定在末尾（这个精简版没有做"任意光标位置插入" 的复杂交互，跟 M4 CreateGroupView
    /// 的取舍一个思路）——最后一个 "@" 之后如果没有空格/换行，就当用户正在打 @ 提及。
    private var mentionQuery: String? {
        guard isGroup, let atIndex = inputText.lastIndex(of: "@") else { return nil }
        let trailing = inputText[inputText.index(after: atIndex)...]
        guard !trailing.contains(" "), !trailing.contains("\n") else { return nil }
        return String(trailing)
    }

    private var mentionCandidates: [ConversationMemberView] {
        guard let query = mentionQuery else { return [] }
        let myId = container.sessionStore.user?.id
        return groupMembers.filter { member in
            member.userId != myId && (query.isEmpty || (member.nickname ?? "").localizedCaseInsensitiveContains(query))
        }
    }

    @ViewBuilder
    private func bubbleContent(_ message: MessageEntity, isMine: Bool) -> some View {
        if message.recalled {
            bubbleWrapper(isMine: isMine) {
                Text("[消息已撤回]").italic()
            }
        } else if message.type == "IMAGE", let payload = message.plaintext.flatMap(PlainMediaPayload.tryParse) {
            ImageBubbleContent(container: container, payload: payload)
        } else if message.type == "FILE", let payload = message.plaintext.flatMap(PlainMediaPayload.tryParse) {
            bubbleWrapper(isMine: isMine) {
                FileBubbleContent(container: container, payload: payload)
            }
        } else if message.type == "VOICE", let payload = message.plaintext.flatMap(PlainMediaPayload.tryParse) {
            bubbleWrapper(isMine: isMine) {
                VoiceBubbleContent(container: container, payload: payload, isMine: isMine)
            }
        } else {
            bubbleWrapper(isMine: isMine) {
                Text(message.plaintext ?? "[无法解密]")
            }
        }
    }

    @ViewBuilder
    private func bubbleWrapper<Content: View>(isMine: Bool, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isMine ? AnyShapeStyle(LinkuBrand.primary) : AnyShapeStyle(.thinMaterial))
            .foregroundStyle(isMine ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func contextMenuItems(for message: MessageEntity, isMine: Bool) -> some View {
        Button {
            replyTarget = message
            editingMessage = nil
        } label: {
            Label("回复", systemImage: "arrowshape.turn.up.left")
        }

        Button {
            forwardSource = message
        } label: {
            Label("转发", systemImage: "arrowshape.turn.up.right")
        }

        Button {
            Task { await react(message, reaction: "👍") }
        } label: {
            Label("赞一下", systemImage: "hand.thumbsup")
        }

        if isMine, message.type == "TEXT", !message.recalled {
            Button {
                startEdit(message)
            } label: {
                Label("编辑", systemImage: "pencil")
            }
        }

        if !message.recalled {
            Button {
                Task { await favorite(message) }
            } label: {
                Label("收藏", systemImage: "star")
            }
        }

        Button {
            Task { await togglePin(message) }
        } label: {
            if pinnedMessageIds.contains(message.id) {
                Label("取消置顶", systemImage: "pin.slash")
            } else {
                Label("置顶", systemImage: "pin")
            }
        }

        if isMine, !message.recalled {
            Button(role: .destructive) {
                Task { await recall(message) }
            } label: {
                Label("撤回", systemImage: "arrow.uturn.backward")
            }
            Button(role: .destructive) {
                purgeTarget = message
            } label: {
                Label("删除给所有人", systemImage: "trash")
            }
        }
    }

    // MARK: - composer

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Menu {
                PhotosPicker(selection: $photosPickerItem, matching: .images) {
                    Label("照片", systemImage: "photo")
                }
                Button {
                    showFileImporter = true
                } label: {
                    Label("文件", systemImage: "doc")
                }
            } label: {
                Image(systemName: "plus.circle").font(.title2)
            }

            // 按住录音、上滑取消——跟 android 那套 pointerInput 手势判定同一个思路：DragGesture
            // 从按下就触发（minimumDistance: 0），translation.height 是从按下点算起的累计位移，
            // 不需要自己再手动记录起始 Y 坐标。这里挂在 Image 而不是 Button 上，不会跟点按手势打架。
            Image(systemName: "mic.fill")
                .font(.title2)
                .foregroundStyle(isRecording ? LinkuBrand.danger : .primary)
                .frame(width: 28, height: 28)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isRecording, !isStartingRecording {
                                Task { await beginRecording() }
                            }
                            willCancelRecording = value.translation.height < -80
                        }
                        .onEnded { _ in
                            Task { await finishRecording() }
                        }
                )

            TextField(editingMessage != nil ? "编辑消息…" : "发消息…", text: $inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)

            Button {
                Task { await send() }
            } label: {
                Image(systemName: "paperplane.fill")
            }
            // 长按发送按钮弹"发送方式"（正常/阅后即焚/限时），跟 android 长按发送键的交互一致；
            // 编辑消息时不允许——编辑走的是另一条 editMessage 接口，没有销毁策略这个概念。用
            // simultaneousGesture 而不是 onLongPressGesture——后者会跟 Button 自带的点按手势打架，
            // 长按有时会连点按的 action 一起吞掉。
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                    guard editingMessage == nil, !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    showSendOptions = true
                }
            )
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
        }
        .padding()
    }

    // MARK: - 动作

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let last = messages.last {
            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }

    /// 只做一个静态角标，不做实时倒计时——倒计时要求每秒重绘所有可见气泡，对这次范围来说
    /// 投入产出不成比例，用户知道"这条消息会消失"就够了，具体还剩多久不是关键信息。
    private func disappearingLabel(for message: MessageEntity) -> String? {
        guard !message.recalled else { return nil }
        switch message.policyMode {
        case "BURN_AFTER_READ": return "阅后即焚"
        case "TTL": return "限时消息"
        default: return nil
        }
    }

    private func replyPreviewText(_ message: MessageEntity) -> String {
        if message.recalled { return "[消息已撤回]" }
        if let preview = message.plaintext.flatMap(PlainMediaPayload.listPreview) { return preview }
        return message.plaintext ?? "[无法解密]"
    }

    private func send(policyMode: String? = nil, policyTtlSec: Int? = nil) async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        errorMessage = nil
        typingSendTask?.cancel()
        wasComposerBlank = true
        Task { await container.chatRepository.sendTyping(conversationId: conversationId, typing: false) }
        do {
            if let editing = editingMessage {
                try await container.chatRepository.editMessage(
                    conversationId: conversationId, messageId: editing.id, content: text
                )
                editingMessage = nil
            } else {
                try await container.chatRepository.sendText(
                    conversationId: conversationId, text: text, replyMessageId: replyTarget?.id,
                    policyMode: policyMode, policyTtlSec: policyTtlSec,
                    mentionedUserIds: pendingMentions.isEmpty ? nil : Array(pendingMentions)
                )
                replyTarget = nil
                pendingMentions = []
            }
            inputText = ""
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "发送失败，请重试"
        }
        sending = false
    }

    private func beginRecording() async {
        isStartingRecording = true
        let granted = await voiceRecorder.requestPermission()
        guard granted else {
            errorMessage = "需要麦克风权限才能发送语音消息"
            isStartingRecording = false
            return
        }
        isRecording = voiceRecorder.start()
        isStartingRecording = false
    }

    private func finishRecording() async {
        guard isRecording else { return }
        isRecording = false
        let cancelled = willCancelRecording
        willCancelRecording = false
        guard let result = voiceRecorder.stop(cancelled: cancelled) else { return }
        defer { try? FileManager.default.removeItem(at: result.url) }
        do {
            let data = try Data(contentsOf: result.url)
            try await container.chatRepository.sendMedia(
                conversationId: conversationId, kind: "VOICE", fileData: data, fileName: "voice.m4a",
                mimeType: "audio/mp4", durationMs: result.durationMs, replyMessageId: replyTarget?.id
            )
            replyTarget = nil
        } catch {
            errorMessage = "语音发送失败"
        }
    }

    private func purge(_ message: MessageEntity) async {
        purgeTarget = nil
        do {
            try await container.chatRepository.purgeForEveryone(conversationId: conversationId, messageId: message.id)
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "删除失败"
        }
    }

    private func startEdit(_ message: MessageEntity) {
        editingMessage = message
        replyTarget = nil
        inputText = message.plaintext ?? ""
    }

    private func cancelEdit() {
        editingMessage = nil
        inputText = ""
    }

    // MARK: - 已读回执/输入状态/在线状态

    /// 挂一个只属于这个会话页面的 WS 订阅——跟 M7 CallCoordinator 直接订阅 socket 是同一个模式，
    /// 不需要 ChatRepository 帮忙转发（onEvent 本身支持多个订阅者）。视图消失后这个闭包依然挂在
    /// ChatSocketClient 的 handlers 数组里，但内部靠 conversationId 比较，对应不上的会话直接跳过，
    /// 没有实际副作用；等这个 View 被销毁，闭包捕获的 self 弱引用会失效——这里没加 [weak self]是
    /// 因为闭包捕获的是 struct 值类型 View 的一份快照，跟 class 引用计数无关，不会导致 View 泄漏。
    private func subscribeRealtimeExtras() {
        realtimeSubscriptionToken = container.chatSocketClient.onEvent { frame in
            guard frame.conversationId == conversationId, let data = frame.data,
                  let jsonData = try? JSONSerialization.data(withJSONObject: data)
            else { return }
            let myUserId = container.sessionStore.user?.id
            switch frame.event {
            case "MESSAGE_RECEIPT":
                guard let receipt = try? JSONDecoder().decode(MessageReceiptView.self, from: jsonData),
                      receipt.status == "READ", receipt.userId != myUserId
                else { return }
                lastReadMessageId = max(lastReadMessageId, receipt.messageId)
            case "TYPING":
                guard let event = try? JSONDecoder().decode(TypingEvent.self, from: jsonData),
                      event.userId != myUserId
                else { return }
                typingClearTasks.removeValue(forKey: event.userId)?.cancel()
                if event.typing {
                    typingUserIds.insert(event.userId)
                    // 对方掉线/异常退出可能没来得及发 typing=false，5 秒没收到新事件就自动清掉，
                    // 避免"正在输入"卡死不消失。
                    typingClearTasks[event.userId] = Task {
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                        guard !Task.isCancelled else { return }
                        typingUserIds.remove(event.userId)
                    }
                } else {
                    typingUserIds.remove(event.userId)
                }
            case "PRESENCE":
                guard !isGroup, let onlineUserIds = data["onlineUserIds"] as? [NSNumber] else { return }
                guard let peerId = allConversations.first(where: { $0.id == conversationId })?.peerUserId else { return }
                peerOnline = onlineUserIds.map(\.int64Value).contains(peerId)
            default:
                break
            }
        }
    }

    /// 只标"对方发的最新一条"，不用逐条上报，跟微信显示上的"已读到哪条"语义一致。
    private func reportReadReceiptIfNeeded() {
        guard allowReadReceipt, let userId = container.sessionStore.user?.id else { return }
        guard let latestPeer = messages.last(where: { $0.senderUserId != userId }) else { return }
        guard latestPeer.id > reportedReadUpTo else { return }
        reportedReadUpTo = latestPeer.id
        Task {
            try? await container.chatRepository.updateReceipt(
                conversationId: conversationId, messageId: latestPeer.id, status: "READ"
            )
        }
    }

    /// 用昵称文本匹配着删除最后一段 "@查询词"，换成 "@昵称 "——精简版没有维护"这段文字对应
    /// 哪个 userId" 的富文本 span，纯靠 pendingMentions 这个 Set 记账，@提及在文本里长什么样
    /// 跟发送时报给服务端的 userId 列表是两条独立的信息（android 的做法完全一样，见
    /// ChatThreadViewModel.insertMention 的注释）。
    private func insertMention(_ member: ConversationMemberView) {
        guard let atIndex = inputText.lastIndex(of: "@") else { return }
        let name = member.nickname ?? "用户\(member.userId)"
        inputText = String(inputText[..<atIndex]) + "@\(name) "
        pendingMentions.insert(member.userId)
    }

    private func handleComposerChange(_ value: String) {
        let isBlank = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        typingSendTask?.cancel()
        if !isBlank {
            if wasComposerBlank {
                Task { await container.chatRepository.sendTyping(conversationId: conversationId, typing: true) }
            }
            typingSendTask = Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                await container.chatRepository.sendTyping(conversationId: conversationId, typing: false)
            }
        } else if !wasComposerBlank {
            Task { await container.chatRepository.sendTyping(conversationId: conversationId, typing: false) }
        }
        wasComposerBlank = isBlank
    }

    private func recall(_ message: MessageEntity) async {
        do {
            let affected = try await container.chatRepository.recallMessage(messageId: message.id)
            if affected == 0 { errorMessage = "已超过可撤回时间" }
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "撤回失败"
        }
    }

    private func forward(_ message: MessageEntity, to target: ConversationEntity) async {
        forwardSource = nil
        do {
            try await container.chatRepository.forwardMessage(sourceMessageId: message.id, targetConversationId: target.id)
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "转发失败"
        }
    }

    private func favorite(_ message: MessageEntity) async {
        do {
            try await container.chatRepository.addFavorite(messageId: message.id)
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "收藏失败"
        }
    }

    private func react(_ message: MessageEntity, reaction: String) async {
        do {
            _ = try await container.chatRepository.addReaction(conversationId: conversationId, messageId: message.id, reaction: reaction)
        } catch {
            // 表情回应不影响主流程，失败静默忽略。
        }
    }

    private func togglePin(_ message: MessageEntity) async {
        do {
            if pinnedMessageIds.contains(message.id) {
                _ = try await container.chatRepository.unpinMessage(conversationId: conversationId, messageId: message.id)
                pinnedMessageIds.remove(message.id)
            } else {
                let pinned = try await container.chatRepository.pinMessage(conversationId: conversationId, messageId: message.id)
                pinnedMessageIds = Set(pinned.map(\.messageId))
            }
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "操作失败"
        }
    }

    private func loadPinned() async {
        guard let pinned = try? await container.chatRepository.pinnedMessages(conversationId: conversationId) else { return }
        pinnedMessageIds = Set(pinned.map(\.messageId))
    }

    /// 每次打开群聊顺手核对一遍成员名单——不是自己发起的踢人/拉人/退群也能借这个机会发现成员变了
    /// 并跟上重新分发 Sender Key，不用等专门的实时通知。指纹没变时是空操作。
    private func syncGroupMembership() async {
        guard let detail = try? await container.chatRepository.conversationDetail(conversationId: conversationId) else { return }
        await container.chatRepository.syncGroupMembership(conversationId: conversationId, memberUserIds: detail.members.map(\.userId))
    }

    // MARK: - 媒体发送

    private func sendPickedImage(_ item: PhotosPickerItem) async {
        photosPickerItem = nil
        guard let rawData = try? await item.loadTransferable(type: Data.self) else {
            errorMessage = "无法读取图片"
            return
        }
        let data = ChatMediaCompress.compressImage(rawData, mimeType: "image/jpeg")
        do {
            try await container.chatRepository.sendMedia(
                conversationId: conversationId, kind: "IMAGE",
                fileData: data, fileName: "image.jpg", mimeType: "image/jpeg",
                replyMessageId: replyTarget?.id
            )
            replyTarget = nil
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "图片发送失败"
        }
    }

    private func sendPickedFile(_ url: URL) async {
        guard url.startAccessingSecurityScopedResource() else {
            errorMessage = "无法读取文件"
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else {
            errorMessage = "无法读取文件"
            return
        }
        let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        do {
            try await container.chatRepository.sendMedia(
                conversationId: conversationId, kind: "FILE",
                fileData: data, fileName: url.lastPathComponent, mimeType: mimeType,
                replyMessageId: replyTarget?.id
            )
            replyTarget = nil
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "文件发送失败"
        }
    }
}
