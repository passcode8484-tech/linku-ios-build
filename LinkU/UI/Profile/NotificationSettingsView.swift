import SwiftUI

/// 对应 android-native ui/profile/NotificationSettingsScreen——声音/振动/预览三个开关，纯本机
/// UserDefaults 偏好，不经过服务端（跟安卓一样：这几个只影响本机怎么展示通知，不是服务端推送
/// 策略）。真正的系统通知权限（是否允许弹通知）iOS 不允许 App 内直接改，引到系统设置页。
struct NotificationSettingsView: View {
    @AppStorage("linku.notification.sound") private var soundEnabled = true
    @AppStorage("linku.notification.vibration") private var vibrationEnabled = true
    @AppStorage("linku.notification.preview") private var previewEnabled = true

    var body: some View {
        Form {
            Section {
                Toggle("声音", isOn: $soundEnabled)
                Toggle("振动", isOn: $vibrationEnabled)
                Toggle("显示消息预览", isOn: $previewEnabled)
            } footer: {
                // 「显示消息预览」目前只影响 App 在前台时收到推送要不要显示内容——iOS 后台通知的
                // 展示内容由系统直接渲染 APNs payload，客户端要改这部分得接一个 Notification Service
                // Extension（这次没做，留到真需要"后台通知也隐藏预览"时再补）。
                Text("关闭后，App 在前台收到新消息时不弹出内容预览。")
            }

            Section {
                Button("前往系统通知设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } footer: {
                Text("是否允许 LinkU 弹出通知，由系统「设置」App 里的通知权限控制。")
            }
        }
        .navigationTitle("通知")
        .navigationBarTitleDisplayMode(.inline)
    }
}
