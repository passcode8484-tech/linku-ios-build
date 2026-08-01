import SwiftUI

/// 对应 android-native ui/profile/E2eeSecurityScreen——显示本机身份公钥指纹，供用户线下核对
/// "这就是我自己的设备"；换身份是不可逆操作（旧会话全部作废，对方要重新走一遍密钥交换才能继续
/// 聊天），所以重置前用系统确认弹窗拦一道。
struct E2eeSecurityView: View {
    let container: AppContainer

    @State private var fingerprint: String?
    @State private var loading = true
    @State private var resetting = false
    @State private var showResetConfirm = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                if loading {
                    ProgressView()
                } else {
                    Text(fingerprint ?? "获取失败")
                        .font(.system(.body, design: .monospaced))
                }
            } header: {
                Text("本机身份指纹")
            } footer: {
                Text("跟对方在其他可信渠道核对这串数字，能确认聊天没有被第三方冒充或窃听。")
            }

            Section {
                Button("重置本机加密身份", role: .destructive) {
                    showResetConfirm = true
                }
                .disabled(resetting)
            } footer: {
                Text("重置后所有会话需要重新建立，好友需要重新验证你的身份。一般只在怀疑身份泄露时使用。")
            }

            if let message {
                Section {
                    Text(message).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("加密安全")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .confirmationDialog("确定要重置加密身份吗？", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("确认重置", role: .destructive) { Task { await reset() } }
            Button("取消", role: .cancel) {}
        }
    }

    private func load() async {
        loading = true
        fingerprint = await container.e2eeSessionManager.getLocalIdentityFingerprint()
        loading = false
    }

    private func reset() async {
        resetting = true
        message = nil
        do {
            try await container.e2eeSessionManager.resetLocalIdentity()
            fingerprint = await container.e2eeSessionManager.getLocalIdentityFingerprint()
            message = "已重置"
        } catch {
            message = "重置失败"
        }
        resetting = false
    }
}
