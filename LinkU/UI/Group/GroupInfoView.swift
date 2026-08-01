import PhotosUI
import SwiftData
import SwiftUI

/// 对应 android-native ui/group/GroupInfoScreen.kt：成员列表+邀请/移除/角色管理/禁言/转让群主、
/// 群公告、持币门槛、加群方式（审批/自动）、入群申请审批、邀请链接/二维码。入群申请列表专门
/// 显示"待审批"，已处理的（同意/拒绝）历史记录服务端接口目前也没暴露，跟 android 一样只看待办。
struct GroupInfoView: View {
    let container: AppContainer
    let conversationId: Int64

    @Environment(\.dismiss) private var dismiss
    @State private var detail: ConversationDetail?
    @State private var errorMessage: String?
    @State private var showInvite = false
    @State private var showTokenGate = false
    @State private var actionTarget: ConversationMemberView?
    @State private var muteTarget: ConversationMemberView?
    @State private var showJoinPolicy = false
    @State private var showAnnouncement = false
    @State private var showInviteLink = false
    @State private var showJoinRequests = false
    @State private var avatarItem: PhotosPickerItem?
    @State private var uploadingAvatar = false
    @State private var showRenameAlert = false
    @State private var titleDraft = ""

    private var myRole: String? {
        guard let userId = container.sessionStore.user?.id else { return nil }
        return detail?.members.first(where: { $0.userId == userId })?.role
    }

    private var isOwner: Bool { myRole == "OWNER" }
    private var isManager: Bool { myRole == "OWNER" || myRole == "ADMIN" }

    var body: some View {
        List {
            if let detail {
                Section {
                    HStack(spacing: 12) {
                        ZStack {
                            GroupAvatarView(objectKey: detail.avatar, title: detail.title, size: 56)
                            if uploadingAvatar {
                                Circle().fill(.black.opacity(0.4)).frame(width: 56, height: 56)
                                ProgressView().tint(.white)
                            }
                        }
                        .overlay(alignment: .bottomTrailing) {
                            if isManager {
                                Image(systemName: "camera.circle.fill")
                                    .foregroundStyle(LinkuBrand.primary)
                                    .background(Circle().fill(.white))
                            }
                        }
                        .overlay {
                            if isManager {
                                PhotosPicker(selection: $avatarItem, matching: .images) { Color.clear }
                                    .disabled(uploadingAvatar)
                            }
                        }

                        Button {
                            guard isManager else { return }
                            titleDraft = detail.title
                            showRenameAlert = true
                        } label: {
                            Text(detail.title).font(.headline).foregroundStyle(.primary)
                        }
                        .disabled(!isManager)

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                Section("群成员（\(detail.members.count)）") {
                    ForEach(detail.members) { member in
                        let isSelf = member.userId == container.sessionStore.user?.id
                        Button {
                            guard isManager, !isSelf else { return }
                            actionTarget = member
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(LinkuAvatarColors.forName(member.nickname ?? "用户\(member.userId)"))
                                    .frame(width: 36, height: 36)
                                    .overlay(Text(String((member.nickname ?? "?").prefix(1))).foregroundStyle(.white))
                                VStack(alignment: .leading) {
                                    Text(member.nickname ?? "用户\(member.userId)")
                                        .foregroundStyle(.primary)
                                    if member.role != "MEMBER" || member.mutedUntil != nil {
                                        HStack(spacing: 6) {
                                            if member.role != "MEMBER" {
                                                Text(member.role == "OWNER" ? "群主" : "管理员")
                                            }
                                            if member.mutedUntil != nil {
                                                Text("已禁言").foregroundStyle(LinkuBrand.danger)
                                            }
                                        }
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    Button {
                        showInvite = true
                    } label: {
                        Label("邀请好友", systemImage: "person.badge.plus")
                    }
                    Button {
                        showInviteLink = true
                    } label: {
                        Label("邀请链接/二维码", systemImage: "qrcode")
                    }
                }

                Section {
                    Button {
                        showAnnouncement = true
                    } label: {
                        Label("群公告", systemImage: "megaphone")
                    }

                    if isManager {
                        Button {
                            showJoinPolicy = true
                        } label: {
                            HStack {
                                Label("加群方式", systemImage: "person.crop.circle.badge.checkmark")
                                Spacer()
                                Text(detail.joinPolicy == "AUTO" ? "自动通过" : "需要审批")
                                    .foregroundStyle(.secondary)
                                    .font(.footnote)
                            }
                        }

                        if detail.joinPolicy != "AUTO" {
                            Button {
                                showJoinRequests = true
                            } label: {
                                Label("入群申请", systemImage: "person.badge.clock")
                            }
                        }
                    }
                }

                // 持币门槛只在群主能改——跟移除成员用同一个 isOwner 判断，管理员也不给这个权限。
                if isOwner {
                    Section {
                        Button {
                            showTokenGate = true
                        } label: {
                            HStack {
                                Text("持币门槛").foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary).font(.caption)
                            }
                        }
                    } footer: {
                        Text("设置后，只有持有指定链上代币达到门槛的用户才能加入本群。")
                    }
                }
            } else if let errorMessage {
                Text(errorMessage).foregroundStyle(LinkuBrand.danger)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("群聊信息")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("关闭") { dismiss() }
            }
        }
        .task { await load() }
        .onChange(of: avatarItem) { _, newItem in
            Task { await uploadAvatar(newItem) }
        }
        .alert("修改群名称", isPresented: $showRenameAlert) {
            TextField("群名称", text: $titleDraft)
            Button("取消", role: .cancel) {}
            Button("保存") { Task { await renameGroup() } }
        }
        .sheet(isPresented: $showInvite) {
            NavigationStack {
                InviteFriendPicker(
                    container: container,
                    excludingUserIds: Set(detail?.members.map(\.userId) ?? [])
                ) { friendUserId in
                    Task { await invite(friendUserId) }
                }
            }
        }
        .sheet(isPresented: $showTokenGate) {
            NavigationStack {
                TokenGateSheet(container: container, conversationId: conversationId)
            }
        }
        .sheet(isPresented: $showAnnouncement) {
            NavigationStack {
                GroupAnnouncementEditView(container: container, conversationId: conversationId, canEdit: isManager)
            }
        }
        .sheet(isPresented: $showInviteLink) {
            NavigationStack {
                GroupInviteLinkView(container: container, conversationId: conversationId)
            }
        }
        .sheet(isPresented: $showJoinRequests) {
            NavigationStack {
                GroupJoinRequestsView(container: container, conversationId: conversationId)
            }
        }
        .confirmationDialog("加群方式", isPresented: $showJoinPolicy, titleVisibility: .visible) {
            Button("需要审批") { Task { await updateJoinPolicy("APPROVAL") } }
            Button("自动通过") { Task { await updateJoinPolicy("AUTO") } }
            Button("取消", role: .cancel) {}
        }
        // 群成员操作——跟 android MemberActionSheet 同一套权限矩阵：设/撤管理员和禁言，管理员就能做；
        // 转让群主只有群主自己能做；移除成员管理员也能做。
        .confirmationDialog(
            actionTarget?.nickname ?? "",
            isPresented: Binding(get: { actionTarget != nil }, set: { if !$0 { actionTarget = nil } }),
            titleVisibility: .visible
        ) {
            if let target = actionTarget {
                Button(target.role == "ADMIN" ? "取消管理员" : "设为管理员") {
                    Task { await toggleAdmin(target) }
                }
                Button(target.mutedUntil != nil ? "解除禁言" : "禁言") {
                    if target.mutedUntil != nil {
                        Task { await mute(target, minutes: 0) }
                    } else {
                        muteTarget = target
                    }
                }
                if isOwner {
                    Button("转让群主", role: .destructive) {
                        Task { await transferOwner(target) }
                    }
                }
                Button("移出群聊", role: .destructive) {
                    Task { await remove(target) }
                }
                Button("取消", role: .cancel) { actionTarget = nil }
            }
        }
        .confirmationDialog(
            "禁言时长",
            isPresented: Binding(get: { muteTarget != nil }, set: { if !$0 { muteTarget = nil } }),
            titleVisibility: .visible
        ) {
            if let target = muteTarget {
                Button("10 分钟") { Task { await mute(target, minutes: 10) } }
                Button("1 小时") { Task { await mute(target, minutes: 60) } }
                Button("24 小时") { Task { await mute(target, minutes: 1440) } }
                Button("取消", role: .cancel) {}
            }
        }
    }

    private func load() async {
        do {
            detail = try await container.chatRepository.conversationDetail(conversationId: conversationId)
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "加载失败"
        }
    }

    private func uploadAvatar(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        uploadingAvatar = true
        defer { uploadingAvatar = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "读取图片失败"
                return
            }
            _ = try await container.chatRepository.updateGroupAvatar(
                conversationId: conversationId, fileData: data, fileName: "group_avatar.jpg", mimeType: "image/jpeg"
            )
            await load()
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "头像上传失败"
        }
    }

    private func renameGroup() async {
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            _ = try await container.chatRepository.updateGroupTitle(conversationId: conversationId, title: trimmed)
            await load()
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "修改失败"
        }
    }

    private func invite(_ targetUserId: Int64) async {
        showInvite = false
        do {
            _ = try await container.chatRepository.inviteMember(conversationId: conversationId, targetUserId: targetUserId)
            await load()
            await container.chatRepository.syncGroupMembership(
                conversationId: conversationId, memberUserIds: detail?.members.map(\.userId) ?? []
            )
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "邀请失败"
        }
    }

    private func remove(_ member: ConversationMemberView) async {
        actionTarget = nil
        do {
            _ = try await container.chatRepository.removeMember(conversationId: conversationId, targetUserId: member.userId)
            await load()
            await container.chatRepository.syncGroupMembership(
                conversationId: conversationId, memberUserIds: detail?.members.map(\.userId) ?? []
            )
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "移除失败"
        }
    }

    private func toggleAdmin(_ member: ConversationMemberView) async {
        actionTarget = nil
        let newRole = member.role == "ADMIN" ? "MEMBER" : "ADMIN"
        do {
            _ = try await container.chatRepository.updateMemberRole(conversationId: conversationId, targetUserId: member.userId, role: newRole)
            await load()
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "操作失败"
        }
    }

    private func mute(_ member: ConversationMemberView, minutes: Int) async {
        actionTarget = nil
        do {
            _ = try await container.chatRepository.muteMember(conversationId: conversationId, targetUserId: member.userId, minutes: minutes)
            await load()
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "操作失败"
        }
    }

    private func transferOwner(_ member: ConversationMemberView) async {
        actionTarget = nil
        do {
            _ = try await container.chatRepository.transferGroupOwner(conversationId: conversationId, targetUserId: member.userId)
            await load()
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "操作失败"
        }
    }

    private func updateJoinPolicy(_ policy: String) async {
        do {
            try await container.chatRepository.updateJoinPolicy(conversationId: conversationId, joinPolicy: policy)
            await load()
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "操作失败"
        }
    }
}

/// 群创建/邀请共用的好友选择器。
struct InviteFriendPicker: View {
    let container: AppContainer
    let excludingUserIds: Set<Int64>
    let onPick: (Int64) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FriendEntity.nickname) private var friends: [FriendEntity]

    var body: some View {
        List(friends.filter { !excludingUserIds.contains($0.friendUserId) }) { friend in
            Button {
                onPick(friend.friendUserId)
            } label: {
                Text(friend.displayName)
            }
        }
        .navigationTitle("选择好友")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("取消") { dismiss() }
            }
        }
    }
}

/// 对应 android GroupInfoScreen 的 TokenGateSheet：设置/清除群持币门槛。写入端点是服务端唯一
/// 暴露的接口——没有"读取当前门槛"的 GET，所以这里跟 android 一样是纯表单，不预填已有设置
/// （见 project_ios_native 记忆里 M5 的说明）。只支持 Ethereum/BSC 两条链，因为服务端余额校验
/// （EvmBalanceService）就只硬编码了这两条 RPC，选别的链门槛形同虚设。
private struct TokenGateSheet: View {
    let container: AppContainer
    let conversationId: Int64

    @Environment(\.dismiss) private var dismiss
    @State private var chain: ChainId = .ethereum
    @State private var tokenAddress = ""
    @State private var minAmountText = ""
    @State private var detectedSymbol: String?
    @State private var detectedDecimals: Int?
    @State private var detecting = false
    @State private var saving = false
    @State private var errorMessage: String?

    private static let supportedChains: [ChainId] = [.ethereum, .bnbChain]

    var body: some View {
        Form {
            Section("链") {
                Picker("链", selection: $chain) {
                    ForEach(Self.supportedChains) { chain in
                        Text(chain.displayName).tag(chain)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: chain) { _, _ in resetDetection() }
            }

            Section("代币合约地址（留空 = 原生币 \(chain.symbol)）") {
                TextField("0x...", text: $tokenAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: tokenAddress) { _, _ in resetDetection() }

                HStack {
                    Button {
                        Task { await detect() }
                    } label: {
                        Text(detecting ? "检测中…" : "检测代币")
                    }
                    .disabled(detecting)

                    Spacer()

                    if let detectedSymbol, let detectedDecimals {
                        Text("\(detectedSymbol) · \(detectedDecimals) 位小数")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("最低持有数量") {
                TextField("例如 10", text: $minAmountText)
                    .keyboardType(.decimalPad)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(LinkuBrand.danger).font(.footnote)
                }
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    Text(saving ? "保存中…" : "保存")
                }
                .disabled(saving)

                Button("清除持币门槛", role: .destructive) {
                    Task { await clear() }
                }
            }
        }
        .navigationTitle("持币门槛")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("关闭") { dismiss() }
            }
        }
    }

    private func resetDetection() {
        detectedSymbol = nil
        detectedDecimals = nil
        errorMessage = nil
    }

    private func detect() async {
        let address = tokenAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else {
            detectedSymbol = chain.symbol
            detectedDecimals = chain.decimals
            return
        }
        detecting = true
        errorMessage = nil
        if let meta = await container.walletRepository.detectTokenMeta(chain: chain, tokenAddress: address) {
            detectedSymbol = meta.symbol
            detectedDecimals = meta.decimals
        } else {
            errorMessage = "检测失败，请检查合约地址是否正确"
        }
        detecting = false
    }

    private func save() async {
        guard let symbol = detectedSymbol, let decimals = detectedDecimals else {
            errorMessage = "请先点「检测代币」确认符号和精度"
            return
        }
        guard let amount = Decimal(string: minAmountText.trimmingCharacters(in: .whitespacesAndNewlines)), amount > 0 else {
            errorMessage = "请输入合法的最低持有数量"
            return
        }
        guard let rawAmount = Self.rawAmountString(amount, decimals: decimals) else {
            errorMessage = "数量超出范围"
            return
        }
        saving = true
        errorMessage = nil
        do {
            let address = tokenAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            try await container.chatRepository.updateTokenGate(
                conversationId: conversationId, chain: chain.gateChainId,
                tokenAddress: address.isEmpty ? nil : address,
                minAmount: rawAmount, symbol: symbol, decimals: decimals
            )
            saving = false
            dismiss()
        } catch let ex as ApiException {
            saving = false
            errorMessage = ex.apiMessage
        } catch {
            saving = false
            errorMessage = "保存失败"
        }
    }

    private func clear() async {
        do {
            try await container.chatRepository.clearTokenGate(conversationId: conversationId)
            dismiss()
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "清除失败"
        }
    }

    private static func rawAmountString(_ amount: Decimal, decimals: Int) -> String? {
        var multiplier = Decimal(1)
        for _ in 0..<decimals { multiplier *= 10 }
        var scaled = amount * multiplier
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .down)
        guard rounded > 0 else { return nil }
        return NSDecimalNumber(decimal: rounded).stringValue
    }
}

/// 群头像——这个应用里其余所有头像（好友/群成员列表）都只画取首字母的纯色圆圈，不拉取真实
/// 图片（M2 定下的取舍，一直没改）。群头像这里破例改成真实拉图，是因为群头像走的是公开媒体
/// 接口（跟朋友圈图片同一条路，见 ChatRepository.updateGroupAvatar 的注释），上传了真图不显示
/// 出来会显得这个功能没做完；给单独一个组件而不是改全局头像组件，避免这次范围之外的大改动。
struct GroupAvatarView: View {
    let objectKey: String?
    let title: String
    let size: CGFloat

    var body: some View {
        Group {
            if let objectKey, !objectKey.isEmpty, let url = URL(string: AppConfig.mediaDownloadURL(objectKey: objectKey)) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        Circle()
            .fill(LinkuAvatarColors.forName(title))
            .overlay(Text(String(title.prefix(1))).foregroundStyle(.white))
    }
}
