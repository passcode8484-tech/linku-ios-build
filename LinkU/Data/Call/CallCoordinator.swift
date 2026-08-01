import Foundation
import LiveKit

/// 通话信令跟聊天走同一条单用户 WS 连接（CALL_* 事件），对应 android-native CallCoordinator.kt——
/// 进程内单例，跟当前显示哪个 Tab 无关，随时可能收到 CALL_RING 弹出来电界面。
enum CallUiState: Equatable {
    case idle
    case incoming(CallSignalEvent)
    case outgoing(CallSessionView)
    case connecting(callId: String)
    case active(CallSessionView)

    var callId: String? {
        switch self {
        case .idle: return nil
        case .incoming(let signal): return signal.callId
        case .outgoing(let session): return session.callId
        case .connecting(let callId): return callId
        case .active(let session): return session.callId
        }
    }
}

@MainActor
final class CallCoordinator: NSObject, ObservableObject {
    @Published private(set) var state: CallUiState = .idle
    @Published var error: String?

    let room = Room()

    private let socket: ChatSocketClient
    private let repository: CallRepository
    private let sessionStore: SessionStore
    private let callKit: CallKitManager

    private var currentUserId: Int64? { sessionStore.user?.id }

    init(socket: ChatSocketClient, repository: CallRepository, sessionStore: SessionStore, callKit: CallKitManager) {
        self.socket = socket
        self.repository = repository
        self.sessionStore = sessionStore
        self.callKit = callKit
        super.init()

        room.add(delegate: self)

        callKit.onAnswer = { [weak self] callId in
            Task { @MainActor in self?.acceptIncoming(matchingCallId: callId) }
        }
        callKit.onEnd = { [weak self] callId in
            Task { @MainActor in self?.hangupFromCallKit(matchingCallId: callId) }
        }

        socket.onEvent { [weak self] frame in
            Task { @MainActor in self?.handleFrame(frame) }
        }
    }

    private func handleFrame(_ frame: ChatSocketFrame) {
        guard frame.event.hasPrefix("CALL_"), let data = frame.data else { return }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data),
              let signal = try? JSONDecoder().decode(CallSignalEvent.self, from: jsonData)
        else { return }

        switch frame.event {
        case "CALL_RING":
            setState(.incoming(signal))
        case "CALL_ACCEPTED":
            if case .outgoing(let session) = state, session.callId == signal.callId {
                Task { await fetchTokenAndActivate(callId: signal.callId) }
            }
        case "CALL_REJECTED", "CALL_END":
            guard state.callId == signal.callId else { return }
            if signal.reason == "TIMEOUT" { error = "对方无法接通" }
            endLocally(reason: .remoteEnded)
        default:
            break
        }
    }

    /// 所有状态切换都走这里——离开/进入 incoming 时顺带控制 CallKit 来电上报，
    /// 不用在每个改状态的地方重复处理。
    private func setState(_ next: CallUiState) {
        if case .incoming(let signal) = next {
            callKit.reportIncomingCall(
                callId: signal.callId,
                callerName: signal.callerName ?? "未知",
                hasVideo: signal.mediaType == "VIDEO"
            )
        }
        state = next
    }

    // MARK: - 应用是被"有来电"的推送点开时用——见 M6 PushNavTarget.incomingCall

    func checkPendingCalls(callId: String? = nil) {
        guard state == .idle, let userId = currentUserId else { return }
        Task {
            guard let sessions = try? await repository.pending(userId: userId) else { return }
            guard let target = sessions.first(where: { $0.state == "RINGING" && $0.calleeId == userId })
            else { return }
            if let callId, target.callId != callId { return }
            guard state == .idle else { return }
            setState(.incoming(CallSignalEvent(
                callId: target.callId, conversationId: target.conversationId,
                callerId: target.callerId, calleeId: target.calleeId,
                callerName: target.callerName, callerAvatar: target.callerAvatar,
                mediaType: target.mediaType, state: target.state, reason: nil
            )))
        }
    }

    // MARK: - 发起/接听/拒绝/挂断

    func startOutgoingCall(conversationId: Int64, mediaType: String) {
        guard let userId = currentUserId else { return }
        Task {
            do {
                let session = try await repository.invite(conversationId: conversationId, userId: userId, mediaType: mediaType)
                setState(.outgoing(session))
                callKit.reportOutgoingCallStarted(callId: session.callId, calleeName: session.callerName ?? "对方")
            } catch {
                self.error = (error as? ApiException)?.apiMessage ?? "发起通话失败"
            }
        }
    }

    /// App 内自己点了接听按钮（不是从系统来电界面）——照样走 CallKit 请求一遍，
    /// 让系统状态（比如打断其他 App 的音频）保持一致。
    func acceptIncoming() {
        guard case .incoming(let signal) = state else { return }
        callKit.reportOutgoingCallStarted(callId: signal.callId, calleeName: signal.callerName ?? "")
        acceptIncoming(matchingCallId: signal.callId)
    }

    private func acceptIncoming(matchingCallId callId: String) {
        guard case .incoming(let signal) = state, signal.callId == callId, let userId = currentUserId else { return }
        setState(.connecting(callId: callId))
        Task {
            do {
                _ = try await repository.accept(callId: callId, userId: userId)
                await fetchTokenAndActivate(callId: callId)
            } catch {
                self.error = (error as? ApiException)?.apiMessage ?? "接听失败"
                endLocally(reason: .failed)
            }
        }
    }

    func rejectIncoming() {
        guard case .incoming(let signal) = state, let userId = currentUserId else { return }
        let callId = signal.callId
        endLocally(reason: .remoteEnded)
        Task { try? await repository.reject(callId: callId, userId: userId) }
    }

    func hangup() {
        guard let callId = state.callId, let userId = currentUserId else { return }
        callKit.requestEndCall(callId: callId)
        endLocally(reason: .remoteEnded)
        Task { try? await repository.hangup(callId: callId, userId: userId) }
    }

    private func hangupFromCallKit(matchingCallId callId: String) {
        guard state.callId == callId, let userId = currentUserId else { return }
        endLocally(reason: .remoteEnded)
        Task { try? await repository.hangup(callId: callId, userId: userId) }
    }

    private func fetchTokenAndActivate(callId: String) async {
        guard let userId = currentUserId else { return }
        do {
            let session = try await repository.liveKitToken(callId: callId, userId: userId)
            guard let url = session.livekitUrl, let token = session.livekitToken else {
                throw ApiException(code: -1, apiMessage: "缺少 LiveKit 连接信息")
            }
            try await room.connect(url: url, token: token)
            try await room.localParticipant.setMicrophone(enabled: true)
            if session.mediaType == "VIDEO" {
                try await room.localParticipant.setCamera(enabled: true)
            }
            callKit.reportCallConnected(callId: callId)
            setState(.active(session))
        } catch {
            self.error = (error as? ApiException)?.apiMessage ?? "接入通话失败"
            endLocally(reason: .failed)
        }
    }

    /// 通话彻底结束的收尾——本地状态归零、断开 LiveKit 房间、清 CallKit 状态。三条路径
    /// （对方挂断/自己挂断/失败）都走这里，不分别写一遍。
    private func endLocally(reason: CallKitEndReasonBridge) {
        if let callId = state.callId {
            callKit.reportCallEnded(callId: callId, reason: reason.cxReason)
        }
        state = .idle
        Task { await room.disconnect() }
    }

    func clearError() {
        error = nil
    }
}

/// CXCallEndedReason 在没 import CallKit 的文件里用不了，这层小小的桥接枚举只是让
/// CallCoordinator 自己的方法签名不用直接依赖 CallKit 类型。
enum CallKitEndReasonBridge {
    case remoteEnded
    case failed

    var cxReason: CXCallEndedReason {
        switch self {
        case .remoteEnded: return .remoteEnded
        case .failed: return .failed
        }
    }
}

extension CallCoordinator: RoomDelegate {
    // 远端音视频 track 由 CallView 直接从 room.remoteParticipants 读取渲染，这里不用重复缓存一份。
}
