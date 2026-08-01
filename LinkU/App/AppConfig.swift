import Foundation

/// 跟 android-native 的 AppConfig.kt 一个思路：正式包连线上，本机联调时把
/// `useProductionInDebug` 改成 false 走 localhost（真机需要电脑和手机同一局域网，
/// 把 LOCAL_BASE_URL 换成电脑的局域网 IP，不能用 localhost）。不要把 false 提交进仓库。
enum AppConfig {
    static let productionBaseURL = "https://chatapi.starcents.org"
    static let webLinkBase = "https://link.starcents.org"
    static let webLinkHost = "link.starcents.org"
    private static let localBaseURL = "http://localhost:9090"

    private static let useProductionInDebug = true

    static var baseURL: String {
        #if DEBUG
        return useProductionInDebug ? productionBaseURL : localBaseURL
        #else
        return productionBaseURL
        #endif
    }

    static var wsURL: String {
        baseURL
            .replacingOccurrences(of: "http://", with: "ws://")
            .replacingOccurrences(of: "https://", with: "wss://")
            + "/ws/im"
    }

    /// 头像/朋友圈等公共媒体（objectKey 以 public/ 开头）走这个下载，不需要鉴权。
    static func mediaDownloadURL(objectKey: String) -> String {
        let encoded = objectKey.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? objectKey
        return "\(baseURL)/api/public/media/download?objectKey=\(encoded)"
    }

    /// 聊天消息里的图片/语音/视频（objectKey 以 chat/ 开头）必须走这个鉴权下载接口——
    /// 公共媒体接口只接受 public/ 前缀的 objectKey，传 chat/ 前缀会被服务端拒绝。
    static func chatMediaDownloadURL(objectKey: String, userId: Int64) -> String {
        let encoded = objectKey.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? objectKey
        return "\(baseURL)/api/im/media/download?objectKey=\(encoded)&userId=\(userId)"
    }

    static func groupInviteWebURL(token: String, locale: String = "zh") -> String {
        "\(webLinkBase)/\(locale)/g/\(token)/"
    }
}

extension CharacterSet {
    /// URLQueryAllowed 默认放行 `&`/`=`/`+` 等会破坏 query string 结构的字符，
    /// 拼 query value 时要用这个更严格的集合，不能直接用 .urlQueryAllowed。
    static let urlQueryValueAllowed: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }()
}
