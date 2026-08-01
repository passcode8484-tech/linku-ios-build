import SwiftUI

/// 收款码——复用 M2 做的 QrCodeView，钱包地址本身就是要收款人扫的内容，不需要 linku:// 那套 scheme。
struct WalletReceiveView: View {
    let account: WalletAccountSnapshot

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(spacing: 20) {
            Text(account.chain.displayName).font(.headline)
            QrCodeView(content: account.address, size: 220)
            Text(account.address)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                UIPasteboard.general.string = account.address
                copied = true
            } label: {
                Label(copied ? "已复制" : "复制地址", systemImage: "doc.on.doc")
            }
            Text("只能接收 \(account.chain.displayName) 网络上的资产，转错网络可能导致资产无法找回。")
                .font(.caption)
                .foregroundStyle(LinkuBrand.danger)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding()
        .navigationTitle("收款")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("关闭") { dismiss() }
            }
        }
    }
}
