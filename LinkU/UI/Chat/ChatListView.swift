import SwiftData
import SwiftUI

/// 对应 android-native ui/chat/ChatListScreen.kt。列表直接用 @Query 订阅本地会话表，
/// ChatRepository 只负责跟服务端同步。
struct ChatListView: View {
    let container: AppContainer

    @Query(sort: \ConversationEntity.updatedAt, order: .reverse) private var conversations: [ConversationEntity]
    @State private var errorMessage: String?
    @State private var showCreateGroup = false

    var body: some View {
        NavigationStack {
            List(conversations) { conversation in
                NavigationLink {
                    ChatThreadView(
                        container: container,
                        conversationId: conversation.id,
                        isGroup: conversation.type == "GROUP",
                        title: conversation.title
                    )
                } label: {
                    row(for: conversation)
                }
            }
            .overlay {
                if conversations.isEmpty {
                    ContentUnavailableView("暂无会话", systemImage: "message", description: Text("去通讯录找好友聊天吧"))
                }
            }
            .navigationTitle("聊天")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showCreateGroup = true } label: { Image(systemName: "person.3") }
                }
            }
            .sheet(isPresented: $showCreateGroup) {
                NavigationStack {
                    CreateGroupView(container: container) { _ in }
                }
            }
            .task { await refresh() }
            .refreshable { await refresh() }
            .alert("加载失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func row(for conversation: ConversationEntity) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(LinkuAvatarColors.forName(conversation.title))
                .frame(width: 44, height: 44)
                .overlay(Text(String(conversation.title.prefix(1))).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.title).font(.body)
                Text(conversation.lastMessage ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if conversation.unreadCount > 0 {
                Text("\(conversation.unreadCount)")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(LinkuBrand.danger, in: Capsule())
            }
        }
    }

    private func refresh() async {
        do {
            try await container.chatRepository.refreshConversations()
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "网络异常，请稍后重试"
        }
    }
}
