import Foundation

enum LoginMode: Equatable {
    case password
    case code
}

/// 对应 android-native ui/auth/LoginViewModel.kt 的 LoginUiState + LoginViewModel，
/// 用 @Published 属性代替 StateFlow<LoginUiState>。
@MainActor
final class LoginViewModel: ObservableObject {
    @Published var account: String = ""
    @Published var password: String = ""
    @Published var code: String = ""
    @Published var mode: LoginMode = .password
    @Published var sendingCode = false
    @Published var codeSentHint: String?
    @Published var submitting = false
    @Published var error: String?

    private let authRepository: AuthRepository

    var accountKind: AuthAccountKind { detectAccountKind(account) }

    var canSubmit: Bool {
        guard !account.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch mode {
        case .password: return !password.isEmpty
        case .code: return !code.isEmpty
        }
    }

    init(authRepository: AuthRepository, sessionStore: SessionStore) {
        self.authRepository = authRepository
        // 退出登录后账号还留着，方便直接重新输密码，不用重新打一遍账号。
        if let lastAccount = sessionStore.lastAccount {
            account = lastAccount
        }
    }

    func onModeChanged(_ newMode: LoginMode) {
        mode = newMode
        error = nil
        codeSentHint = nil
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
            _ = try await authRepository.sendCode(account: trimmed, kind: accountKind, scene: "LOGIN")
            codeSentHint = accountKind == .email
                ? "验证码已发送，请查收邮箱（10 分钟内有效）"
                : "验证码已发送，请查收短信（10 分钟内有效）"
        } catch let ex as ApiException {
            error = ex.apiMessage
        } catch {
            // 不带 catch let 的 catch 块会隐式绑一个叫 error 的本地 Error 常量，把这个类自己的
            // @Published var error 遮住了——这里必须显式 self.error，不然编译器会认为在给那个
            // 隐式的、不可变的 Error 常量赋值。
            self.error = "网络异常，请稍后重试"
        }
        sendingCode = false
    }

    func submit() async {
        guard canSubmit, !submitting else { return }
        submitting = true
        error = nil
        do {
            switch mode {
            case .password:
                _ = try await authRepository.loginByPassword(
                    account: account.trimmingCharacters(in: .whitespaces),
                    password: password
                )
            case .code:
                _ = try await authRepository.loginByCode(
                    account: account.trimmingCharacters(in: .whitespaces),
                    kind: accountKind,
                    code: code.trimmingCharacters(in: .whitespaces)
                )
            }
            // 登录成功后 sessionStore.token 会被 AuthRepository 写入，RootView 据此自动切到主界面，
            // 这里不需要再维护一个单独的 loggedIn 标志。
        } catch let ex as ApiException {
            error = ex.apiMessage
        } catch {
            self.error = "网络异常，请稍后重试"
        }
        submitting = false
    }
}
