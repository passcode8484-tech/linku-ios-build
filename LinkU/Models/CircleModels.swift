import Foundation

/// 跟 android-native remote/dto/CircleDtos.kt 逐字段对应，覆盖核心链路（广场/我的/详情/加入/
/// 发帖/互动/入圈审批）——统计/举报/话题订阅/编辑历史/访客记录这些运营向长尾功能安卓端自己都
/// 没做原生端，iOS 跟进同样的取舍。
struct CircleView: Codable, Equatable, Identifiable {
    let id: Int64
    let name: String
    let description: String?
    let avatarText: String?
    let ownerUserId: Int64
    let ownerNickname: String?
    let memberCount: Int
    let isPublic: Bool
    let joined: Bool
    let conversationId: Int64?
    let coverObjectKey: String?
    let announcement: String?
    let tags: String?
    let joinRequestStatus: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description, avatarText, ownerUserId, ownerNickname, memberCount
        case isPublic, joined, conversationId, coverObjectKey, announcement, tags
        case joinRequestStatus, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        avatarText = try container.decodeIfPresent(String.self, forKey: .avatarText)
        ownerUserId = try container.decode(Int64.self, forKey: .ownerUserId)
        ownerNickname = try container.decodeIfPresent(String.self, forKey: .ownerNickname)
        memberCount = try container.decodeIfPresent(Int.self, forKey: .memberCount) ?? 0
        isPublic = try container.decodeIfPresent(Bool.self, forKey: .isPublic) ?? true
        joined = try container.decodeIfPresent(Bool.self, forKey: .joined) ?? false
        conversationId = try container.decodeIfPresent(Int64.self, forKey: .conversationId)
        coverObjectKey = try container.decodeIfPresent(String.self, forKey: .coverObjectKey)
        announcement = try container.decodeIfPresent(String.self, forKey: .announcement)
        tags = try container.decodeIfPresent(String.self, forKey: .tags)
        joinRequestStatus = try container.decodeIfPresent(String.self, forKey: .joinRequestStatus)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }
}

struct CirclePostView: Codable, Equatable, Identifiable {
    let id: Int64
    let circleId: Int64
    let userId: Int64
    let authorNickname: String?
    let content: String
    let imageUrls: String?
    let likeCount: Int
    let commentCount: Int
    let liked: Bool
    let circleName: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, circleId, userId, authorNickname, content, imageUrls
        case likeCount, commentCount, liked, circleName, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        circleId = try container.decode(Int64.self, forKey: .circleId)
        userId = try container.decode(Int64.self, forKey: .userId)
        authorNickname = try container.decodeIfPresent(String.self, forKey: .authorNickname)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        imageUrls = try container.decodeIfPresent(String.self, forKey: .imageUrls)
        likeCount = try container.decodeIfPresent(Int.self, forKey: .likeCount) ?? 0
        commentCount = try container.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0
        liked = try container.decodeIfPresent(Bool.self, forKey: .liked) ?? false
        circleName = try container.decodeIfPresent(String.self, forKey: .circleName)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }
}

struct CircleJoinRequestView: Codable, Equatable, Identifiable {
    let id: Int64
    let circleId: Int64
    let userId: Int64
    let nickname: String?
    let message: String?
    let status: String
    let createdAt: String?
}

struct CircleMemberView: Codable, Equatable, Identifiable {
    let userId: Int64
    let nickname: String?
    let role: String
    let joinedAt: String?
    var id: Int64 { userId }
}

struct CirclePostCommentView: Codable, Equatable, Identifiable {
    let id: Int64
    let postId: Int64
    let userId: Int64
    let authorNickname: String?
    let content: String
    let replyToCommentId: Int64?
    let replyToNickname: String?
    let createdAt: String?
}
