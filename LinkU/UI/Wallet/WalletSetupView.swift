import SwiftUI

/// 对应 android-native ui/wallet/WalletSetupScreen + MnemonicStepsScreen + ConfirmBackupScreen
/// 的精简合并版：创建新钱包(生成助记词 -> 用户确认已备份 -> 存盘) / 导入已有钱包(校验助记词 -> 存盘)。
struct WalletSetupView: View {
    let container: AppContainer
    var onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .choose

    private enum Mode {
        case choose
        case createBackup(mnemonic: String)
        case createConfirm(mnemonic: String)
        case importWallet
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("钱包")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("取消") { dismiss() }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .choose:
            chooseView
        case .createBackup(let mnemonic):
            BackupMnemonicView(mnemonic: mnemonic) {
                mode = .createConfirm(mnemonic: mnemonic)
            }
        case .createConfirm(let mnemonic):
            ConfirmBackupView(mnemonic: mnemonic) {
                save(mnemonic: mnemonic)
            }
        case .importWallet:
            ImportWalletView(container: container) {
                onFinished()
                dismiss()
            }
        }
    }

    private var chooseView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "wallet.pass")
                .font(.system(size: 56))
                .foregroundStyle(LinkuBrand.primary)
            Text("非托管多链钱包").font(.title3.bold())
            Text("助记词只保存在本机，LinkU 服务器不持有你的私钥")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button {
                guard let mnemonic = container.walletRepository.generateMnemonic() else { return }
                mode = .createBackup(mnemonic: mnemonic)
            } label: {
                Text("创建新钱包").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(LinkuBrand.primary)
            .padding(.horizontal)

            Button {
                mode = .importWallet
            } label: {
                Text("导入已有钱包").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
    }

    private func save(mnemonic: String) {
        do {
            try container.walletRepository.saveWallet(mnemonic: mnemonic)
            onFinished()
            dismiss()
        } catch {
            // 存盘失败极少见（Keychain 异常）——保持在确认页，用户可以重试。
        }
    }
}

private struct BackupMnemonicView: View {
    let mnemonic: String
    var onConfirmed: () -> Void

    private var words: [String] { mnemonic.split(separator: " ").map(String.init) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("请按顺序抄写下面这 \(words.count) 个单词，离线保存——截图/云同步都不安全。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                        HStack {
                            Text("\(index + 1).").foregroundStyle(.secondary)
                            Text(word).bold()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                Button("我已经安全抄写") { onConfirmed() }
                    .buttonStyle(.borderedProminent)
                    .tint(LinkuBrand.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
            .padding()
        }
    }
}

private struct ConfirmBackupView: View {
    let mnemonic: String
    var onConfirmed: () -> Void

    @State private var checkedIndices: Set<Int> = []
    @State private var quizWords: [(index: Int, word: String)] = []

    private var words: [String] { mnemonic.split(separator: " ").map(String.init) }

    var body: some View {
        VStack(spacing: 20) {
            Text("按顺序点选下面第 \(quizWords.map { $0.index + 1 }.sorted().map(String.init).joined(separator: "、")) 个单词，确认你已经抄对了。")
                .font(.subheadline)
                .padding(.horizontal)
                .multilineTextAlignment(.center)

            // 简化版核对：直接展示需要确认的几个词及其序号，勾选表示"我核对过了"，
            // 不是完整的乱序重排点选交互（那个交互态更复杂，先做最小可用版本）。
            VStack(spacing: 10) {
                ForEach(quizWords, id: \.index) { item in
                    Button {
                        if checkedIndices.contains(item.index) {
                            checkedIndices.remove(item.index)
                        } else {
                            checkedIndices.insert(item.index)
                        }
                    } label: {
                        HStack {
                            Text("第 \(item.index + 1) 个：\(item.word)")
                            Spacer()
                            Image(systemName: checkedIndices.contains(item.index) ? "checkmark.circle.fill" : "circle")
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal)

            Button("确认完成备份") { onConfirmed() }
                .buttonStyle(.borderedProminent)
                .tint(LinkuBrand.primary)
                .disabled(checkedIndices.count < quizWords.count)
                .padding(.horizontal)

            Spacer()
        }
        .padding(.top, 24)
        .onAppear {
            if quizWords.isEmpty {
                let sampleIndices = Array(words.indices.shuffled().prefix(3)).sorted()
                quizWords = sampleIndices.map { ($0, words[$0]) }
            }
        }
    }
}

private struct ImportWalletView: View {
    let container: AppContainer
    var onImported: () -> Void

    @State private var input = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("输入 12 或 24 个助记词，用空格分隔").font(.subheadline).foregroundStyle(.secondary)
            TextEditor(text: $input)
                .frame(height: 140)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(LinkuBrand.danger)
            }

            Button("导入") { importWallet() }
                .buttonStyle(.borderedProminent)
                .tint(LinkuBrand.primary)
                .frame(maxWidth: .infinity)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()
        }
        .padding()
    }

    private func importWallet() {
        let mnemonic = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard container.walletRepository.isValidMnemonic(mnemonic) else {
            errorMessage = "助记词不合法，请检查拼写和顺序"
            return
        }
        do {
            try container.walletRepository.saveWallet(mnemonic: mnemonic)
            onImported()
        } catch {
            errorMessage = "导入失败，请重试"
        }
    }
}
