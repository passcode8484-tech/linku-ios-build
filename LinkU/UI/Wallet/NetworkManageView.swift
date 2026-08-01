import SwiftUI

/// 对应 android-native ui/wallet/NetworkManageScreen 的精简版：四条链分别选预设 RPC 节点，
/// 或者填一个自定义节点覆盖。不支持新增/删除整条自定义链（android 那边的 RpcManageScreen 更完整，
/// 这次范围里只做"换节点"，不做"管理链列表"）。
struct NetworkManageView: View {
    let container: AppContainer

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(ChainId.allCases) { chain in
                Section(chain.displayName) {
                    ChainEndpointRow(container: container, chain: chain)
                }
            }
        }
        .navigationTitle("节点管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("关闭") { dismiss() }
            }
        }
    }
}

private struct ChainEndpointRow: View {
    let container: AppContainer
    let chain: ChainId

    @State private var current: String = ""
    @State private var customInput: String = ""
    @State private var showCustomField = false

    var body: some View {
        Group {
            ForEach(chain.presetRpcEndpoints, id: \.self) { endpoint in
                Button {
                    container.walletRepository.setCustomEndpoint(nil, for: chain)
                    current = chain.presetRpcEndpoints[0]
                    if endpoint != chain.presetRpcEndpoints[0] {
                        container.walletRepository.setCustomEndpoint(endpoint, for: chain)
                        current = endpoint
                    }
                } label: {
                    HStack {
                        Text(endpoint).font(.footnote).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        if current == endpoint {
                            Image(systemName: "checkmark").foregroundStyle(LinkuBrand.primary)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }

            if showCustomField {
                HStack {
                    TextField("自定义节点 URL", text: $customInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.footnote)
                    Button("应用") {
                        let trimmed = customInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        container.walletRepository.setCustomEndpoint(trimmed, for: chain)
                        current = trimmed
                    }
                    .disabled(customInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                Button("自定义节点…") { showCustomField = true }
            }
        }
        .onAppear { current = container.walletRepository.currentEndpoint(for: chain) }
    }
}
