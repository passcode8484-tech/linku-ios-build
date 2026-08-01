import Foundation

/// 跟 android-native data/push/PushNavTarget.kt 对应：通知点击后要跳去哪。
enum PushNavTarget: Equatable {
    case chat(conversationId: Int64)
    case friendRequests
    case groupJoinRequests
    case incomingCall(callId: String)

    static func fromData(_ data: [String: String]) -> PushNavTarget? {
        switch data["route"] {
        case "chat":
            guard let raw = data["conversationId"], let id = Int64(raw) else { return nil }
            return .chat(conversationId: id)
        case "friend_request":
            return .friendRequests
        case "group_join_request":
            return .groupJoinRequests
        case "call":
            guard let callId = data["callId"], !callId.isEmpty else { return nil }
            return .incomingCall(callId: callId)
        default:
            return nil
        }
    }
}

/// 通知点击后要跳去哪：AppDelegate 收到通知响应时把目标塞进来，RootView/MainShellView 观察
/// 并消费掉——跟 android-native PushNavHub 是同一个思路，原生这边没有基于统一 NavController
/// 的会话路由，只能用一个进程内单例中转。
@MainActor
final class PushNavHub: ObservableObject {
    static let shared = PushNavHub()

    @Published private(set) var pending: PushNavTarget?

    private init() {}

    func push(_ target: PushNavTarget) {
        pending = target
    }

    func consume() {
        pending = nil
    }
}
