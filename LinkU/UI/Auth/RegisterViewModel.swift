import Foundation

/// 对应 android-native ui/auth/RegisterViewModel.kt。
@MainActor
final class RegisterViewModel: ObservableObject {
    @Published var account: String = ""
    @Published var code: String = ""
    @Published var password: String = ""
    @Published var nickname: String = ""
    @Published var sendingCode = false
    @Published var codeSentHint: String?
    @Published var submitting = false
    @Published var error: String?

    private let authRepository: AuthRepository

    var accountKind: AuthAccountKind { detectAccountKind(account) }

    var canSubmit: Bool {
        !account.trimmingCharacters(in: .whitespaces).isEmpty
            && !code.trimmingCharacters(in: .whitespaces).isEmpty
            && password.count >= 6
    }

    init(authRepository: AuthRepository) {
        self.authRepository = authRepository
    }

    func sendCode() async {
        let trimmed = account.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            error = "请先输入邮箱或手机号"
            return
        }
        sendingCode = true
        error = nil
        do {
            _ = try await authRepository.sendCode(account: trimmed, kind: accountKind, scene: "REGISTER")
            codeSentHint = accountKind == .email ? "验证码已发送，请查收邮箱" : "验证码已发送，请查收短信"
        } catch let ex as ApiException {
            error = ex.apiMessage
        } catch {
            error = "网络异常，请稍后重试"
        }
        sendingCode = false
    }

    func submit() async {
        guard canSubmit, !submitting else { return }
        submitting = true
        error = nil
        do {
            _ = try await authRepository.register(
                account: account.trimmingCharacters(in: .whitespaces),
                kind: accountKind,
                code: code.trimmingCharacters(in: .whitespaces),
                password: password,
                nickname: nickname.isEmpty ? nil : nickname
            )
            // 注册成功后 sessionStore.token 会被写入，RootView 据此自动切到主界面。
        } catch let ex as ApiException {
            error = ex.apiMessage
        } catch {
            error = "网络异常，请稍后重试"
        }
        submitting = false
    }
}
