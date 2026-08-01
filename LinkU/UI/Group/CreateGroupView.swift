import SwiftData
import SwiftUI

/// 对应 android-native ui/contacts/CreateGroupScreen/VM：选好友 + 填标题 -> 建群。
struct CreateGroupView: View {
    let container: AppContainer
    var onCreated: (Int64) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FriendEntity.nickname) private var friends: [FriendEntity]
    @State private var title = ""
    @State private var selected: Set<Int64> = []
    @State private var creating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            TextField("群名称", text: $title)
                .textFieldStyle(.roundedBorder)
                .padding()

            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(LinkuBrand.danger).padding(.horizontal)
            }

            List(friends) { friend in
                Button {
                    toggle(friend.friendUserId)
                } label: {
                    HStack {
                        Text(friend.displayName)
                        Spacer()
                        if selected.contains(friend.friendUserId) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(LinkuBrand.primary)
                        } else {
                            Image(systemName: "circle").foregroundStyle(.secondary)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
        }
        .navigationTitle("创建群聊")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if creating {
                    ProgressView()
                } else {
                    Button("创建") { Task { await create() } }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || selected.count < 2)
                }
            }
        }
    }

    private func toggle(_ userId: Int64) {
        if selected.contains(userId) { selected.remove(userId) } else { selected.insert(userId) }
    }

    private func create() async {
        creating = true
        errorMessage = nil
        do {
            let id = try await container.chatRepository.createGroupConversation(
                title: title.trimmingCharacters(in: .whitespaces), memberUserIds: Array(selected)
            )
            onCreated(id)
            dismiss()
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "创建失败"
        }
        creating = false
    }
}
