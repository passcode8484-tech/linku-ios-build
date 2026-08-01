import UIKit

/// 跟 android-native data/chat/ChatMediaCompress.kt（以及 Flutter 端 chat_media_compress.dart）
/// 保持同一套参数——最长边 1920px + JPEG q82，三端发出去的图片体积/画质一致。已经是较小 JPEG
/// 时跳过重新编码，没必要为了一张本来就不大的图再吃一次编解码开销。
enum ChatMediaCompress {
    private static let maxSide: CGFloat = 1920
    private static let jpegQuality: CGFloat = 0.82
    private static let skipBelowBytes = 256 * 1024

    /// 压缩失败（不是合法图片数据之类）直接返回原始 data，调用方不用关心失败细节——
    /// 发一张没压缩的图总比发送失败强。
    static func compressImage(_ data: Data, mimeType: String) -> Data {
        if mimeType == "image/jpeg", data.count < skipBelowBytes {
            return data
        }
        // UIImage(data:) 已经按 EXIF 方向把图片摆正了（.imageOrientation 属性只是标记，真正
        // 绘制到新 context 里才会把方向"烤"进像素数据本身）——用 UIGraphicsImageRenderer
        // 重绘一遍顺带完成了 android 那边手动读 ExifInterface 转 Matrix 做的事，不用照抄那套。
        guard let image = UIImage(data: data) else { return data }
        let longSide = max(image.size.width, image.size.height)
        let scale = longSide > maxSide ? maxSide / longSide : 1
        let targetSize = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: jpegQuality) ?? data
    }
}
