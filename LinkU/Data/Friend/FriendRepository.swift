import Foundation
import SwiftData

/// 对应 android-native data/friend/FriendRepository.kt。响应式列表这边不用手写 Combine 发布器——
/// SwiftUI 视图直接用 @Query 订阅 FriendEntity/FriendRequestEntity，这个仓库只管"跟服务端同步、
/// 写回本地表"，跟 Room DAO + repository 的分工是一样的，只是"谁负责推新数据给 UI"换成了 SwiftData
/// 自己的机制。
@MainActor
final class FriendRepository {
    private let api: FriendApi
    private let modelContext: ModelContext
    private let sessionStore: SessionStore

    init(api: FriendApi, modelContext: ModelContext, sessionStore: SessionStore) {
        self.api = api
        self.modelContext = modelContext
        self.sessionStore = sessionStore
    }

    private var currentUserId: Int64? { sessionStore.user?.id }

    @discardableResult
    func refreshFriends() async throws -> [FriendView] {
        guard let userId = currentUserId else { return [] }
        let friends = try await api.listFriends(userId: userId)
        replaceAllFriends(friends)
        return friends
    }

    @discardableResult
    func refreshIncomingRequests() async throws -> [FriendRequestView] {
        guard let userId = currentUserId else { return [] }
        let requests = try await api.incomingRequests(userId: userId)
        upsertRequests(requests)
        return requests
    }

    func sendRequest(toPublicUid: String, message: String? = nil) async throws {
        guard let userId = currentUserId else { return }
        try await api.sendRequest(fromUserId: userId, toPublicUid: toPublicUid, message: message)
    }

    // accept/reject/remove 服务端成功时 data 是空的，用 throwIfFailed 而不是 dataOrThrow，
    // 否则"data 为空"会被误判成失败，明明操作成功了却报错。
    func acceptRequest(requestId: Int64) async throws {
        guard let userId = currentUserId else { return }
        try await api.acceptRequest(userId: userId, requestId: requestId)
        updateRequestStatus(requestId: requestId, status: "ACCEPTED")
        // 同意之后对方就进了我的好友列表——顺手拉一次最新好友列表同步进本地表。
        // 好友请求里没有 remark/linkId/status 这些字段，本地直接拼一条 FriendView 是残缺数据，
        // 不如老实跟服务端同步一次；同步失败不影响"已同意"这个结果本身，所以这里失败直接吞掉。
        try? await refreshFriends()
    }

    func rejectRequest(requestId: Int64) async throws {
        guard let userId = currentUserId else { return }
        try await api.rejectRequest(userId: userId, requestId: requestId)
        updateRequestStatus(requestId: requestId, status: "REJECTED")
    }

    func searchUsers(keyword: String) async throws -> [UserSearchView] {
        guard let userId = currentUserId else { return [] }
        return try await api.searchUsers(userId: userId, keyword: keyword)
    }

    func removeFriend(friendPublicUid: String) async throws {
        guard let userId = currentUserId else { return }
        try await api.removeFriend(userId: userId, friendPublicUid: friendPublicUid)
    }

    func updateRemark(friendPublicUid: String, remark: String) async throws {
        guard let userId = currentUserId else { return }
        try await api.updateRemark(userId: userId, friendPublicUid: friendPublicUid, remark: remark)
    }

    func updateBlocked(friendPublicUid: String, blocked: Bool) async throws {
        guard let userId = currentUserId else { return }
        try await api.updateBlocked(userId: userId, friendPublicUid: friendPublicUid, blocked: blocked)
    }

    // MARK: - Local cache

    private func replaceAllFriends(_ friends: [FriendView]) {
        if let existing = try? modelContext.fetch(FetchDescriptor<FriendEntity>()) {
            for entity in existing { modelContext.delete(entity) }
        }
        for view in friends {
            modelContext.insert(FriendEntity(from: view))
        }
        try? modelContext.save()
    }

    private func upsertRequests(_ requests: [FriendRequestView]) {
        for view in requests {
            let targetId = view.id
            let descriptor = FetchDescriptor<FriendRequestEntity>(
                predicate: #Predicate { $0.id == targetId }
            )
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.update(from: view)
            } else {
                modelContext.insert(FriendRequestEntity(from: view))
            }
        }
        try? modelContext.save()
    }

    private func updateRequestStatus(requestId: Int64, status: String) {
        let descriptor = FetchDescriptor<FriendRequestEntity>(
            predicate: #Predicate { $0.id == requestId }
        )
        guard let existing = try? modelContext.fetch(descriptor).first else { return }
        existing.status = status
        try? modelContext.save()
    }
}
