import Foundation

/// 跟 android-native data/call/CallRepository.kt 对应，薄封装。
struct CallRepository {
    let api: CallApi

    func pending(userId: Int64) async throws -> [CallSessionView] {
        try await api.pending(userId: userId)
    }

    func invite(conversationId: Int64, userId: Int64, mediaType: String) async throws -> CallSessionView {
        try await api.invite(conversationId: conversationId, userId: userId, mediaType: mediaType)
    }

    func accept(callId: String, userId: Int64) async throws -> CallSessionView {
        try await api.accept(callId: callId, userId: userId)
    }

    func reject(callId: String, userId: Int64) async throws {
        _ = try await api.reject(callId: callId, userId: userId)
    }

    func hangup(callId: String, userId: Int64) async throws {
        _ = try await api.hangup(callId: callId, userId: userId)
    }

    func liveKitToken(callId: String, userId: Int64) async throws -> CallSessionView {
        try await api.liveKitToken(callId: callId, userId: userId)
    }
}
