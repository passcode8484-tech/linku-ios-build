import SwiftUI

/// 对应 android-native ui/nav/LinkUNavHost.kt 的顶层判断：未登录 -> LoginView，已登录 -> MainShellView。
/// 直接观察 SessionStore.token 而不是走某个 ViewModel 里的 loggedIn 标志——登录/注册/登出任何一处
/// 写入或清空 token，这里都会自动响应，不需要额外的导航状态同步。
struct RootView: View {
    private let container: AppContainer
    @ObservedObject private var sessionStore: SessionStore
    @ObservedObject private var callCoordinator: CallCoordinator
    @Environment(\.colorScheme) private var colorScheme
    @State private var isRestoring = true

    init(container: AppContainer) {
        self.container = container
        self.sessionStore = container.sessionStore
        self.callCoordinator = container.callCoordinator
    }

    var body: some View {
        Group {
            if isRestoring {
                splash
            } else if sessionStore.token != nil {
                MainShellView(container: container)
            } else {
                LoginView(container: container)
            }
        }
        .linkuColorScheme(colorScheme)
        .task {
            // 有本地 token 才需要向服务端校验是否还有效（顺带建立 WS 连接）；
            // 没有 token 直接进登录页，不用多等一次网络往返。
            if sessionStore.token != nil {
                await container.authRepository.restoreSession()
            }
            isRestoring = false
        }
        // 通话界面挂在最顶层——来电随时可能发生，跟当前在登录页/哪个 Tab 都无关，
        // CallCoordinator.state 一旦不是 .idle 就盖一层全屏通话界面上去。
        .fullScreenCover(isPresented: Binding(
            get: { callCoordinator.state != .idle },
            set: { if !$0 { callCoordinator.hangup() } }
        )) {
            CallView(coordinator: callCoordinator)
        }
    }

    private var splash: some View {
        VStack(spacing: 12) {
            Text("LinkU")
                .font(.largeTitle.bold())
                .foregroundStyle(LinkuBrand.primary)
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview {
    RootView(container: AppContainer())
}
