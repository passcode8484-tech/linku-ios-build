import Foundation

/// 服务端事件帧：{event, conversationId?, data}，对应服务端 ChatWebSocketHandler.encodeEvent。
struct ChatSocketFrame {
    let event: String
    let conversationId: Int64?
    let data: [String: Any]?
}

/// 单用户单连接，一条连接收全部会话的消息——对应 android-native data/remote/ws/ChatSocketClient.kt。
/// 用 URLSessionWebSocketTask 实现（对应 OkHttp WebSocket），20s 心跳 + 指数退避自动重连。
/// 所有可变状态都只在 `queue` 这个私有串行队列上touch，delegate 回调/receive 回调可能来自任意线程。
final class ChatSocketClient: NSObject {
    private let queue = DispatchQueue(label: "com.linku.ios.chatsocket")
    private var task: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var connectedToken: String?
    private var reconnectAttempt = 0
    private var reconnectWorkItem: DispatchWorkItem?
    private var pingWorkItem: DispatchWorkItem?
    private var pendingAcks: [String: (Result<ChatSocketFrame, Error>) -> Void] = [:]
    private var eventHandlers: [UUID: (ChatSocketFrame) -> Void] = [:]

    var isConnected: Bool { queue.sync { task != nil } }

    /// 订阅所有推送事件（新消息/已读回执/输入状态/来电信令……）——ChatRepository/CallCoordinator
    /// 这类"整个 App 生命周期只订阅一次"的单例调用方可以不管返回的 token；但像 ChatThreadView
    /// 这种"每次进这个页面就订阅一次"的场景，必须在页面消失时调用 removeEventHandler(token)，
    /// 不然旧闭包（连带它捕获的 @State）永远留在这个数组里，越攒越多。回调固定在主线程触发，
    /// 方便直接更新 UI/SwiftData。
    @discardableResult
    func onEvent(_ handler: @escaping (ChatSocketFrame) -> Void) -> UUID {
        let token = UUID()
        queue.async { self.eventHandlers[token] = handler }
        return token
    }

    func removeEventHandler(_ token: UUID) {
        queue.async { self.eventHandlers.removeValue(forKey: token) }
    }

    func connect(token: String) {
        queue.async {
            if self.connectedToken == token, self.task != nil { return }
            self.reconnectWorkItem?.cancel()
            self.reconnectAttempt = 0
            self.task?.cancel(with: .goingAway, reason: nil)
            self.task = nil
            self.connectedToken = token
            self.openSocket(token: token)
        }
    }

    func disconnect() {
        queue.async {
            self.reconnectWorkItem?.cancel()
            self.pingWorkItem?.cancel()
            self.connectedToken = nil
            self.task?.cancel(with: .goingAway, reason: nil)
            self.task = nil
        }
    }

    // MARK: - 连接建立/心跳/重连

    private func openSocket(token: String) {
        guard let url = URL(string: "\(AppConfig.wsURL)?token=\(token)") else { return }
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let socketTask = session.webSocketTask(with: url)
        urlSession = session
        task = socketTask
        socketTask.resume()
        receiveLoop(on: socketTask)
        schedulePing(on: socketTask)
    }

    private func receiveLoop(on socketTask: URLSessionWebSocketTask) {
        socketTask.receive { [weak self] result in
            guard let self else { return }
            self.queue.async {
                switch result {
                case .failure:
                    guard self.task === socketTask else { return }
                    self.task = nil
                    self.scheduleReconnect()
                case .success(let message):
                    if case .string(let text) = message, let frame = Self.parseFrame(text) {
                        self.handleFrame(frame)
                    }
                    guard self.task === socketTask else { return }
                    self.receiveLoop(on: socketTask)
                }
            }
        }
    }

    /// 20s 心跳 ping——跟 android-native OkHttpClient.pingInterval(20s) 同样的用意：连接死掉后
    /// 几十秒内就能通过 ping 失败触发重连，而不是等到下次主动发消息才发现"其实早断了"。
    private func schedulePing(on socketTask: URLSessionWebSocketTask) {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            socketTask.sendPing { error in
                self.queue.async {
                    guard self.task === socketTask else { return }
                    if error != nil {
                        self.task = nil
                        self.scheduleReconnect()
                    } else {
                        self.schedulePing(on: socketTask)
                    }
                }
            }
        }
        pingWorkItem = work
        queue.asyncAfter(deadline: .now() + 20, execute: work)
    }

    /// 指数退避（2s→4s→8s→16s→封顶 30s），成功连上（didOpen）后计数清零。
    private func scheduleReconnect() {
        guard let token = connectedToken else { return }
        reconnectWorkItem?.cancel()
        let delaySeconds = min(2 << min(reconnectAttempt, 4), 30)
        reconnectAttempt += 1
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.connectedToken == token, self.task == nil else { return }
            self.openSocket(token: token)
        }
        reconnectWorkItem = work
        queue.asyncAfter(deadline: .now() + .seconds(delaySeconds), execute: work)
    }

    // MARK: - 请求-应答

    /// 服务端支持的通用请求-应答口：发一个 {action,clientMsgId,data} 帧，按 clientMsgId 匹配
    /// 对应的 ACK 帧当作这次调用的返回值。
    func sendAction(_ action: String, data requestData: [String: Any], timeout: TimeInterval = 8) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let task = self.task else {
                    continuation.resume(throwing: ApiException(code: -1, apiMessage: "WebSocket 未连接"))
                    return
                }
                let requestId = UUID().uuidString
                var settled = false
                self.pendingAcks[requestId] = { result in
                    guard !settled else { return }
                    settled = true
                    switch result {
                    case .success(let frame):
                        guard let data = frame.data else {
                            continuation.resume(throwing: ApiException(code: -1, apiMessage: "空响应"))
                            return
                        }
                        if frame.event == "ACTION_ERROR" {
                            let message = data["message"] as? String ?? "请求失败"
                            continuation.resume(throwing: ApiException(code: -1, apiMessage: message))
                        } else {
                            continuation.resume(returning: data)
                        }
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                let frameObj: [String: Any] = ["action": action, "clientMsgId": requestId, "data": requestData]
                guard let frameData = try? JSONSerialization.data(withJSONObject: frameObj),
                      let frameText = String(data: frameData, encoding: .utf8) else {
                    self.pendingAcks.removeValue(forKey: requestId)
                    continuation.resume(throwing: ApiException(code: -1, apiMessage: "请求序列化失败"))
                    return
                }
                task.send(.string(frameText)) { error in
                    guard let error else { return }
                    self.queue.async {
                        if let pending = self.pendingAcks.removeValue(forKey: requestId) {
                            pending(.failure(error))
                        }
                    }
                }
                self.queue.asyncAfter(deadline: .now() + timeout) {
                    if let pending = self.pendingAcks.removeValue(forKey: requestId) {
                        pending(.failure(ApiException(code: -1, apiMessage: "等待服务端响应超时")))
                    }
                }
            }
        }
    }

    /// 发消息走 WS：跟 HTTP 版 ChatApi.sendMessage 语义完全对应，服务端两条路径落到同一个实现，
    /// 返回的 message 结构一致，可以直接复用 MessageView 反序列化。
    func sendChatMessage(
        conversationId: Int64,
        senderUserId: Int64,
        type: String,
        content: String,
        replyMessageId: Int64? = nil
    ) async throws -> MessageView {
        var data: [String: Any] = [
            "conversationId": conversationId,
            "senderUserId": senderUserId,
            "type": type,
            "content": content,
        ]
        if let replyMessageId { data["replyMessageId"] = replyMessageId }
        let result = try await sendAction("SEND_MESSAGE", data: data)
        guard let messageJson = result["message"] else {
            throw ApiException(code: -1, apiMessage: "响应缺少 message 字段")
        }
        let jsonData = try JSONSerialization.data(withJSONObject: messageJson)
        return try JSONDecoder().decode(MessageView.self, from: jsonData)
    }

    // MARK: - 帧处理

    private func handleFrame(_ frame: ChatSocketFrame) {
        if let requestId = frame.data?["clientMsgId"] as? String,
           let pending = pendingAcks.removeValue(forKey: requestId) {
            pending(.success(frame))
        }
        let handlers = eventHandlers.values
        DispatchQueue.main.async {
            handlers.forEach { $0(frame) }
        }
    }

    private static func parseFrame(_ text: String) -> ChatSocketFrame? {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = obj["event"] as? String
        else { return nil }
        let conversationId = (obj["conversationId"] as? NSNumber)?.int64Value
        let frameData = obj["data"] as? [String: Any]
        return ChatSocketFrame(event: event, conversationId: conversationId, data: frameData)
    }
}

extension ChatSocketClient: URLSessionWebSocketDelegate {
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        queue.async { self.reconnectAttempt = 0 }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        queue.async {
            guard self.task === webSocketTask else { return }
            self.task = nil
            self.scheduleReconnect()
        }
    }
}
