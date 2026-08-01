import SwiftData
import SwiftUI

/// 对应 android-native ui/profile/FavoritesScreen 的精简版：收藏列表 + 备注 + 取消收藏。
/// 语音/视频专门播放器、图片全屏画廊这些留到之后要用再补——这里图片按 ChatThreadView 同一套
/// ImageBubbleContent 渲染缩略图，文件走同一套下载/分享，核心浏览体验已经够用。
struct FavoritesView: View {
    let container: AppContainer

    @Query private var cachedConversations: [ConversationEntity]
    @State private var items: [FavoriteMessageView] = []
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var editingNoteFor: FavoriteMessageView?
    @State private var noteDraft = ""

    var body: some View {
        Group {
            if loading {
                ProgressView()
            } else if items.isEmpty {
                ContentUnavailableView("还没有收藏", systemImage: "star")
            } else {
                List {
                    ForEach(items) { item in
                        row(for: item)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("我的收藏")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .alert("出错了", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(item: $editingNoteFor) { item in
            NavigationStack {
                Form {
                    TextField("备注", text: $noteDraft, axis: .vertical)
                }
                .navigationTitle("编辑备注")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("取消") { editingNoteFor = nil }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("保存") { Task { await saveNote(item) } }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    @ViewBuilder
    private func row(for item: FavoriteMessageView) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(conversationTitle(item.conversationId))
                .font(.caption)
                .foregroundStyle(.secondary)

            content(for: item)

            if let note = item.note, !note.isEmpty {
                Text("备注：\(note)")
                    .font(.footnote)
                    .foregroundStyle(LinkuBrand.primary)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                editingNoteFor = item
                noteDraft = item.note ?? ""
            } label: {
                Label("编辑备注", systemImage: "square.and.pencil")
            }
            Button(role: .destructive) {
                Task { await remove(item) }
            } label: {
                Label("取消收藏", systemImage: "star.slash")
            }
        }
        .swipeActions {
            Button(role: .destructive) {
                Task { await remove(item) }
            } label: {
                Label("取消收藏", systemImage: "star.slash")
            }
        }
    }

    @ViewBuilder
    private func content(for item: FavoriteMessageView) -> some View {
        let raw = item.content ?? ""
        if item.messageType == "IMAGE", let payload = PlainMediaPayload.tryParse(raw) {
            ImageBubbleContent(container: container, payload: payload)
        } else if item.messageType == "FILE", let payload = PlainMediaPayload.tryParse(raw) {
            FileBubbleContent(container: container, payload: payload)
        } else {
            Text(raw.isEmpty ? "[消息]" : raw)
        }
    }

    private func conversationTitle(_ conversationId: Int64) -> String {
        cachedConversations.first(where: { $0.id == conversationId })?.title ?? "会话"
    }

    private func load() async {
        loading = true
        do {
            items = try await container.chatRepository.favorites()
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "加载失败"
        }
        loading = false
    }

    private func remove(_ item: FavoriteMessageView) async {
        do {
            try await container.chatRepository.removeFavorite(messageId: item.messageId)
            items.removeAll { $0.messageId == item.messageId }
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "操作失败"
        }
    }

    private func saveNote(_ item: FavoriteMessageView) async {
        let note = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await container.chatRepository.updateFavoriteNote(messageId: item.messageId, note: note.isEmpty ? nil : note)
            if let index = items.firstIndex(where: { $0.messageId == item.messageId }) {
                items[index].note = note.isEmpty ? nil : note
            }
            editingNoteFor = nil
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "保存失败"
        }
    }
}
