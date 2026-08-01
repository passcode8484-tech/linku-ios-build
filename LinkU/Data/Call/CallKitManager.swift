import AVFoundation
import CallKit
import Foundation

/// 包一层 CXProvider/CXCallController——把系统原生来电界面（锁屏、控制中心）接进来电流程。
/// CallKit 要求用 UUID 标识一通通话，服务端的 callId 是 String，所以这里维护一份
/// `callId <-> UUID` 的映射，对外仍然按 callId 操作，CallKit 相关的 UUID 转换封在内部。
///
/// 只做了接听/挂断这两个最基本的系统交互；保持通话、DTMF、多路通话这些没有做——LinkU 目前
/// 只支持单聊 1:1 通话，用不上。
@MainActor
final class CallKitManager: NSObject {
    var onAnswer: ((String) -> Void)?
    var onEnd: ((String) -> Void)?
    var onMuteChanged: ((String, Bool) -> Void)?

    private let provider: CXProvider
    private let callController = CXCallController()
    private var callIdToUUID: [String: UUID] = [:]
    private var uuidToCallId: [UUID: String] = [:]

    override init() {
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = true
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        self.provider = CXProvider(configuration: configuration)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    private func uuid(for callId: String) -> UUID {
        if let existing = callIdToUUID[callId] { return existing }
        let uuid = UUID()
        callIdToUUID[callId] = uuid
        uuidToCallId[uuid] = callId
        return uuid
    }

    /// 收到 CALL_RING 时调用——弹出系统来电界面，即使 App 在后台/锁屏也能看到。
    func reportIncomingCall(callId: String, callerName: String, hasVideo: Bool) {
        let uuid = uuid(for: callId)
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: callerName)
        update.hasVideo = hasVideo
        update.localizedCallerName = callerName
        provider.reportNewIncomingCall(with: uuid, update: update) { _ in
            // 系统偶尔会拒绝上报（比如 Do Not Disturb/家长控制策略），这里静默忽略——
            // 应用内的来电横幅/铃声（CallCoordinator 自己那套）仍然会正常工作，只是少了
            // 系统级来电界面这一层增强。
        }
    }

    /// 自己发起呼叫时调用，让系统知道"这台设备正在打一通电话"（影响静音开关/耳机路由等系统行为）。
    func reportOutgoingCallStarted(callId: String, calleeName: String) {
        let uuid = uuid(for: callId)
        let handle = CXHandle(type: .generic, value: calleeName)
        let startAction = CXStartCallAction(call: uuid, handle: handle)
        callController.request(CXTransaction(action: startAction)) { _ in }
    }

    func reportCallConnected(callId: String) {
        guard let uuid = callIdToUUID[callId] else { return }
        provider.reportOutgoingCall(with: uuid, connectedAt: nil)
    }

    /// 通话结束——不管是自己挂的、对方挂的、还是超时——统一走这里清掉 CallKit 侧的状态。
    func reportCallEnded(callId: String, reason: CXCallEndedReason = .remoteEnded) {
        guard let uuid = callIdToUUID[callId] else { return }
        provider.reportCall(with: uuid, endedAt: nil, reason: reason)
        callIdToUUID.removeValue(forKey: callId)
        uuidToCallId.removeValue(forKey: uuid)
    }

    /// 应用内自己触发的挂断（比如用户点了 App 内的挂断按钮，不是从系统来电界面操作的）——
    /// 走 CXCallController 请求而不是直接调 provider.reportCall，这样系统状态（比如通话中
    /// 状态栏绿条）能正确收起。
    func requestEndCall(callId: String) {
        guard let uuid = callIdToUUID[callId] else { return }
        let endAction = CXEndCallAction(call: uuid)
        callController.request(CXTransaction(action: endAction)) { _ in }
    }
}

extension CallKitManager: CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {
        callIdToUUID.removeAll()
        uuidToCallId.removeAll()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        guard let callId = uuidToCallId[action.callUUID] else {
            action.fail()
            return
        }
        onAnswer?(callId)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        guard let callId = uuidToCallId[action.callUUID] else {
            action.fail()
            return
        }
        onEnd?(callId)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        guard let callId = uuidToCallId[action.callUUID] else {
            action.fail()
            return
        }
        onMuteChanged?(callId, action.isMuted)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        // LiveKit 自己管理音频会话的激活/配置（内部用的是 WebRTC 的 AudioSession 管理），
        // 这里不用手动配置 AVAudioSession——避免两边争抢音频会话配置权导致听不到声音。
    }
}
