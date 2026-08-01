import Foundation

/// 跟 android-native data/circle/CircleRepository.kt 对应，同样不带本地缓存层（见
/// MomentRepository 头部注释，取舍一致）。
@MainActor
final class CircleRepository {
    private let api: CircleApi
    private let sessionStore: SessionStore

    init(api: CircleApi, sessionStore: SessionStore) {
        self.api = api
        self.sessionStore = sessionStore
    }

    private func requireUserId() throws -> Int64 {
        guard let id = sessionStore.user?.id else { throw ApiException(code: -1, apiMessage: "未登录") }
        return id
    }

    func plaza(keyword: String? = nil) async throws -> [CircleView] {
        try await api.plaza(userId: try requireUserId(), keyword: keyword)
    }

    func mine() async throws -> [CircleView] {
        try await api.mine(userId: try requireUserId())
    }

    func detail(circleId: Int64) async throws -> CircleView {
        try await api.detail(userId: try requireUserId(), circleId: circleId)
    }

    func create(name: String, description: String?, tags: String = "") async throws -> CircleView {
        try await api.create(userId: try requireUserId(), name: name, description: description, tags: tags)
    }

    func join(circleId: Int64) async throws -> CircleView {
        try await api.join(userId: try requireUserId(), circleId: circleId)
    }

    func applyJoin(circleId: Int64, message: String = "") async throws -> CircleView {
        try await api.applyJoin(userId: try requireUserId(), circleId: circleId, message: message)
    }

    func leave(circleId: Int64) async throws {
        try await api.leave(userId: try requireUserId(), circleId: circleId)
    }

    func members(circleId: Int64) async throws -> [CircleMemberView] {
        try await api.members(userId: try requireUserId(), circleId: circleId)
    }

    func posts(circleId: Int64, beforeId: Int64? = nil) async throws -> [CirclePostView] {
        try await api.posts(userId: try requireUserId(), circleId: circleId, beforeId: beforeId)
    }

    func publishPost(circleId: Int64, content: String, mediaItems: [MomentMediaItem]) async throws -> CirclePostView {
        let mediaJson = mediaItems.isEmpty ? nil : MomentMediaPayload.encode(mediaItems)
        return try await api.publishPost(userId: try requireUserId(), circleId: circleId, content: content, mediaJson: mediaJson)
    }

    func likePost(postId: Int64) async throws -> CirclePostView {
        try await api.likePost(userId: try requireUserId(), postId: postId)
    }

    func unlikePost(postId: Int64) async throws -> CirclePostView {
        try await api.unlikePost(userId: try requireUserId(), postId: postId)
    }

    func commentPost(postId: Int64, content: String) async throws -> CirclePostCommentView {
        try await api.commentPost(userId: try requireUserId(), postId: postId, content: content)
    }

    func postComments(postId: Int64) async throws -> [CirclePostCommentView] {
        try await api.postComments(userId: try requireUserId(), postId: postId)
    }

    func joinRequests(circleId: Int64) async throws -> [CircleJoinRequestView] {
        try await api.joinRequests(userId: try requireUserId(), circleId: circleId)
    }

    func approveJoinRequest(circleId: Int64, requestId: Int64) async throws {
        try await api.approveJoinRequest(userId: try requireUserId(), circleId: circleId, requestId: requestId)
    }

    func rejectJoinRequest(circleId: Int64, requestId: Int64) async throws {
        try await api.rejectJoinRequest(userId: try requireUserId(), circleId: circleId, requestId: requestId)
    }
}
