import SwiftUI

struct MomentCommentsView: View {
    let container: AppContainer
    let postId: Int64

    @Environment(\.dismiss) private var dismiss
    @State private var comments: [MomentCommentView] = []
    @State private var draft = ""
    @State private var sending = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            List(comments) { comment in
                VStack(alignment: .leading, spacing: 2) {
                    Text(comment.authorNickname ?? "用户\(comment.userId)").font(.caption.bold())
                    Text(comment.content)
                }
            }
            .listStyle(.plain)
            .overlay {
                if comments.isEmpty {
                    ContentUnavailableView("还没有评论", systemImage: "bubble.right")
                }
            }

            HStack {
                TextField("说点什么…", text: $draft)
                    .textFieldStyle(.roundedBorder)
                Button("发送") { Task { await send() } }
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || sending)
            }
            .padding()
        }
        .navigationTitle("评论")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("关闭") { dismiss() }
            }
        }
        .task { await load() }
        .alert("操作失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func load() async {
        do {
            comments = try await container.momentRepository.comments(postId: postId)
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "加载失败"
        }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        sending = true
        do {
            let created = try await container.momentRepository.comment(postId: postId, content: text)
            comments.append(created)
            draft = ""
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "发送失败"
        }
        sending = false
    }
}
