import SwiftData
import SwiftUI

/// 对应 android-native ui/contacts/ContactsScreen 那一支：好友列表 + 好友请求入口 + 添加好友/我的二维码。
/// 列表直接用 @Query 订阅本地表，FriendRepository 只负责跟服务端同步。
struct ContactsListView: View {
    let container: AppContainer

    @Query(sort: \FriendEntity.nickname) private var friends: [FriendEntity]
    @Query(filter: #Predicate<FriendRequestEntity> { $0.status == "PENDING" })
    private var pendingRequests: [FriendRequestEntity]

    @State private var showAddFriend = false
    @State private var showMyQr = false
    @State private var showRequests = false
    @State private var errorMessage: String?
    @State private var chatTarget: ChatTarget?
    @State private var openingChatFor: Int64?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showRequests = true
                    } label: {
                        HStack {
                            Label("新的朋友", systemImage: "person.crop.circle.badge.plus")
                            Spacer()
                            if !pendingRequests.isEmpty {
                                Text("\(pendingRequests.count)")
                                    .font(.caption2)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(LinkuBrand.danger, in: Capsule())
                            }
                        }
                    }
                }

                Section("好友（\(friends.count)）") {
                    ForEach(friends) { friend in
                        Button {
                            Task { await openChat(with: friend) }
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(LinkuAvatarColors.forName(friend.displayName))
                                    .frame(width: 40, height: 40)
                                    .overlay(Text(String(friend.displayName.prefix(1))).foregroundStyle(.white))
                                VStack(alignment: .leading) {
                                    Text(friend.displayName)
                                    if let username = friend.username, !username.isEmpty {
                                        Text(username).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if openingChatFor == friend.friendUserId {
                                    ProgressView()
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                        .disabled(openingChatFor != nil)
                    }
                }
            }
            .navigationTitle("通讯录")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { showMyQr = true } label: { Image(systemName: "qrcode") }
                    Button { showAddFriend = true } label: { Image(systemName: "person.badge.plus") }
                }
            }
            .task { await refresh() }
            .refreshable { await refresh() }
            .sheet(isPresented: $showAddFriend) {
                NavigationStack { AddFriendView(container: container) }
            }
            .sheet(isPresented: $showMyQr) {
                NavigationStack { ProfileQrView(container: container) }
            }
            .sheet(isPresented: $showRequests) {
                NavigationStack { FriendRequestsView(container: container) }
            }
            .navigationDestination(item: $chatTarget) { target in
                ChatThreadView(container: container, conversationId: target.conversationId, title: target.title)
            }
            .alert("加载失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func refresh() async {
        do {
            try await container.friendRepository.refreshFriends()
            try await container.friendRepository.refreshIncomingRequests()
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "网络异常，请稍后重试"
        }
    }

    private func openChat(with friend: FriendEntity) async {
        openingChatFor = friend.friendUserId
        do {
            let conversationId = try await container.chatRepository.openOrCreateSingleConversation(
                peerUserId: friend.friendUserId, title: friend.displayName
            )
            chatTarget = ChatTarget(conversationId: conversationId, title: friend.displayName)
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "网络异常，请稍后重试"
        }
        openingChatFor = nil
    }
}

private struct ChatTarget: Identifiable, Hashable {
    let conversationId: Int64
    let title: String
    var id: Int64 { conversationId }
}
