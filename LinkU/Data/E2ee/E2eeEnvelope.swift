import Foundation

/// 消息体不再是明文——`content` 字段里存的是这一段 JSON 密文信封，字段和解析容错逻辑跟
/// android-native E2eeEnvelope.kt 逐字段对应：字段缺失时按同样的默认值兜底（不是严格反序列化），
/// 因为这里要解析的是别人（甚至是老版本自己）发过来的、格式可能不完全规整的字符串，解析失败/
/// 字段缺失都不该整体崩掉。
struct E2eePreview: Equatable {
    var kind: String?
    var text: String?
    var durationMs: Int64?
}

struct E2eeEnvelope: Equatable {
    var version: Int
    var scheme: String
    var type: String
    var conversationType: String
    var senderDeviceId: String
    var registrationId: Int
    var ciphertext: String
    var messageType: Int
    var preview: E2eePreview?

    func encode() -> String {
        var obj: [String: Any] = [
            "v": version,
            "scheme": scheme,
            "type": type,
            "conversationType": conversationType,
            "senderDeviceId": senderDeviceId,
            "registrationId": registrationId,
            "ciphertext": ciphertext,
            "messageType": messageType,
        ]
        if let preview {
            var previewObj: [String: Any] = [:]
            if let kind = preview.kind { previewObj["kind"] = kind }
            if let text = preview.text { previewObj["text"] = text }
            if let durationMs = preview.durationMs { previewObj["durationMs"] = durationMs }
            obj["preview"] = previewObj
        }
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static let legacyLockedPreview = "🔒 加密消息"
    static let listPreviewFallback = "新消息"
    static let failedDecryptPreview = "[无法解密]"

    static func tryParse(_ raw: String) -> E2eeEnvelope? {
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["scheme"] as? String) == "signal"
        else { return nil }

        var preview: E2eePreview?
        if let previewObj = obj["preview"] as? [String: Any] {
            preview = E2eePreview(
                kind: previewObj["kind"] as? String,
                text: previewObj["text"] as? String,
                durationMs: (previewObj["durationMs"] as? NSNumber)?.int64Value
            )
        }

        return E2eeEnvelope(
            version: (obj["v"] as? NSNumber)?.intValue ?? 1,
            scheme: obj["scheme"] as? String ?? "signal",
            type: obj["type"] as? String ?? "ciphertext",
            conversationType: obj["conversationType"] as? String ?? "SINGLE",
            senderDeviceId: obj["senderDeviceId"] as? String ?? "1",
            registrationId: (obj["registrationId"] as? NSNumber)?.intValue ?? 0,
            ciphertext: obj["ciphertext"] as? String ?? "",
            messageType: (obj["messageType"] as? NSNumber)?.intValue ?? 0,
            preview: preview
        )
    }

    static func looksEncrypted(_ raw: String) -> Bool { tryParse(raw) != nil }

    static func isSenderKeyDistribution(_ raw: String) -> Bool { tryParse(raw)?.type == "sender_key_distribution" }

    static func needsDecrypt(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed == legacyLockedPreview || looksEncrypted(trimmed)
    }

    /// 聊天列表/消息气泡解密失败时的兜底文案——forList 时用更中性的"新消息"，单条气泡里用更明确的"[无法解密]"。
    static func previewText(_ raw: String, forList: Bool = false) -> String {
        if let envelope = tryParse(raw), let preview = envelope.preview {
            if let text = preview.text?.trimmingCharacters(in: .whitespaces), !text.isEmpty {
                return text
            }
            switch preview.kind {
            case "IMAGE": return "[图片]"
            case "VIDEO": return "[视频]"
            case "VOICE": return "[语音]"
            case "FILE": return "[文件]"
            default: break
            }
        }
        if needsDecrypt(raw) { return forList ? listPreviewFallback : failedDecryptPreview }
        return raw
    }

    static func isReadablePlaintext(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != legacyLockedPreview else { return false }
        return !looksEncrypted(trimmed)
    }

    /// 能写进本地缓存的"真明文"——排除占位/解密失败提示，避免把这些提示文字当成真实消息内容缓存下来。
    static func isPersistablePlaintext(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isReadablePlaintext(trimmed) else { return false }
        return trimmed != listPreviewFallback && trimmed != failedDecryptPreview
    }
}
