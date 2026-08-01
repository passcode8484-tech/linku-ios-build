import Foundation

/// 跟 android-native data/remote/CircleApi.kt 对应，覆盖同样的"核心链路"范围（广场/我的/详情/
/// 加入/发帖/互动/入圈审批）。
struct CircleApi {
    let client: ApiClient

    func plaza(userId: Int64, keyword: String? = nil, tag: String? = nil, sort: String = "newest", limit: Int = 50) async throws -> [CircleView] {
        try await client.getJSON(
            "/api/circle/plaza",
            query: ["userId": String(userId), "keyword": keyword, "tag": tag, "sort": sort, "limit": String(limit)]
        ).dataOrThrow()
    }

    func mine(userId: Int64, keyword: String? = nil, sort: String = "newest", limit: Int = 50) async throws -> [CircleView] {
        try await client.getJSON(
            "/api/circle/mine",
            query: ["userId": String(userId), "keyword": keyword, "sort": sort, "limit": String(limit)]
        ).dataOrThrow()
    }

    func detail(userId: Int64, circleId: Int64) async throws -> CircleView {
        try await client.getJSON(
            "/api/circle/detail", query: ["userId": String(userId), "circleId": String(circleId)]
        ).dataOrThrow()
    }

    func create(userId: Int64, name: String, description: String?, tags: String = "") async throws -> CircleView {
        try await client.postForm(
            "/api/circle/create",
            fields: ["userId": String(userId), "name": name, "description": description, "tags": tags]
        ).dataOrThrow()
    }

    func join(userId: Int64, circleId: Int64) async throws -> CircleView {
        try await client.postForm(
            "/api/circle/join", fields: ["userId": String(userId), "circleId": String(circleId)]
        ).dataOrThrow()
    }

    func applyJoin(userId: Int64, circleId: Int64, message: String = "") async throws -> CircleView {
        try await client.postForm(
            "/api/circle/join/apply",
            fields: ["userId": String(userId), "circleId": String(circleId), "message": message]
        ).dataOrThrow()
    }

    func leave(userId: Int64, circleId: Int64) async throws {
        let response: ApiResponse<EmptyData> = try await client.postForm(
            "/api/circle/leave", fields: ["userId": String(userId), "circleId": String(circleId)]
        )
        try response.throwIfFailed()
    }

    func members(userId: Int64, circleId: Int64, limit: Int = 100) async throws -> [CircleMemberView] {
        try await client.getJSON(
            "/api/circle/members",
            query: ["userId": String(userId), "circleId": String(circleId), "limit": String(limit)]
        ).dataOrThrow()
    }

    func posts(userId: Int64, circleId: Int64, limit: Int = 10, beforeId: Int64? = nil) async throws -> [CirclePostView] {
        try await client.getJSON(
            "/api/circle/posts",
            query: [
                "userId": String(userId), "circleId": String(circleId),
                "limit": String(limit), "beforeId": beforeId.map(String.init),
            ]
        ).dataOrThrow()
    }

    func publishPost(userId: Int64, circleId: Int64, content: String, mediaJson: String?) async throws -> CirclePostView {
        try await client.postForm(
            "/api/circle/post/publish",
            fields: ["userId": String(userId), "circleId": String(circleId), "content": content, "mediaJson": mediaJson]
        ).dataOrThrow()
    }

    func likePost(userId: Int64, postId: Int64) async throws -> CirclePostView {
        try await client.postForm(
            "/api/circle/post/like", fields: ["userId": String(userId), "postId": String(postId)]
        ).dataOrThrow()
    }

    func unlikePost(userId: Int64, postId: Int64) async throws -> CirclePostView {
        try await client.postForm(
            "/api/circle/post/unlike", fields: ["userId": String(userId), "postId": String(postId)]
        ).dataOrThrow()
    }

    func commentPost(userId: Int64, postId: Int64, content: String, replyToCommentId: Int64? = nil) async throws -> CirclePostCommentView {
        try await client.postForm(
            "/api/circle/post/comment",
            fields: [
                "userId": String(userId), "postId": String(postId), "content": content,
                "replyToCommentId": replyToCommentId.map(String.init),
            ]
        ).dataOrThrow()
    }

    func postComments(userId: Int64, postId: Int64, limit: Int = 50) async throws -> [CirclePostCommentView] {
        try await client.getJSON(
            "/api/circle/post/comments",
            query: ["userId": String(userId), "postId": String(postId), "limit": String(limit)]
        ).dataOrThrow()
    }

    func joinRequests(userId: Int64, circleId: Int64, limit: Int = 50) async throws -> [CircleJoinRequestView] {
        try await client.getJSON(
            "/api/circle/join/requests",
            query: ["userId": String(userId), "circleId": String(circleId), "limit": String(limit)]
        ).dataOrThrow()
    }

    func approveJoinRequest(userId: Int64, circleId: Int64, requestId: Int64) async throws {
        let response: ApiResponse<EmptyData> = try await client.postForm(
            "/api/circle/join/request/approve",
            fields: ["userId": String(userId), "circleId": String(circleId), "requestId": String(requestId)]
        )
        try response.throwIfFailed()
    }

    func rejectJoinRequest(userId: Int64, circleId: Int64, requestId: Int64) async throws {
        let response: ApiResponse<EmptyData> = try await client.postForm(
            "/api/circle/join/request/reject",
            fields: ["userId": String(userId), "circleId": String(circleId), "requestId": String(requestId)]
        )
        try response.throwIfFailed()
    }
}
