import LiveKit
import SwiftUI

/// 对应 android-native ui/call/CallScreen.kt。挂在 RootView 顶层，跟当前在哪个 Tab 无关——
/// CallCoordinator.state 一旦不是 .idle 就盖一层全屏通话界面上去。
struct CallView: View {
    @ObservedObject var coordinator: CallCoordinator

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch coordinator.state {
            case .idle:
                EmptyView()
            case .incoming(let signal):
                IncomingCallContent(signal: signal, coordinator: coordinator)
            case .outgoing(let session):
                CallingContent(name: session.callerName ?? "对方", statusText: "正在呼叫…", coordinator: coordinator)
            case .connecting:
                CallingContent(name: "", statusText: "连接中…", coordinator: coordinator)
            case .active(let session):
                ActiveCallContent(session: session, coordinator: coordinator)
            }
        }
        .alert("通话异常", isPresented: Binding(get: { coordinator.error != nil }, set: { if !$0 { coordinator.clearError() } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(coordinator.error ?? "")
        }
    }
}

private struct IncomingCallContent: View {
    let signal: CallSignalEvent
    @ObservedObject var coordinator: CallCoordinator

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Circle()
                .fill(LinkuAvatarColors.forName(signal.callerName ?? ""))
                .frame(width: 96, height: 96)
                .overlay(Text(String((signal.callerName ?? "?").prefix(1))).font(.largeTitle).foregroundStyle(.white))
            Text(signal.callerName ?? "未知来电").font(.title2.bold()).foregroundStyle(.white)
            Text(signal.mediaType == "VIDEO" ? "邀请你视频通话" : "邀请你语音通话")
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            HStack(spacing: 60) {
                CallActionButton(systemImage: "phone.down.fill", tint: .red) { coordinator.rejectIncoming() }
                CallActionButton(systemImage: "phone.fill", tint: .green) { coordinator.acceptIncoming() }
            }
            .padding(.bottom, 60)
        }
    }
}

private struct CallingContent: View {
    let name: String
    let statusText: String
    @ObservedObject var coordinator: CallCoordinator

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Circle()
                .fill(LinkuAvatarColors.forName(name))
                .frame(width: 96, height: 96)
                .overlay(Text(String(name.prefix(1))).font(.largeTitle).foregroundStyle(.white))
            Text(name).font(.title2.bold()).foregroundStyle(.white)
            Text(statusText).foregroundStyle(.white.opacity(0.8))
            Spacer()
            CallActionButton(systemImage: "phone.down.fill", tint: .red) { coordinator.hangup() }
                .padding(.bottom, 60)
        }
    }
}

private struct ActiveCallContent: View {
    let session: CallSessionView
    @ObservedObject var coordinator: CallCoordinator

    @State private var micEnabled = true
    @State private var cameraEnabled: Bool

    init(session: CallSessionView, coordinator: CallCoordinator) {
        self.session = session
        self.coordinator = coordinator
        _cameraEnabled = State(initialValue: session.mediaType == "VIDEO")
    }

    private var remoteVideoTrack: VideoTrack? {
        coordinator.room.remoteParticipants.values.first?.firstCameraVideoTrack
    }

    private var localVideoTrack: VideoTrack? {
        coordinator.room.localParticipant.firstCameraVideoTrack
    }

    var body: some View {
        ZStack {
            if let remoteVideoTrack {
                LiveKitVideoView(track: remoteVideoTrack).ignoresSafeArea()
            } else {
                VStack(spacing: 16) {
                    Circle()
                        .fill(LinkuAvatarColors.forName(session.callerName ?? ""))
                        .frame(width: 96, height: 96)
                        .overlay(Text(String((session.callerName ?? "?").prefix(1))).font(.largeTitle).foregroundStyle(.white))
                    Text(session.callerName ?? "对方").font(.title2.bold()).foregroundStyle(.white)
                }
            }

            if cameraEnabled, let localVideoTrack {
                LiveKitVideoView(track: localVideoTrack)
                    .frame(width: 110, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.3)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding()
            }

            VStack {
                Spacer()
                controls
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 40) {
            CallActionButton(systemImage: micEnabled ? "mic.fill" : "mic.slash.fill", tint: .white.opacity(0.25)) {
                toggleMic()
            }
            if session.mediaType == "VIDEO" {
                CallActionButton(systemImage: cameraEnabled ? "video.fill" : "video.slash.fill", tint: .white.opacity(0.25)) {
                    toggleCamera()
                }
            }
            CallActionButton(systemImage: "phone.down.fill", tint: .red) {
                coordinator.hangup()
            }
        }
        .padding(.bottom, 50)
    }

    private func toggleMic() {
        micEnabled.toggle()
        Task { try? await coordinator.room.localParticipant.setMicrophone(enabled: micEnabled) }
    }

    private func toggleCamera() {
        cameraEnabled.toggle()
        Task { try? await coordinator.room.localParticipant.setCamera(enabled: cameraEnabled) }
    }
}

private struct CallActionButton: View {
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title)
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(tint, in: Circle())
        }
    }
}
