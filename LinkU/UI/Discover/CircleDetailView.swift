import SwiftUI

/// 对应 android-native ui/discover/CircleDetailScreen/VM。
struct CircleDetailView: View {
    let container: AppContainer
    let circleId: Int64

    @State private var circle: CircleView?
    @State private var posts: [CirclePostView] = []
    @State private var errorMessage: String?
    @State private var joining = false
    @State private var showComposer = false

    var body: some View {
        List {
            if let circle {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(circle.name).font(.title3.bold())
                        if let description = circle.description, !description.isEmpty {
                            Text(description).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Text("\(circle.memberCount) 位成员 · 群主 \(circle.ownerNickname ?? "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if circle.joined {
                            Button("退出圈子", role: .destructive) { Task { await leave() } }
                                .disabled(joining)
                        } else {
                            Button(circle.joinRequestStatus == "PENDING" ? "申请审核中" : "加入圈子") {
                                Task { await join() }
                            }
                            .disabled(joining || circle.joinRequestStatus == "PENDING")
                            .buttonStyle(.borderedProminent)
                            .tint(LinkuBrand.primary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("帖子") {
                ForEach(posts) { post in
                    CirclePostRow(container: container, post: post) { updated in
                        if let index = posts.firstIndex(where: { $0.id == updated.id }) {
                            posts[index] = updated
                        }
                    }
                }
            }
        }
        .navigationTitle(circle?.name ?? "圈子")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if circle?.joined == true {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showComposer = true } label: { Image(systemName: "square.and.pencil") }
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showComposer) {
            NavigationStack {
                CirclePostComposerView(container: container, circleId: circleId) { Task { await load() } }
            }
        }
        .alert("操作失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func load() async {
        do {
            async let detailTask = container.circleRepository.detail(circleId: circleId)
            async let postsTask = container.circleRepository.posts(circleId: circleId)
            circle = try await detailTask
            posts = try await postsTask
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "加载失败"
        }
    }

    private func join() async {
        joining = true
        do {
            circle = try await container.circleRepository.join(circleId: circleId)
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "加入失败"
        }
        joining = false
    }

    private func leave() async {
        joining = true
        do {
            try await container.circleRepository.leave(circleId: circleId)
            await load()
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "退出失败"
        }
        joining = false
    }
}

private struct CirclePostRow: View {
    let container: AppContainer
    let post: CirclePostView
    let onUpdate: (CirclePostView) -> Void

    @State private var liking = false

    private var mediaItems: [MomentMediaItem] { MomentMediaPayload.decode(post.imageUrls) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(post.authorNickname ?? "用户\(post.userId)").font(.caption.bold())
            if !post.content.isEmpty { Text(post.content) }
            if !mediaItems.isEmpty {
                MomentMediaGrid(objectKeys: mediaItems.map(\.key))
            }
            Button {
                Task { await toggleLike() }
            } label: {
                Label("\(post.likeCount)", systemImage: post.liked ? "heart.fill" : "heart")
                    .font(.footnote)
                    .foregroundStyle(post.liked ? LinkuBrand.danger : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(liking)
        }
        .padding(.vertical, 4)
    }

    private func toggleLike() async {
        liking = true
        do {
            let updated = post.liked
                ? try await container.circleRepository.unlikePost(postId: post.id)
                : try await container.circleRepository.likePost(postId: post.id)
            onUpdate(updated)
        } catch {
            // 静默忽略，不影响主流程。
        }
        liking = false
    }
}

struct CirclePostComposerView: View {
    let container: AppContainer
    let circleId: Int64
    var onPublished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var content = ""
    @State private var publishing = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading) {
            TextEditor(text: $content)
                .frame(height: 160)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
                .padding()
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(LinkuBrand.danger).padding(.horizontal)
            }
            Spacer()
        }
        .navigationTitle("发帖")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if publishing {
                    ProgressView()
                } else {
                    Button("发表") { Task { await publish() } }
                        .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func publish() async {
        publishing = true
        do {
            _ = try await container.circleRepository.publishPost(circleId: circleId, content: content, mediaItems: [])
            onPublished()
            dismiss()
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "发表失败"
        }
        publishing = false
    }
}
