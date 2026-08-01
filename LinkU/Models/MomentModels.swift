import Foundation

/// 跟 android-native remote/dto/MomentDtos.kt 逐字段对应。
struct MomentPostView: Codable, Equatable, Identifiable {
    let id: Int64
    let userId: Int64
    let authorNickname: String?
    let authorAvatar: String?
    let content: String
    let imageUrls: String?
    let visibility: String
    let locationLabel: String?
    let likeCount: Int
    let commentCount: Int
    let liked: Bool
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, userId, authorNickname, authorAvatar, content, imageUrls, visibility
        case locationLabel, likeCount, commentCount, liked, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        userId = try container.decode(Int64.self, forKey: .userId)
        authorNickname = try container.decodeIfPresent(String.self, forKey: .authorNickname)
        authorAvatar = try container.decodeIfPresent(String.self, forKey: .authorAvatar)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        imageUrls = try container.decodeIfPresent(String.self, forKey: .imageUrls)
        visibility = try container.decodeIfPresent(String.self, forKey: .visibility) ?? "PUBLIC"
        locationLabel = try container.decodeIfPresent(String.self, forKey: .locationLabel)
        likeCount = try container.decodeIfPresent(Int.self, forKey: .likeCount) ?? 0
        commentCount = try container.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0
        liked = try container.decodeIfPresent(Bool.self, forKey: .liked) ?? false
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }
}

struct MomentCommentView: Codable, Equatable, Identifiable {
    let id: Int64
    let postId: Int64
    let userId: Int64
    let authorNickname: String?
    let content: String
    let createdAt: String?
}

struct MomentLikeView: Codable, Equatable, Identifiable {
    let userId: Int64
    let nickname: String?
    var id: Int64 { userId }
}

/// 跟 Flutter/android 端保持同一套 JSON 约定：{"items":[{"kind":"IMAGE"|"VIDEO","key":...}]}。
/// 圈子帖子（CirclePostView.imageUrls）复用同一份编解码。
struct MomentMediaItem: Equatable {
    let isVideo: Bool
    let key: String
    let coverKey: String?
    let durationMs: Int64?

    init(isVideo: Bool, key: String, coverKey: String? = nil, durationMs: Int64? = nil) {
        self.isVideo = isVideo
        self.key = key
        self.coverKey = coverKey
        self.durationMs = durationMs
    }
}

enum MomentMediaPayload {
    static func encode(_ items: [MomentMediaItem]) -> String {
        let array: [[String: Any]] = items.map { item in
            if item.isVideo {
                return [
                    "kind": "VIDEO", "key": item.key,
                    "coverKey": item.coverKey ?? "", "durationMs": item.durationMs ?? 0,
                ]
            }
            return ["kind": "IMAGE", "key": item.key]
        }
        let root: [String: Any] = ["items": array]
        guard let data = try? JSONSerialization.data(withJSONObject: root), let json = String(data: data, encoding: .utf8) else {
            return "{\"items\":[]}"
        }
        return json
    }

    static func decode(_ raw: String?) -> [MomentMediaItem] {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = obj["items"] as? [[String: Any]]
        else { return [] }
        return items.compactMap { item -> MomentMediaItem? in
            guard let key = item["key"] as? String, !key.isEmpty else { return nil }
            let isVideo = (item["kind"] as? String)?.uppercased() == "VIDEO"
            let durationMs = (item["durationMs"] as? NSNumber)?.int64Value
            return MomentMediaItem(isVideo: isVideo, key: key, coverKey: item["coverKey"] as? String, durationMs: durationMs)
        }
    }
}
