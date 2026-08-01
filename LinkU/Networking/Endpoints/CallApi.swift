import Foundation

/// 跟 android-native data/remote/CallApi.kt 对应。注意这几个接口服务端是 @Query 不是表单体，
/// 即使 invite/accept/reject/hangup 是 POST，参数也走 query string。
struct CallApi {
    let client: ApiClient

    func pending(userId: Int64) async throws -> [CallSessionView] {
        try await client.getJSON("/api/im/calls/pending", query: ["userId": String(userId)]).dataOrThrow()
    }

    func detail(callId: String, userId: Int64) async throws -> CallSessionView {
        try await client.getJSON(
            "/api/im/calls/detail", query: ["callId": callId, "userId": String(userId)]
        ).dataOrThrow()
    }

    func invite(conversationId: Int64, userId: Int64, mediaType: String) async throws -> CallSessionView {
        try await postWithQuery(
            "/api/im/calls/invite",
            query: ["conversationId": String(conversationId), "userId": String(userId), "mediaType": mediaType]
        )
    }

    func accept(callId: String, userId: Int64) async throws -> CallSessionView {
        try await postWithQuery("/api/im/calls/accept", query: ["callId": callId, "userId": String(userId)])
    }

    func reject(callId: String, userId: Int64, reason: String? = nil) async throws -> CallSessionView {
        try await postWithQuery(
            "/api/im/calls/reject", query: ["callId": callId, "userId": String(userId), "reason": reason]
        )
    }

    func hangup(callId: String, userId: Int64, reason: String? = nil) async throws -> CallSessionView {
        try await postWithQuery(
            "/api/im/calls/hangup", query: ["callId": callId, "userId": String(userId), "reason": reason]
        )
    }

    func liveKitToken(callId: String, userId: Int64) async throws -> CallSessionView {
        try await client.getJSON(
            "/api/im/calls/livekit-token", query: ["callId": callId, "userId": String(userId)]
        ).dataOrThrow()
    }

    /// 这几个 POST 接口参数在 query string 里、body 是空的——ApiClient 目前的 postForm 是走
    /// x-www-form-urlencoded body，这里借用它的路径构造但把参数塞进 URL 上，不塞进 body。
    private func postWithQuery(_ path: String, query: [String: String?]) async throws -> CallSessionView {
        try await client.postFormWithQuery(path, query: query).dataOrThrow()
    }
}
