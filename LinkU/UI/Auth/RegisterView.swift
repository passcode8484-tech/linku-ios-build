import SwiftUI

/// 对应 android-native ui/auth/RegisterScreen.kt。
struct RegisterView: View {
    @Environment(\.linkuColors) private var colors
    @StateObject private var viewModel: RegisterViewModel

    init(container: AppContainer) {
        _viewModel = StateObject(wrappedValue: RegisterViewModel(authRepository: container.authRepository))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                TextField("邮箱或手机号", text: $viewModel.account)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                HStack {
                    TextField("验证码", text: $viewModel.code)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                    Button(viewModel.sendingCode ? "发送中…" : "获取验证码") {
                        Task { await viewModel.sendCode() }
                    }
                    .disabled(viewModel.sendingCode)
                }

                SecureField("密码（至少 6 位）", text: $viewModel.password)
                    .textFieldStyle(.roundedBorder)

                TextField("昵称（可选）", text: $viewModel.nickname)
                    .textFieldStyle(.roundedBorder)

                if let hint = viewModel.codeSentHint {
                    Text(hint).font(.footnote).foregroundStyle(colors.secondaryText)
                }
                if let error = viewModel.error {
                    Text(error).font(.footnote).foregroundStyle(LinkuBrand.danger)
                }

                Button {
                    Task { await viewModel.submit() }
                } label: {
                    if viewModel.submitting {
                        ProgressView().tint(.white)
                    } else {
                        Text("注册").bold()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(viewModel.canSubmit ? LinkuBrand.primary : LinkuBrand.primary.opacity(0.4))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .disabled(!viewModel.canSubmit || viewModel.submitting)
            }
            .padding()
        }
        .background(colors.background)
        .navigationTitle("注册")
    }
}

#Preview {
    NavigationStack { RegisterView(container: AppContainer()) }
}
