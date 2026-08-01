import SwiftUI

/// 对应 android-native ui/profile/ChangePasswordScreen。账号如果本来就没设过密码（纯验证码登录），
/// oldPassword 传空——服务端自己判断是不是首次设置密码，这里不在客户端猜测。
struct ChangePasswordView: View {
    let container: AppContainer

    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var submitting = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("原密码（未设置过密码可留空）") {
                SecureField("原密码", text: $oldPassword)
            }
            Section("新密码") {
                SecureField("新密码（至少 8 位）", text: $newPassword)
                SecureField("再次输入新密码", text: $confirmPassword)
            }
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(LinkuBrand.danger)
                }
            }
            Section {
                Button {
                    Task { await submit() }
                } label: {
                    if submitting { ProgressView() } else { Text("确认修改") }
                }
                .disabled(submitting || newPassword.count < 8 || newPassword != confirmPassword)
            }
        }
        .navigationTitle("修改密码")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() async {
        errorMessage = nil
        submitting = true
        do {
            try await container.userProfileRepository.changePassword(
                oldPassword: oldPassword.isEmpty ? nil : oldPassword, newPassword: newPassword
            )
            dismiss()
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "修改失败"
        }
        submitting = false
    }
}

/// "账号安全"入口页——目前只有修改密码这一项，跟 android 保持一致（手机号/邮箱换绑放在编辑资料页）。
struct AccountSecurityView: View {
    let container: AppContainer

    var body: some View {
        List {
            NavigationLink {
                ChangePasswordView(container: container)
            } label: {
                Label("修改密码", systemImage: "lock")
            }
        }
        .navigationTitle("账号安全")
        .navigationBarTitleDisplayMode(.inline)
    }
}
