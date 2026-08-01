import SwiftUI

/// 对应 android-native ui/wallet/SecretRevealScreen——查看助记词前先过一道生物识别/密码验证。
struct RevealMnemonicView: View {
    let container: AppContainer

    @State private var unlocked = false
    @State private var mnemonic: String?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let mnemonic {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("任何人拿到这些单词都能拿走你的资产，不要截图、不要发给任何人（包括自称「客服」的人）。")
                            .font(.footnote)
                            .foregroundStyle(LinkuBrand.danger)
                        Text(mnemonic)
                            .font(.body.monospaced())
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .padding()
                }
            } else if let errorMessage {
                ContentUnavailableView(errorMessage, systemImage: "lock")
            } else {
                ProgressView("验证身份中…")
            }
        }
        .navigationTitle("助记词")
        .navigationBarTitleDisplayMode(.inline)
        .task { await unlock() }
    }

    private func unlock() async {
        let ok = await WalletUnlockGate.authenticate(reason: "查看钱包助记词")
        guard ok else {
            errorMessage = "身份验证失败或未设置设备密码"
            return
        }
        do {
            mnemonic = try container.walletRepository.revealMnemonic()
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "读取失败"
        }
    }
}
