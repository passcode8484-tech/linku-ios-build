import Foundation

/// 跟 android-native data/chat/PlainMediaPayload.kt（以及 Flutter 端 plain_media_payload.dart）
/// 保持同一套明文媒体 JSON 约定——字段名/结构必须逐字节一致，这样三端互相收发的图片/文件消息
/// 才能被正确识别成媒体而不是纯文本。
enum PlainMediaPayload {
    static func encode(
        kind: String,
        objectKey: String,
        mime: String,
        size: Int64? = nil,
        durationMs: Int64? = nil,
        fileName: String? = nil,
        fileKey: String? = nil,
        fileIv: String? = nil
    ) -> String {
        var obj: [String: Any] = ["plain": true, "kind": kind, "objectKey": objectKey, "mime": mime]
        if let size { obj["size"] = size }
        if let durationMs { obj["durationMs"] = durationMs }
        if let fileName { obj["fileName"] = fileName }
        // fileKey/fileIv 非空说明服务器上存的是密文——这两个字段本身也只会出现在已经被 Signal
        // 加密过的消息体里，不会以明文形式经过服务端。
        if let fileKey { obj["fileKey"] = fileKey }
        if let fileIv { obj["fileIv"] = fileIv }
        guard let data = try? JSONSerialization.data(withJSONObject: obj), let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    static func tryParse(_ content: String) -> [String: Any]? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["plain"] as? Bool) == true,
              let kind = obj["kind"] as? String, !kind.isEmpty,
              let objectKey = obj["objectKey"] as? String, !objectKey.isEmpty
        else { return nil }
        return obj
    }

    static func objectKey(_ payload: [String: Any]) -> String? { payload["objectKey"] as? String }
    static func kind(_ payload: [String: Any]) -> String? { payload["kind"] as? String }
    static func mime(_ payload: [String: Any]) -> String? { payload["mime"] as? String }
    static func durationMs(_ payload: [String: Any]) -> Int64? { (payload["durationMs"] as? NSNumber)?.int64Value }
    static func size(_ payload: [String: Any]) -> Int64? { (payload["size"] as? NSNumber)?.int64Value }
    static func fileName(_ payload: [String: Any]) -> String? { payload["fileName"] as? String }
    static func fileKey(_ payload: [String: Any]) -> String? { payload["fileKey"] as? String }
    static func fileIv(_ payload: [String: Any]) -> String? { payload["fileIv"] as? String }

    /// 会话列表最后一条消息的预览文案。
    static func listPreview(_ content: String) -> String? {
        guard let payload = tryParse(content) else { return nil }
        switch kind(payload) {
        case "IMAGE": return "[图片]"
        case "VOICE": return "[语音]"
        case "VIDEO": return "[视频]"
        case "FILE":
            let name = fileName(payload)?.trimmingCharacters(in: .whitespaces) ?? ""
            return name.isEmpty ? "[文件]" : "[文件] \(name)"
        default: return nil
        }
    }
}
