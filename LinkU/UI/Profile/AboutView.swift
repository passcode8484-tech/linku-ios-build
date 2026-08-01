import SwiftUI

/// 对应 android-native ui/profile/AboutScreen 的精简版——静态版本信息。安卓那边还有一套
/// AppUpdateApi 手动检查新 APK 的逻辑，iOS 上应用更新走 App Store 系统机制，不需要也不应该
/// 自己实现一套（App Store 审核也不允许 App 内引导安装 App Store 之外的更新包）。
struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Text("LinkU")
                        .font(.title2.bold())
                        .foregroundStyle(LinkuBrand.primary)
                    Text("版本 \(version) (\(build))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }

            Section {
                Link("隐私政策", destination: URL(string: "\(AppConfig.webLinkBase)/privacy")!)
                Link("用户协议", destination: URL(string: "\(AppConfig.webLinkBase)/terms")!)
            }
        }
        .navigationTitle("关于 LinkU")
        .navigationBarTitleDisplayMode(.inline)
    }
}
