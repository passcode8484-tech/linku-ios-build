import Network

/// 对应 android ChatThreadViewModel.isOnWifi()（用 ConnectivityManager 查当前网络能力）——
/// 常驻一个 NWPathMonitor 单例挂在 AppContainer 上，比每次要判断的时候现建一个监听器、等第一次
/// 回调再销毁更省事：图片消息一多，短时间内会连续问好几次"现在是不是 Wi-Fi"。
@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var isOnWifi = true

    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnWifi = path.usesInterfaceType(.wifi)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.linku.ios.networkmonitor"))
    }
}
