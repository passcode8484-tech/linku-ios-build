import SwiftData
import SwiftUI

/// 对应 android-native ui/main/MainShellScreen.kt 的四 Tab 主壳。四个 Tab 都已经接上真实内容。
struct MainShellView: View {
    private let container: AppContainer
    @ObservedObject private var sessionStore: SessionStore
    @ObservedObject private var pushNavHub = PushNavHub.shared
    @Query private var cachedConversations: [ConversationEntity]

    init(container: AppContainer) {
        self.container = container
        self.sessionStore = container.sessionStore
    }

    var body: some View {
        TabView {
            ChatListView(container: container)
                .tabItem { Label("聊天", systemImage: "message") }

            ContactsListView(container: container)
                .tabItem { Label("通讯录", systemImage: "person.2") }

            DiscoverView(container: container)
                .tabItem { Label("发现", systemImage: "safari") }

            ProfileTab(container: container, sessionStore: sessionStore, authRepository: container.authRepository)
                .tabItem { Label("我", systemImage: "person.crop.circle") }
        }
        .tint(LinkuBrand.primary)
        .task { await container.pushTokenManager.ensureRegistered() }
        .fullScreenCover(isPresented: pushChatBinding) {
            if case .chat(let conversationId) = pushNavHub.pending {
                NavigationStack {
                    ChatThreadView(
                        container: container,
                        conversationId: conversationId,
                        isGroup: pushTargetIsGroup(conversationId),
                        title: pushTargetTitle(conversationId)
                    )
                }
            }
        }
        .sheet(isPresented: pushFriendRequestsBinding) {
            NavigationStack { FriendRequestsView(container: container) }
        }
        .onChange(of: pushNavHub.pending) { _, target in
            // 来电推送不需要单独的界面——CallCoordinator 自己查一次待接来电，查到了会把
            // state 切到 .incoming，RootView 顶层的 CallView 会自动盖上来，这里只管消费掉目标。
            guard case .incomingCall(let callId) = target else { return }
            container.callCoordinator.checkPendingCalls(callId: callId)
            pushNavHub.consume()
        }
        // group_join_request 这类推送目标还没有对应界面（要等群管理页面补入群审批），
        // 先只识别不跳转，避免用户点了通知却卡在一个空白页。
    }

    private var pushChatBinding: Binding<Bool> {
        Binding(
            get: { if case .chat = pushNavHub.pending { return true } else { return false } },
            set: { if !$0 { pushNavHub.consume() } }
        )
    }

    private var pushFriendRequestsBinding: Binding<Bool> {
        Binding(
            get: { pushNavHub.pending == .friendRequests },
            set: { if !$0 { pushNavHub.consume() } }
        )
    }

    /// 推送点进来时本地会话缓存不一定已经有这条会话（比如对方刚建的新会话）——命中就用真实标题/
    /// 类型，没命中就用占位，ChatThreadView 进去后自己会拉一次 conversationDetail 补全。
    private func pushTargetTitle(_ conversationId: Int64) -> String {
        cachedConversations.first(where: { $0.id == conversationId })?.title ?? "聊天"
    }

    private func pushTargetIsGroup(_ conversationId: Int64) -> Bool {
        cachedConversations.first(where: { $0.id == conversationId })?.type == "GROUP"
    }
}

private struct ProfileTab: View {
    let container: AppContainer
    @ObservedObject var sessionStore: SessionStore
    let authRepository: AuthRepository

    @State private var showWalletSetup = false
    @State private var showWalletHome = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(LinkuAvatarColors.forName(sessionStore.user?.nickname ?? ""))
                            .frame(width: 48, height: 48)
                            .overlay(
                                Text(String((sessionStore.user?.nickname ?? "?").prefix(1)))
                                    .foregroundStyle(.white)
                            )
                        VStack(alignment: .leading) {
                            Text(sessionStore.user?.nickname ?? "未登录")
                                .font(.headline)
                            Text(sessionStore.user?.linkId ?? sessionStore.user?.publicUid ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Button {
                        if container.walletRepository.hasWallet {
                            showWalletHome = true
                        } else {
                            showWalletSetup = true
                        }
                    } label: {
                        HStack {
                            Label("钱包", systemImage: "wallet.pass")
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary).font(.caption)
                        }
                    }
                    .foregroundStyle(.primary)

                    NavigationLink {
                        SettingsView(container: container)
                    } label: {
                        Label("设置", systemImage: "gearshape")
                    }
                }

                Section {
                    Button("退出登录", role: .destructive) {
                        Task { await authRepository.logout() }
                    }
                }
            }
            .navigationTitle("我")
            .navigationDestination(isPresented: $showWalletHome) {
                WalletHomeView(container: container)
            }
            .sheet(isPresented: $showWalletSetup) {
                WalletSetupView(container: container) {
                    showWalletHome = true
                }
            }
        }
    }
}
