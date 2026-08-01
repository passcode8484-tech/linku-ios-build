import PhotosUI
import SwiftUI

/// 对应 android-native ui/discover/MomentFeedViewModel + 对应界面。没有本地缓存(见
/// MomentRepository 头部注释)，每次进这个 Tab/下拉刷新都是真网络请求。
struct MomentsFeedView: View {
    let container: AppContainer

    @State private var posts: [MomentPostView] = []
    @State private var errorMessage: String?
    @State private var showComposer = false

    var body: some View {
        List(posts) { post in
            MomentRow(container: container, post: post) { updated in
                if let index = posts.firstIndex(where: { $0.id == updated.id }) {
                    posts[index] = updated
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if posts.isEmpty {
                ContentUnavailableView("还没有朋友圈动态", systemImage: "photo.on.rectangle.angled")
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showComposer = true } label: { Image(systemName: "square.and.pencil") }
            }
        }
        .task { await refresh() }
        .refreshable { await refresh() }
        .sheet(isPresented: $showComposer) {
            NavigationStack {
                MomentComposerView(container: container) { Task { await refresh() } }
            }
        }
        .alert("加载失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func refresh() async {
        do {
            posts = try await container.momentRepository.feed()
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "网络异常，请稍后重试"
        }
    }
}

struct MomentRow: View {
    let container: AppContainer
    let post: MomentPostView
    let onUpdate: (MomentPostView) -> Void

    @State private var showComments = false
    @State private var liking = false

    private var mediaItems: [MomentMediaItem] { MomentMediaPayload.decode(post.imageUrls) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(LinkuAvatarColors.forName(post.authorNickname ?? ""))
                    .frame(width: 36, height: 36)
                    .overlay(Text(String((post.authorNickname ?? "?").prefix(1))).foregroundStyle(.white))
                VStack(alignment: .leading) {
                    Text(post.authorNickname ?? "用户\(post.userId)").font(.subheadline.bold())
                    if let locationLabel = post.locationLabel, !locationLabel.isEmpty {
                        Text(locationLabel).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            if !post.content.isEmpty {
                Text(post.content)
            }

            if !mediaItems.isEmpty {
                MomentMediaGrid(objectKeys: mediaItems.map(\.key))
            }

            HStack {
                Button {
                    Task { await toggleLike() }
                } label: {
                    Label("\(post.likeCount)", systemImage: post.liked ? "heart.fill" : "heart")
                        .foregroundStyle(post.liked ? LinkuBrand.danger : .secondary)
                }
                .disabled(liking)
                .buttonStyle(.plain)

                Button {
                    showComments = true
                } label: {
                    Label("\(post.commentCount)", systemImage: "bubble.right")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()
                if let createdAt = post.createdAt {
                    Text(createdAt).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .font(.footnote)
        }
        .padding(.vertical, 6)
        .sheet(isPresented: $showComments) {
            NavigationStack { MomentCommentsView(container: container, postId: post.id) }
        }
    }

    private func toggleLike() async {
        liking = true
        do {
            let updated = post.liked
                ? try await container.momentRepository.unlike(postId: post.id)
                : try await container.momentRepository.like(postId: post.id)
            onUpdate(updated)
        } catch {
            // 点赞失败不影响主流程，静默忽略。
        }
        liking = false
    }
}

/// 公开媒体（朋友圈/圈子图片）不加密，直接用鉴权下载链接给 AsyncImage 加载即可，
/// 不用像聊天媒体那样先下载解密到本地文件。
struct MomentMediaGrid: View {
    let objectKeys: [String]

    private let columns = [GridItem(.adaptive(minimum: 90), spacing: 4)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(objectKeys, id: \.self) { key in
                AsyncImage(url: URL(string: AppConfig.mediaDownloadURL(objectKey: key))) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Color.gray.opacity(0.15)
                    }
                }
                .frame(width: 90, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
