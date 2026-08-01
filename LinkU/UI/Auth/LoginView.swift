import SwiftUI

/// 对应 android-native ui/auth/LoginScreen.kt。
struct LoginView: View {
    @Environment(\.linkuColors) private var colors
    @StateObject private var viewModel: LoginViewModel
    @State private var showRegister = false
    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
        _viewModel = StateObject(
            wrappedValue: LoginViewModel(
                authRepository: container.authRepository,
                sessionStore: container.sessionStore
            )
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("LinkU")
                        .font(.largeTitle.bold())
                        .foregroundStyle(LinkuBrand.primary)
                        .padding(.top, 48)

                    Picker("登录方式", selection: Binding(
                        get: { viewModel.mode },
                        set: { viewModel.onModeChanged($0) }
                    )) {
                        Text("密码登录").tag(LoginMode.password)
                        Text("验证码登录").tag(LoginMode.code)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    VStack(spacing: 12) {
                        TextField("邮箱或手机号", text: $viewModel.account)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        if viewModel.mode == .password {
                            SecureField("密码", text: $viewModel.password)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            HStack {
                                TextField("验证码", text: $viewModel.code)
                                    .textFieldStyle(.roundedBorder)
                                    .keyboardType(.numberPad)
                                Button(viewModel.sendingCode ? "发送中…" : "获取验证码") {
                                    Task { await viewModel.sendCode() }
                                }
                                .disabled(viewModel.sendingCode)
                            }
                        }
                    }
                    .padding(.horizontal)

                    if let hint = viewModel.codeSentHint {
                        Text(hint)
                            .font(.footnote)
                            .foregroundStyle(colors.secondaryText)
                    }
                    if let error = viewModel.error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(LinkuBrand.danger)
                    }

                    Button {
                        Task { await viewModel.submit() }
                    } label: {
                        if viewModel.submitting {
                            ProgressView().tint(.white)
                        } else {
                            Text("登录").bold()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.canSubmit ? LinkuBrand.primary : LinkuBrand.primary.opacity(0.4))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .disabled(!viewModel.canSubmit || viewModel.submitting)
                    .padding(.horizontal)

                    Button("还没有账号？去注册") { showRegister = true }
                        .font(.footnote)
                        .padding(.bottom, 24)
                }
            }
            .background(colors.background)
            .navigationDestination(isPresented: $showRegister) {
                RegisterView(container: container)
            }
        }
    }
}

#Preview {
    LoginView(container: AppContainer())
}
