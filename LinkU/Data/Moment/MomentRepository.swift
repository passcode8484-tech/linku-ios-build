import Foundation

/// 跟 android-native data/moment/MomentRepository.kt 对应。没有搬安卓那套 Room 本地缓存
/// （MomentDao "本地优先秒开"那部分）——朋友圈刷新本来就要等网络，iOS 这版先接受"打开时转一下"，
/// 不算功能缺失，只是少一层离线/秒开体验，用到时再补。
@MainActor
final class MomentRepository {
    private let api: MomentApi
    private let publicMediaApi: PublicMediaApi
    private let sessionStore: SessionStore

    init(api: MomentApi, publicMediaApi: PublicMediaApi, sessionStore: SessionStore) {
        self.api = api
        self.publicMediaApi = publicMediaApi
        self.sessionStore = sessionStore
    }

    private func requireUserId() throws -> Int64 {
        guard let id = sessionStore.user?.id else { throw ApiException(code: -1, apiMessage: "未登录") }
        return id
    }

    func feed(beforeId: Int64? = nil) async throws -> [MomentPostView] {
        try await api.feed(userId: try requireUserId(), beforeId: beforeId)
    }

    func mine(beforeId: Int64? = nil) async throws -> [MomentPostView] {
        try await api.mine(userId: try requireUserId(), beforeId: beforeId)
    }

    func userPosts(targetUserId: Int64, beforeId: Int64? = nil) async throws -> [MomentPostView] {
        try await api.userPosts(userId: try requireUserId(), targetUserId: targetUserId, beforeId: beforeId)
    }

    func publish(content: String, mediaItems: [MomentMediaItem], visibility: String = "PUBLIC", locationLabel: String? = nil) async throws -> MomentPostView {
        let mediaJson = mediaItems.isEmpty ? nil : MomentMediaPayload.encode(mediaItems)
        return try await api.publish(
            userId: try requireUserId(), content: content, mediaJson: mediaJson,
            visibility: visibility, locationLabel: locationLabel
        )
    }

    func like(postId: Int64) async throws -> MomentPostView {
        try await api.like(userId: try requireUserId(), postId: postId)
    }

    func unlike(postId: Int64) async throws -> MomentPostView {
        try await api.unlike(userId: try requireUserId(), postId: postId)
    }

    func comment(postId: Int64, content: String) async throws -> MomentCommentView {
        try await api.comment(userId: try requireUserId(), postId: postId, content: content)
    }

    func comments(postId: Int64) async throws -> [MomentCommentView] {
        try await api.comments(userId: try requireUserId(), postId: postId)
    }

    func likes(postId: Int64) async throws -> [MomentLikeView] {
        try await api.likes(userId: try requireUserId(), postId: postId)
    }

    /// kind 对应服务端支持的枚举：moment_image / moment_video。
    func uploadMedia(fileData: Data, fileName: String, mimeType: String, kind: String) async throws -> MediaUploadView {
        try await publicMediaApi.upload(userId: try requireUserId(), kind: kind, fileData: fileData, fileName: fileName, mimeType: mimeType)
    }
}
