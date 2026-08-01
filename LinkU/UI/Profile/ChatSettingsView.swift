import SwiftUI

/// 对应 android"设置 -> 通用"里跟聊天媒体相关的两个开关（那边归在 GeneralSettingsScreen 里，
/// iOS 这边没有搬那整个通用设置页——见 SettingsView 的说明——但这两个开关本身有实际数据流量/
/// 隐私影响，单独给一个小页面）。
struct ChatSettingsView: View {
    @AppStorage("linku.chat.autoDownloadWifiOnly") private var autoDownloadWifiOnly = false
    @AppStorage("linku.chat.autoSaveMedia") private var autoSaveMedia = false

    var body: some View {
        Form {
            Section {
                Toggle("仅在 Wi-Fi 下自动下载媒体", isOn: $autoDownloadWifiOnly)
            } footer: {
                Text("开启后，使用蜂窝网络时收到的图片不会自动下载，需要手动点击加载。")
            }

            Section {
                Toggle("自动保存媒体到相册", isOn: $autoSaveMedia)
            } footer: {
                Text("开启后，聊天中收发的图片会自动保存一份到系统相册。")
            }
        }
        .navigationTitle("聊天与媒体")
        .navigationBarTitleDisplayMode(.inline)
    }
}
