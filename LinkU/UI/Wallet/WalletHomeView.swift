import SwiftUI

/// 对应 android-native ui/wallet/WalletPage 的精简版：四链地址+余额列表、收款、节点管理、
/// 查看助记词、移除钱包。**没有转账/swap 入口**——这次范围里没做（见 WalletRepository.swift
/// 顶部注释），UI 上也不留一个点了没反应的假按钮。
struct WalletHomeView: View {
    let container: AppContainer

    @State private var accounts: [WalletAccountSnapshot] = []
    @State private var receiveTarget: WalletAccountSnapshot?
    @State private var showNetworkManage = false
    @State private var showRemoveConfirm = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                ForEach(accounts) { account in
                    Button {
                        receiveTarget = account
                    } label: {
                        row(for: account)
                    }
                    .foregroundStyle(.primary)
                }
            } footer: {
                Text("非托管钱包，助记词只保存在本机，LinkU 服务器不持有你的私钥。")
            }

            Section {
                NavigationLink("查看助记词") {
                    RevealMnemonicView(container: container)
                }
                Button { showNetworkManage = true } label: {
                    Text("节点管理")
                }
            }

            Section {
                Button("移除钱包（本机）", role: .destructive) { showRemoveConfirm = true }
            }
        }
        .navigationTitle("钱包")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await refreshBalances() }
        .sheet(item: $receiveTarget) { account in
            NavigationStack { WalletReceiveView(account: account) }
        }
        .sheet(isPresented: $showNetworkManage) {
            NavigationStack { NetworkManageView(container: container) }
        }
        .confirmationDialog("移除钱包后本机将不再保存助记词，未备份将无法找回", isPresented: $showRemoveConfirm, titleVisibility: .visible) {
            Button("确认移除", role: .destructive) { removeWallet() }
            Button("取消", role: .cancel) {}
        }
        .alert("加载失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func row(for account: WalletAccountSnapshot) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(account.chain.displayName).font(.body)
                Text(account.address).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if account.loadingBalance {
                ProgressView()
            } else {
                Text(account.balanceText ?? "--").font(.callout)
            }
        }
    }

    private func load() async {
        do {
            let addresses = try container.walletRepository.deriveAddresses()
            accounts = ChainId.allCases.compactMap { chain in
                guard let address = addresses[chain] else { return nil }
                return WalletAccountSnapshot(chain: chain, address: address, loadingBalance: true)
            }
            await refreshBalances()
        } catch let ex as ApiException {
            errorMessage = ex.apiMessage
        } catch {
            errorMessage = "加载失败"
        }
    }

    private func refreshBalances() async {
        await withTaskGroup(of: (Int, String).self) { group in
            for (index, account) in accounts.enumerated() {
                group.addTask {
                    let text = await container.walletRepository.fetchBalanceText(chain: account.chain, address: account.address)
                    return (index, text)
                }
            }
            for await (index, text) in group where index < accounts.count {
                accounts[index].balanceText = text
                accounts[index].loadingBalance = false
            }
        }
    }

    private func removeWallet() {
        try? container.walletRepository.removeWallet()
        accounts = []
    }
}
