import Photos
import UIKit

/// 对应 android saveMediaToGallery（写 MediaStore）——iOS 这边用 PHPhotoLibrary 的"仅新增"权限
/// （NSPhotoLibraryAddUsageDescription，不需要完整相册读取权限），跟系统"存储图片"这个动作的
/// 隐私粒度匹配。只在 ChatSettingsView 的"自动保存媒体到相册"开关打开时调用。
enum MediaGallerySaver {
    @discardableResult
    static func saveImage(at fileURL: URL) async -> Bool {
        guard let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) else { return false }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}
