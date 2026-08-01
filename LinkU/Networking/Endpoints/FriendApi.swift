import Foundation

/// 跟 android-native data/remote/FriendApi.kt 逐接口对应。
struct FriendApi {
    let client: ApiClient

    func listFriends(userId: Int64) async throws -> [FriendView] {
        try await client.getJSON("/api/friend/list", query: ["userId": String(userId)]).dataOrThrow()
    }

    func incomingRequests(userId: Int64) async throws -> [FriendRequestView] {
        try await client.getJSON("/api/friend/requests/incoming", query: ["userId": String(userId)]).dataOrThrow()
    }

    func sendRequest(fromUserId: Int64, toPublicUid: String, message: String?) async throws {
        let response: ApiResponse<EmptyData> = try await client.postForm(
            "/api/friend/request/send",
            fields: ["fromUserId": String(fromUserId), "toPublicUid": toPublicUid, "message": message]
        )
        try response.throwIfFailed()
    }

    func acceptRequest(userId: Int64, requestId: Int64) async throws {
        let response: ApiResponse<EmptyData> = try await client.postForm(
            "/api/friend/request/accept",
            fields: ["userId": String(userId), "requestId": String(requestId)]
        )
        try response.throwIfFailed()
    }

    func rejectRequest(userId: Int64, requestId: Int64) async throws {
        let response: ApiResponse<EmptyData> = try await client.postForm(
            "/api/friend/request/reject",
            fields: ["userId": String(userId), "requestId": String(requestId)]
        )
        try response.throwIfFailed()
    }

    func searchUsers(userId: Int64, keyword: String, limit: Int = 20) async throws -> [UserSearchView] {
        try await client.getJSON(
            "/api/friend/search",
            query: ["userId": String(userId), "keyword": keyword, "limit": String(limit)]
        ).dataOrThrow()
    }

    func removeFriend(userId: Int64, friendPublicUid: String) async throws {
        let response: ApiResponse<EmptyData> = try await client.postForm(
            "/api/friend/remove",
            fields: ["userId": String(userId), "friendPublicUid": friendPublicUid]
        )
        try response.throwIfFailed()
    }

    func updateRemark(userId: Int64, friendPublicUid: String, remark: String) async throws {
        let response: ApiResponse<Int> = try await client.postForm(
            "/api/friend/remark",
            fields: ["userId": String(userId), "friendPublicUid": friendPublicUid, "remark": remark]
        )
        _ = try response.dataOrThrow()
    }

    func updateBlocked(userId: Int64, friendPublicUid: String, blocked: Bool) async throws {
        let response: ApiResponse<Int> = try await client.postForm(
            "/api/friend/block",
            fields: ["userId": String(userId), "friendPublicUid": friendPublicUid, "blocked": blocked ? "true" : "false"]
        )
        _ = try response.dataOrThrow()
    }
}
