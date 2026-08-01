import AVFoundation

/// 语音消息录制——对应 android ChatThreadScreen.kt 里直接用 MediaRecorder 写的那段（AAC 编码，
/// .m4a 容器）。iOS 侧没有单独的 ViewModel 层，这个类就是"录音机"本身，ChatThreadView 直接持有
/// 一个实例，跟 M9 的 WalletUnlockGate 一样是个纯功能类，不需要走 AppContainer 依赖注入
/// （不持有任何跨会话状态）。
@MainActor
final class VoiceRecorder: NSObject {
    private var recorder: AVAudioRecorder?
    private var startDate: Date?

    var isRecording: Bool { recorder != nil }

    /// iOS 17 新 API——`AVAudioSession.requestRecordPermission(_:)` 那套基于 completion handler
    /// 的写法已经废弃，这个 async 版本是官方现在推荐的写法。
    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    /// 开始录音，失败（拿不到麦克风/文件系统异常）返回 false。
    func start() -> Bool {
        guard recorder == nil else { return false }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            return false
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice_\(UUID().uuidString).m4a")
        // 跟 android MediaRecorder 的 MPEG_4/AAC 配置对齐——上传给服务端存的是密文字节，
        // 具体编码只有播放端自己关心，两端选同一种主流格式互相都能播就行。
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        do {
            let newRecorder = try AVAudioRecorder(url: url, settings: settings)
            guard newRecorder.record() else { return false }
            recorder = newRecorder
            startDate = Date()
            return true
        } catch {
            return false
        }
    }

    /// 停止录音——取消或者时长不足 1 秒（跟 android elapsedMs >= 1000 同一个下限）都直接删文件、
    /// 返回 nil，调用方不用再判一次。
    func stop(cancelled: Bool) -> (url: URL, durationMs: Int64)? {
        guard let recorder, let startDate else { return nil }
        recorder.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        self.recorder = nil
        self.startDate = nil
        let durationMs = Int64(Date().timeIntervalSince(startDate) * 1000)
        let url = recorder.url
        guard !cancelled, durationMs >= 1000 else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return (url, durationMs)
    }
}
