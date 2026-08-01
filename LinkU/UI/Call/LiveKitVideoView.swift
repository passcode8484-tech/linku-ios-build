import LiveKit
import SwiftUI

/// LiveKit 的 VideoView 是 UIKit 视图（内部叫 NativeView，iOS 上就是 UIView 子类），
/// SDK 本身没有提供现成的 SwiftUI 封装，这里自己包一层 UIViewRepresentable。
struct LiveKitVideoView: UIViewRepresentable {
    let track: VideoTrack?

    func makeUIView(context: Context) -> VideoView {
        let view = VideoView()
        view.layoutMode = .fill
        return view
    }

    func updateUIView(_ uiView: VideoView, context: Context) {
        uiView.track = track
    }
}
