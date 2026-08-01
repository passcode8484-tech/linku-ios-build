import AVFoundation
import UIKit

/// 对应 android VoiceProximityRouter——语音消息播放时贴近耳朵自动切听筒、拿开自动切回外放，
/// 跟打电话时的行为一致。iOS 用 UIDevice.proximityState 而不是原始距离传感器数值（系统已经做好
/// 了阈值判断），配合 AVAudioSession 的输出端口覆盖来回切换。
@MainActor
final class VoiceProximityRouter {
    private var observer: NSObjectProtocol?

    func start() {
        let device = UIDevice.current
        device.isProximityMonitoringEnabled = true
        observer = NotificationCenter.default.addObserver(
            forName: UIDevice.proximityStateDidChangeNotification, object: device, queue: .main
        ) { [weak self] _ in
            self?.applyRoute(near: device.proximityState)
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        UIDevice.current.isProximityMonitoringEnabled = false
        // 播放结束/组件销毁时，把输出端口切回外放的默认状态，不留一个"下次播放莫名从听筒
        // 出声"的悬空设置。
        try? AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
    }

    private func applyRoute(near: Bool) {
        try? AVAudioSession.sharedInstance().overrideOutputAudioPort(near ? .none : .speaker)
    }
}
