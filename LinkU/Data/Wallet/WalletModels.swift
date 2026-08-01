import Foundation

/// 跟 docs/WALLET.md 的 Phase 1 支持范围一一对应：四条链，地址+余额只读，不做转账/swap
/// （见 WalletRepository.swift 顶部注释说明为什么这次不做签名广播）。
enum ChainId: String, CaseIterable, Identifiable {
    case ethereum
    case bnbChain
    case tron
    case solana

    var id: String { rawValue }

    /// 服务端持币门槛接口认的链标识跟本地 rawValue 不是一回事——服务端沿用 android 的
    /// `NetworkConfig.id`（"ethereum"/"bsc"），不是 "bnbChain"。只有 tokenGate 相关请求需要这个，
    /// RPC 节点选择、UserDefaults key 等本地用途继续用 rawValue，不要混用。
    var gateChainId: String {
        switch self {
        case .bnbChain: return "bsc"
        default: return rawValue
        }
    }

    var displayName: String {
        switch self {
        case .ethereum: return "Ethereum"
        case .bnbChain: return "BNB Chain"
        case .tron: return "TRON"
        case .solana: return "Solana"
        }
    }

    var symbol: String {
        switch self {
        case .ethereum: return "ETH"
        case .bnbChain: return "BNB"
        case .tron: return "TRX"
        case .solana: return "SOL"
        }
    }

    var decimals: Int {
        switch self {
        case .ethereum, .bnbChain: return 18
        case .tron: return 6
        case .solana: return 9
        }
    }

    /// BNB Chain 是 EVM 兼容链，跟 Ethereum 用同一条派生路径，地址完全相同——
    /// 派生地址时两者都走 WalletCore 的 CoinType.ethereum，不需要（也没有把握去猜）一个
    /// 单独的 "smartchain" CoinType case 名。
    var derivesLikeEthereum: Bool {
        self == .bnbChain
    }

    /// 预设 RPC 节点，跟 docs/WALLET.md「预设节点」表格一致。第一个是默认值。
    var presetRpcEndpoints: [String] {
        switch self {
        case .ethereum:
            return ["https://ethereum-rpc.publicnode.com", "https://cloudflare-eth.com"]
        case .bnbChain:
            return ["https://bsc-dataseed.binance.org", "https://bsc-rpc.publicnode.com"]
        case .tron:
            return ["https://api.trongrid.io"]
        case .solana:
            return ["https://api.mainnet-beta.solana.com"]
        }
    }
}

struct WalletAccountSnapshot: Identifiable, Equatable {
    let chain: ChainId
    let address: String
    var balanceText: String?
    var loadingBalance: Bool = false

    var id: String { chain.id }
}
