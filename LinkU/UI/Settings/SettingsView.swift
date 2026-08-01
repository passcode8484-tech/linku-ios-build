import SwiftUI

/// M10 顶层设置页——直接把 android "我" Tab 下面几层导航（ProfileScreen -> PrivacySettingsScreen
/// -> AccountSecuritySettingsScreen/PrivacyDetailScreen/E2eeSecurityScreen）拍平成一层，
/// 少一层纯导航中转页，跟 MainShellView 的 ProfileTab 已经分出"钱包"单独一行是同一个思路。
/// 通用设置里的字号/语言/代理这几项这次没做——iOS 系统本身有字号（动态字体）/语言跟随系统设置，
/// 代理这类设置在 iOS 消费级 App 里也不是常规做法，都不是"能不能正常用 LinkU"的必要项。
struct SettingsView: View {
    let container: AppContainer

    var body: some View {
        List {
            Section {
                NavigationLink {
                    EditProfileView(container: container)
                } label: {
                    Label("编辑资料", systemImage: "person.crop.circle")
                }
                NavigationLink {
                    ProfileQrView(container: container)
                } label: {
                    Label("我的二维码", systemImage: "qrcode")
                }
            }

            Section {
                NavigationLink {
                    AccountSecurityView(container: container)
                } label: {
                    Label("账号安全", systemImage: "lock.shield")
                }
                NavigationLink {
                    PrivacyView(container: container)
                } label: {
                    Label("隐私", systemImage: "hand.raised")
                }
                NavigationLink {
                    E2eeSecurityView(container: container)
                } label: {
                    Label("加密安全", systemImage: "checkmark.shield")
                }
            }

            Section {
                NavigationLink {
                    NotificationSettingsView()
                } label: {
                    Label("通知", systemImage: "bell")
                }
                NavigationLink {
                    ChatSettingsView()
                } label: {
                    Label("聊天与媒体", systemImage: "photo.on.rectangle")
                }
                NavigationLink {
                    FavoritesView(container: container)
                } label: {
                    Label("我的收藏", systemImage: "star")
                }
            }

            Section {
                NavigationLink {
                    AboutView()
                } label: {
                    Label("关于 LinkU", systemImage: "info.circle")
                }
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}
