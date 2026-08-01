import Foundation
import SwiftData

/// 手动依赖容器，对应 android-native 的 Hilt 单例图——Swift/SwiftUI 没有官方等价物，
/// 用一个简单的容器代替，从 LinkUApp 顶层创建一次，通过 environmentObject 往下传。
/// 后续里程碑（ChatRepository/GroupRepository...）都往这里加一个 let 属性。
@MainActor
final class AppContainer: ObservableObject {
    /// AppDelegate（Firebase/APNs 回调）不在 SwiftUI 视图树里，拿不到 environmentObject——
    /// 靠这个静态引用够到 pushTokenManager 等服务。LinkUApp 里创建 AppContainer 时赋值一次。
    static private(set) var shared: AppContainer?

    let sessionStore: SessionStore
    let apiClient: ApiClient
    let chatSocketClient: ChatSocketClient
    let authRepository: AuthRepository

    let modelContainer: ModelContainer
    let friendRepository: FriendRepository

    let e2eeSessionManager: E2eeSessionManager
    let chatRepository: ChatRepository

    let pushRepository: PushRepository
    let pushTokenManager: PushTokenManager

    let callCoordinator: CallCoordinator

    let momentRepository: MomentRepository
    let circleRepository: CircleRepository

    let walletRepository: WalletRepository

    let userProfileRepository: UserProfileRepository

    let networkMonitor: NetworkMonitor

    init() {
        let sessionStore = SessionStore()
        let apiClient = ApiClient(tokenProvider: sessionStore)
        let chatSocketClient = ChatSocketClient()

        self.sessionStore = sessionStore
        self.apiClient = apiClient
        self.chatSocketClient = chatSocketClient
        self.authRepository = AuthRepository(
            api: AuthApi(client: apiClient),
            sessionStore: sessionStore,
            chatSocketClient: chatSocketClient
        )

        // 跟 android-native Room AppDatabase 对应的本地缓存；schema 会随后续里程碑
        // （聊天记录、会话、群组、钱包……）不断加 @Model 类型进来。
        let schema = Schema([
            FriendEntity.self, FriendRequestEntity.self,
            ConversationEntity.self, MessageEntity.self,
        ])
        guard let modelContainer = try? ModelContainer(for: schema) else {
            fatalError("无法初始化本地数据库")
        }
        self.modelContainer = modelContainer

        // 用 mainContext 而不是自己再 new 一个 ModelContext——SwiftUI 的 `.modelContainer()`
        // 环境修饰符和 @Query 用的也是同一个 mainContext，这样仓库这边 insert/delete 之后
        // 视图能立刻感知到，不需要额外的跨 context 同步。
        self.friendRepository = FriendRepository(
            api: FriendApi(client: apiClient),
            modelContext: modelContainer.mainContext,
            sessionStore: sessionStore
        )

        let e2eeSessionManager = E2eeSessionManager(
            api: E2eeApi(client: apiClient),
            keyStore: E2eeKeyStore(),
            sessionStore: sessionStore
        )
        self.e2eeSessionManager = e2eeSessionManager

        self.chatRepository = ChatRepository(
            api: ChatApi(client: apiClient),
            socket: chatSocketClient,
            modelContext: modelContainer.mainContext,
            sessionStore: sessionStore,
            e2ee: e2eeSessionManager,
            publicMediaApi: PublicMediaApi(client: apiClient)
        )

        let pushRepository = PushRepository(api: PushApi(client: apiClient))
        self.pushRepository = pushRepository
        self.pushTokenManager = PushTokenManager(sessionStore: sessionStore, pushRepository: pushRepository)

        self.callCoordinator = CallCoordinator(
            socket: chatSocketClient,
            repository: CallRepository(api: CallApi(client: apiClient)),
            sessionStore: sessionStore,
            callKit: CallKitManager()
        )

        self.momentRepository = MomentRepository(
            api: MomentApi(client: apiClient),
            publicMediaApi: PublicMediaApi(client: apiClient),
            sessionStore: sessionStore
        )
        self.circleRepository = CircleRepository(api: CircleApi(client: apiClient), sessionStore: sessionStore)

        self.walletRepository = WalletRepository(sessionStore: sessionStore)

        self.userProfileRepository = UserProfileRepository(api: UserProfileApi(client: apiClient), sessionStore: sessionStore)

        self.networkMonitor = NetworkMonitor()

        Self.shared = self
    }
}
