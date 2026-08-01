import SwiftUI

/// 对应 android-native ui/profile/ChangeContactScreen——换绑手机号/邮箱，一个页面走完
/// "填新号码 -> 发验证码 -> 填验证码 -> 提交"，不要求验证原手机号/密码（登录态本身就是信任边界）。
struct ChangeContactView: View {
    let container: AppContainer
    let kind: AuthAccountKind

    @State private var newValue = ""
    @State private var code = ""
    @State private var sendingCode = false
    @State private var codeSent = false
    @State private var cooldown = 0
    @State private var submitting = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private var label: String { kind == .phone ? "手机号" : "邮箱" }

    var body: some View {
        Form {
            Section {
                TextField(kind == .phone ? "新手机号" : "新邮箱", text: $newValue)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(kind == .phone ? .phonePad : .emailAddress)
            } header: {
                Text("新\(label)")
            }

            Section {
                HStack {
                    TextField("验证码", text: $code)
                        .keyboardType(.numberPad)
                    Button {
                        Task { await sendCode() }
                    } label: {
                        if sendingCode {
                            ProgressView()
                        } else if cooldown > 0 {
                            Text("\(cooldown)s")
                        } else {
                            Text(codeSent ? "重新发送" : "发送验证码")
                        }
                    }
                    .disabled(sendingCode || cooldown > 0 || newValue.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section {
                Button {
                    Task { await submit() }
                } label: {
                    if submitting {
                        ProgressView()
                    } else {
                        Text("确认更换")
                    }
                }
                .disabled(submitting || newValue.trimmingCharacters(in: .whitespaces).isEmpty || code.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle("更换\(label)")
        .navigationBarTitleDisplayMode(.inline)
        .alert("出错了", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func sendCode() async {
        sendingCode = true
        do {
            let scene = kind == .phone ? "CHANGE_PHONE" : "CHANGE_EMAIL"
            _ = try await container.authRepository.sendCode(account: newValue.trimmingCharacters(in: .whitespaces), kind: kind, scene: scene)
            codeSent = true
            startCooldown()
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "发送失败"
        }
        sendingCode = false
    }

    private func startCooldown() {
        cooldown = 60
        Task {
            while cooldown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                cooldown -= 1
            }
        }
    }

    private func submit() async {
        submitting = true
        do {
            let value = newValue.trimmingCharacters(in: .whitespaces)
            if kind == .phone {
                try await container.userProfileRepository.changePhone(phone: value, code: code)
            } else {
                try await container.userProfileRepository.changeEmail(email: value, code: code)
            }
            dismiss()
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "更新失败"
        }
        submitting = false
    }
}
