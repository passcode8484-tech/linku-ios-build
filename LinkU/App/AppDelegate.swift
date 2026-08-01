import FirebaseCore
import FirebaseMessaging
import UIKit
import UserNotifications

/// SwiftUI 的 App 协议本身没有推送注册/接收这套钩子——Firebase SDK 和 APNs 都是按传统
/// UIApplicationDelegate 生命周期设计的，用 `@UIApplicationDelegateAdaptor` 接进来。
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // FCM 内部靠这个 APNs token 把自己签发的 FCM token 跟真机关联起来，
        // 服务端只需要认 FCM token，不用直接碰 APNs。
        Messaging.messaging().apnsToken = deviceToken
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { @MainActor in
            await AppContainer.shared?.pushTokenManager.onNewToken(fcmToken)
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// App 在前台时收到推送默认不会弹出来，要显式声明才行——顺带尊重 M10 通知设置页的
    /// 声音/预览开关（这两个只在前台生效，见 NotificationSettingsView 里的说明）。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let defaults = UserDefaults.standard
        let soundEnabled = defaults.object(forKey: "linku.notification.sound") as? Bool ?? true
        let previewEnabled = defaults.object(forKey: "linku.notification.preview") as? Bool ?? true

        var options: UNNotificationPresentationOptions = previewEnabled ? [.banner, .list] : [.badge]
        if soundEnabled { options.insert(.sound) }
        completionHandler(options)
    }

    /// 用户点了通知——解析 data 字段，塞进 PushNavHub 让 UI 层消费并跳转。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let data = userInfo.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String {
                result[key] = value
            }
        }
        if let target = PushNavTarget.fromData(data) {
            Task { @MainActor in PushNavHub.shared.push(target) }
        }
        completionHandler()
    }
}
