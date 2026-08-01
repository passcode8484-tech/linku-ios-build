import AVFoundation
import SwiftUI

/// 图片/文件消息气泡内容——`message.plaintext` 对媒体消息来说本身就是 PlainMediaPayload JSON
/// （不是给人看的文字），这里负责解析 + 按需下载解密 + 渲染，对应 android-native
/// ChatThreadViewModel.ensureImageDecrypted / downloadFile 那部分逻辑。"仅 Wi-Fi 自动下载"
/// 开着且当前不在 Wi-Fi 时，本地已缓存的图正常显示，没缓存的先停在"点击加载"占位，不自动拉。
struct ImageBubbleContent: View {
    let container: AppContainer
    let payload: [String: Any]

    @AppStorage("linku.chat.autoDownloadWifiOnly") private var autoDownloadWifiOnly = false
    @AppStorage("linku.chat.autoSaveMedia") private var autoSaveMedia = false
    @ObservedObject private var networkMonitor: NetworkMonitor

    @State private var localURL: URL?
    @State private var loadFailed = false
    @State private var pendingManualLoad = false
    @State private var loading = false
    @State private var showFullscreen = false

    init(container: AppContainer, payload: [String: Any]) {
        self.container = container
        self.payload = payload
        self.networkMonitor = container.networkMonitor
    }

    var body: some View {
        Group {
            if let localURL, let uiImage = UIImage(contentsOfFile: localURL.path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 180, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .onTapGesture { showFullscreen = true }
            } else if loadFailed {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 180, height: 180)
                    .overlay(Image(systemName: "exclamationmark.triangle"))
            } else if pendingManualLoad {
                Button {
                    Task { await load(force: true) }
                } label: {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 180, height: 180)
                        .overlay(
                            VStack(spacing: 6) {
                                Image(systemName: "arrow.down.circle")
                                Text("点击加载图片").font(.caption2)
                            }
                        )
                }
                .buttonStyle(.plain)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 180, height: 180)
                    .overlay(ProgressView())
            }
        }
        .task { await load() }
        .fullScreenCover(isPresented: $showFullscreen) {
            if let localURL, let uiImage = UIImage(contentsOfFile: localURL.path) {
                ZStack(alignment: .topTrailing) {
                    Color.black.ignoresSafeArea()
                    Image(uiImage: uiImage).resizable().scaledToFit()
                    Button {
                        showFullscreen = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                            .padding()
                    }
                }
            }
        }
    }

    private func load(force: Bool = false) async {
        guard !loading else { return }
        guard let objectKey = PlainMediaPayload.objectKey(payload) else {
            loadFailed = true
            return
        }
        let mime = PlainMediaPayload.mime(payload) ?? "image/jpeg"
        let ext = mime.split(separator: "/").last.map(String.init) ?? "jpg"

        if let cached = ChatRepository.cachedMediaURL(objectKey: objectKey, suggestedExtension: ext) {
            localURL = cached
            pendingManualLoad = false
            return
        }
        if !force, autoDownloadWifiOnly, !networkMonitor.isOnWifi {
            pendingManualLoad = true
            return
        }

        loading = true
        pendingManualLoad = false
        do {
            let url = try await container.chatRepository.downloadAndDecryptMedia(
                objectKey: objectKey,
                fileKey: PlainMediaPayload.fileKey(payload),
                fileIv: PlainMediaPayload.fileIv(payload),
                suggestedExtension: ext
            )
            localURL = url
            if autoSaveMedia {
                Task { await MediaGallerySaver.saveImage(at: url) }
            }
        } catch {
            loadFailed = true
        }
        loading = false
    }
}

struct FileBubbleContent: View {
    let container: AppContainer
    let payload: [String: Any]

    @State private var localURL: URL?
    @State private var downloading = false
    @State private var showShare = false
    @State private var errorText: String?

    private var fileName: String { PlainMediaPayload.fileName(payload) ?? "文件" }
    private var sizeText: String {
        guard let size = PlainMediaPayload.size(payload) else { return "" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var body: some View {
        Button {
            Task { await downloadAndShare() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.fill")
                    .font(.title2)
                    .foregroundStyle(LinkuBrand.primary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(fileName).lineLimit(1)
                    if !sizeText.isEmpty {
                        Text(sizeText).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if downloading { ProgressView() }
            }
            .padding(10)
            .frame(maxWidth: 220)
        }
        .buttonStyle(.plain)
        .disabled(downloading)
        .sheet(isPresented: $showShare) {
            if let localURL {
                ActivityView(items: [localURL])
            }
        }
    }

    private func downloadAndShare() async {
        guard let objectKey = PlainMediaPayload.objectKey(payload) else { return }
        if let localURL {
            _ = localURL
            showShare = true
            return
        }
        downloading = true
        let ext = (fileName as NSString).pathExtension.isEmpty ? "dat" : (fileName as NSString).pathExtension
        do {
            localURL = try await container.chatRepository.downloadAndDecryptMedia(
                objectKey: objectKey,
                fileKey: PlainMediaPayload.fileKey(payload),
                fileIv: PlainMediaPayload.fileIv(payload),
                suggestedExtension: ext
            )
            showShare = true
        } catch {
            errorText = "下载失败"
        }
        downloading = false
    }
}

/// 包一层系统分享面板——用户可以选"存到文件"/用其他 App 打开，对应安卓端"下载到本地再交给
/// 系统打开方式"的思路。
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// 语音消息播放——点一下播放/暂停，贴近耳朵自动切听筒（VoiceProximityRouter，见该文件注释）。
struct VoiceBubbleContent: View {
    let container: AppContainer
    let payload: [String: Any]
    let isMine: Bool

    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var loading = false
    @State private var loadFailed = false
    @State private var delegate: VoicePlaybackDelegate?
    @State private var proximityRouter = VoiceProximityRouter()

    private var durationSeconds: Int {
        max(1, Int((PlainMediaPayload.durationMs(payload) ?? 0) / 1000))
    }

    var body: some View {
        Button {
            Task { await togglePlayback() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: loadFailed ? "exclamationmark.triangle" : (isPlaying ? "pause.fill" : "play.fill"))
                Text("\(durationSeconds)″")
                if loading { ProgressView().tint(isMine ? .white : .primary) }
            }
            .frame(minWidth: 70)
        }
        .buttonStyle(.plain)
        .disabled(loading)
        .onChange(of: isPlaying) { _, playing in
            if playing { proximityRouter.start() } else { proximityRouter.stop() }
        }
        .onDisappear {
            player?.stop()
            proximityRouter.stop()
        }
    }

    private func togglePlayback() async {
        if let player {
            if isPlaying {
                player.pause()
                isPlaying = false
            } else {
                player.play()
                isPlaying = true
            }
            return
        }
        guard let objectKey = PlainMediaPayload.objectKey(payload) else {
            loadFailed = true
            return
        }
        loading = true
        do {
            let localURL = try await container.chatRepository.downloadAndDecryptMedia(
                objectKey: objectKey,
                fileKey: PlainMediaPayload.fileKey(payload),
                fileIv: PlainMediaPayload.fileIv(payload),
                suggestedExtension: "m4a"
            )
            // playAndRecord（而不是单纯 playback）才能用 overrideOutputAudioPort 切到听筒——
            // 这里不实际录音，只是借这个 category 打开"可以走听筒"这条路。
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth])
            try AVAudioSession.sharedInstance().setActive(true)
            let newPlayer = try AVAudioPlayer(contentsOf: localURL)
            let newDelegate = VoicePlaybackDelegate { isPlaying = false }
            newPlayer.delegate = newDelegate
            delegate = newDelegate
            newPlayer.play()
            player = newPlayer
            isPlaying = true
        } catch {
            loadFailed = true
        }
        loading = false
    }
}

/// AVAudioPlayerDelegate 只能挂在 NSObject 子类上，SwiftUI View 本身不是——单独包一层，
/// 只关心"播完了"这一件事。
private final class VoicePlaybackDelegate: NSObject, AVAudioPlayerDelegate {
    let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [onFinish] in onFinish() }
    }
}
