import Foundation

/// 跟 android-native data/remote/MomentApi.kt 对应。
struct MomentApi {
    let client: ApiClient

    func feed(userId: Int64, limit: Int = 10, beforeId: Int64? = nil) async throws -> [MomentPostView] {
        try await client.getJSON(
            "/api/moment/feed",
            query: ["userId": String(userId), "limit": String(limit), "beforeId": beforeId.map(String.init)]
        ).dataOrThrow()
    }

    func mine(userId: Int64, limit: Int = 10, beforeId: Int64? = nil) async throws -> [MomentPostView] {
        try await client.getJSON(
            "/api/moment/mine",
            query: ["userId": String(userId), "limit": String(limit), "beforeId": beforeId.map(String.init)]
        ).dataOrThrow()
    }

    func userPosts(userId: Int64, targetUserId: Int64, limit: Int = 10, beforeId: Int64? = nil) async throws -> [MomentPostView] {
        try await client.getJSON(
            "/api/moment/user",
            query: [
                "userId": String(userId), "targetUserId": String(targetUserId),
                "limit": String(limit), "beforeId": beforeId.map(String.init),
            ]
        ).dataOrThrow()
    }

    func publish(
        userId: Int64,
        content: String,
        mediaJson: String?,
        visibility: String = "PUBLIC",
        locationLabel: String? = nil
    ) async throws -> MomentPostView {
        try await client.postForm(
            "/api/moment/publish",
            fields: [
                "userId": String(userId), "content": content, "mediaJson": mediaJson,
                "visibility": visibility, "locationLabel": locationLabel,
            ]
        ).dataOrThrow()
    }

    func like(userId: Int64, postId: Int64) async throws -> MomentPostView {
        try await client.postForm(
            "/api/moment/like", fields: ["userId": String(userId), "postId": String(postId)]
        ).dataOrThrow()
    }

    func unlike(userId: Int64, postId: Int64) async throws -> MomentPostView {
        try await client.postForm(
            "/api/moment/unlike", fields: ["userId": String(userId), "postId": String(postId)]
        ).dataOrThrow()
    }

    func comment(userId: Int64, postId: Int64, content: String) async throws -> MomentCommentView {
        try await client.postForm(
            "/api/moment/comment",
            fields: ["userId": String(userId), "postId": String(postId), "content": content]
        ).dataOrThrow()
    }

    func comments(userId: Int64, postId: Int64, limit: Int = 50) async throws -> [MomentCommentView] {
        try await client.getJSON(
            "/api/moment/comments",
            query: ["userId": String(userId), "postId": String(postId), "limit": String(limit)]
        ).dataOrThrow()
    }

    func likes(userId: Int64, postId: Int64, limit: Int = 50) async throws -> [MomentLikeView] {
        try await client.getJSON(
            "/api/moment/likes",
            query: ["userId": String(userId), "postId": String(postId), "limit": String(limit)]
        ).dataOrThrow()
    }
}

/// 朋友圈/圈子等"公开媒体"走这个接口——跟聊天媒体上传（需要 conversationId，且加密）是两条不同的路，
/// 这里上传的是明文（公开可见内容本来就不需要端到端加密）。
struct PublicMediaApi {
    let client: ApiClient

    /// kind 对应服务端支持的枚举：moment_image / moment_video / group_avatar。
    func upload(userId: Int64, kind: String, fileData: Data, fileName: String, mimeType: String) async throws -> MediaUploadView {
        try await client.uploadMultipart(
            "/api/user/media/upload",
            fields: ["userId": String(userId), "kind": kind],
            fileFieldName: "file",
            fileData: fileData,
            fileName: fileName,
            mimeType: mimeType
        ).dataOrThrow()
    }
}
