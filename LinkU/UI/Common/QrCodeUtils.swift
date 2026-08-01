import CoreImage.CIFilterBuiltins
import UIKit

/// 群邀请二维码、"我的二维码"和钱包收款码共用这一套生成/解析函数，跟 android-native
/// ui/common/QrCode.kt 对应，payload 格式必须逐字节一致——不然两端扫码互相不认。
enum QrCodeUtils {
    /// 纠错等级用 H（最高档，约 30% 可容错）——钱包收款码要在中间叠一个头像徽章挡住一块，
    /// 容错等级不够高会导致扫不出来。
    static func generateImage(content: String, size: CGFloat = 512) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(content.utf8)
        filter.correctionLevel = "H"

        guard let outputImage = filter.outputImage else { return nil }
        let scale = size / outputImage.extent.width
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// 生成可被好友扫码添加的 LinkU 名片内容——跟 Flutter/Android 端 scheme 完全一致，
    /// 这样同一个二维码，不管哪端扫，都能识别。
    static func buildProfilePayload(publicUid: String, linkId: String?) -> String {
        let trimmed = linkId?.trimmingCharacters(in: .whitespaces)
        if let trimmed, !trimmed.isEmpty {
            return "linku://add?linkId=\(trimmed)"
        }
        return "linku://add?uid=\(publicUid)"
    }

    struct ProfileTarget {
        let linkId: String?
        let publicUid: String?

        var searchKeyword: String { linkId?.isEmpty == false ? linkId! : (publicUid ?? "") }
    }

    /// 解析扫码结果，支持 linku://add?linkId= / linku://add?uid=、https://linku.app/add?... 以及裸 @linkId。
    static func parseProfilePayload(_ raw: String) -> ProfileTarget? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if text.hasPrefix("@"), text.count > 1 {
            return ProfileTarget(linkId: String(text.dropFirst()).trimmingCharacters(in: .whitespaces), publicUid: nil)
        }

        guard let components = URLComponents(string: text) else {
            return ProfileTarget(linkId: text, publicUid: nil)
        }

        func fromQuery() -> ProfileTarget? {
            let items = components.queryItems ?? []
            let linkId = items.first(where: { $0.name == "linkId" })?.value?.trimmingCharacters(in: .whitespaces)
            let uid = items.first(where: { $0.name == "uid" })?.value?.trimmingCharacters(in: .whitespaces)
            if let linkId, !linkId.isEmpty { return ProfileTarget(linkId: linkId, publicUid: nil) }
            if let uid, !uid.isEmpty { return ProfileTarget(linkId: nil, publicUid: uid) }
            return nil
        }

        if components.scheme == "linku", components.host == "add" {
            return fromQuery()
        }

        if let scheme = components.scheme, scheme == "http" || scheme == "https",
           components.host?.lowercased().replacingOccurrences(of: "www.", with: "") == "linku.app",
           components.path.split(separator: "/").first == "add" {
            return fromQuery()
        }

        return nil
    }

    /// 群邀请二维码/链接——支持 App scheme 与官网 HTTPS 落地页。
    static func parseGroupInviteToken(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let components = URLComponents(string: text) else { return nil }

        if components.scheme == "linku", components.host == "group-invite" {
            let segments = components.path.split(separator: "/").map(String.init)
            return segments.first?.trimmingCharacters(in: .whitespaces)
        }

        if let scheme = components.scheme, scheme == "http" || scheme == "https",
           components.host?.lowercased().replacingOccurrences(of: "www.", with: "") == AppConfig.webLinkHost {
            let segments = components.path.split(separator: "/").map(String.init)
            if let groupIndex = segments.firstIndex(of: "g"), groupIndex + 1 < segments.count {
                return segments[groupIndex + 1].trimmingCharacters(in: .whitespaces)
            }
        }

        return nil
    }
}
