import Foundation

/// 跟 android-native remote/dto/CallDtos.kt 逐字段对应。
struct CallSessionView: Codable, Equatable {
    let callId: String
    let conversationId: Int64
    let callerId: Int64
    let calleeId: Int64
    let callerName: String?
    let callerAvatar: String?
    let mediaType: String
    let state: String
    let livekitUrl: String?
    let livekitRoom: String?
    let livekitToken: String?

    enum CodingKeys: String, CodingKey {
        case callId, conversationId, callerId, calleeId, callerName, callerAvatar
        case mediaType, state, livekitUrl, livekitRoom, livekitToken
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callId = try container.decode(String.self, forKey: .callId)
        conversationId = try container.decode(Int64.self, forKey: .conversationId)
        callerId = try container.decode(Int64.self, forKey: .callerId)
        calleeId = try container.decode(Int64.self, forKey: .calleeId)
        callerName = try container.decodeIfPresent(String.self, forKey: .callerName)
        callerAvatar = try container.decodeIfPresent(String.self, forKey: .callerAvatar)
        mediaType = try container.decodeIfPresent(String.self, forKey: .mediaType) ?? "AUDIO"
        state = try container.decodeIfPresent(String.self, forKey: .state) ?? "RINGING"
        livekitUrl = try container.decodeIfPresent(String.self, forKey: .livekitUrl)
        livekitRoom = try container.decodeIfPresent(String.self, forKey: .livekitRoom)
        livekitToken = try container.decodeIfPresent(String.self, forKey: .livekitToken)
    }
}

/// WS 信令帧的 data 部分，跟服务端 CallSignalEvent 对应。
struct CallSignalEvent: Codable, Equatable {
    let callId: String
    let conversationId: Int64
    let callerId: Int64
    let calleeId: Int64
    let callerName: String?
    let callerAvatar: String?
    let mediaType: String?
    let state: String?
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case callId, conversationId, callerId, calleeId, callerName, callerAvatar, mediaType, state, reason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        callId = try container.decode(String.self, forKey: .callId)
        conversationId = try container.decode(Int64.self, forKey: .conversationId)
        callerId = try container.decode(Int64.self, forKey: .callerId)
        calleeId = try container.decode(Int64.self, forKey: .calleeId)
        callerName = try container.decodeIfPresent(String.self, forKey: .callerName)
        callerAvatar = try container.decodeIfPresent(String.self, forKey: .callerAvatar)
        mediaType = try container.decodeIfPresent(String.self, forKey: .mediaType)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
    }
}
