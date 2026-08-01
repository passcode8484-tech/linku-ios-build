import Foundation
import WalletCore

/// 对应 android-native data/wallet/（WalletRepository/WalletAccountRepository/WalletKeyStore 等
/// 几个类合在一起的精简版）。**这次只做创建/导入助记词 + 四链地址派生 + 只读余额查询 + 收款码
/// ——不做转账/swap（签名+广播交易）。** 这不是功能范围的常规取舍，是安全考量：转账代码一旦有
/// bug 就是真金白银的损失，而这个环境没有编译器、没有测试网验证手段，任何手写的签名/广播代码
/// 在被人用 Xcode 真正跑一遍、过一遍测试网小额转账之前都不该碰真实资产。地址派生/余额查询错了
/// 最坏结果是显示错误数字，不会导致资金损失，风险等级完全不同。
///
/// 助记词生成/派生用 Trust Wallet 的 WalletCore（SPM 包，经过大量生产环境验证的开源多链钱包库），
/// 不是自己手写 BIP39/BIP32/secp256k1——这类底层密码学代码手写出错的代价太高，能用经过审计的
/// 库就不要自己重新发明。
@MainActor
final class WalletRepository {
    private let keyStore = WalletKeyStore()
    private let sessionStore: SessionStore
    private let evmClient = EvmRpcClient()
    private let tronClient = TronRpcClient()
    private let solanaClient = SolanaRpcClient()
    private let rpcPrefs = WalletRpcPrefs()

    init(sessionStore: SessionStore) {
        self.sessionStore = sessionStore
    }

    private func requireUserId() throws -> Int64 {
        guard let id = sessionStore.user?.id else { throw ApiException(code: -1, apiMessage: "未登录") }
        return id
    }

    var hasWallet: Bool {
        guard let userId = sessionStore.user?.id else { return false }
        return keyStore.hasWallet(forUserId: userId)
    }

    /// 128 bit 熵 = 12 个助记词，主流钱包的默认长度。
    func generateMnemonic() -> String? {
        HDWallet(strength: 128, passphrase: "")?.mnemonic
    }

    func isValidMnemonic(_ mnemonic: String) -> Bool {
        Mnemonic.isValid(mnemonic: mnemonic.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    /// 创建/导入都走这个存盘——调用前调用方要已经让用户完成"备份确认"（创建流程）或
    /// 校验过合法性（导入流程，见 isValidMnemonic）。
    func saveWallet(mnemonic: String) throws {
        let userId = try requireUserId()
        keyStore.saveMnemonic(mnemonic.trimmingCharacters(in: .whitespacesAndNewlines), forUserId: userId)
    }

    /// 移除钱包仅删除本机存储——助记词没有单独备份的话真的找不回来了，UI 层必须有一道
    /// "再次确认"才能调到这里。
    func removeWallet() throws {
        let userId = try requireUserId()
        keyStore.removeMnemonic(forUserId: userId)
    }

    func revealMnemonic() throws -> String {
        let userId = try requireUserId()
        guard let mnemonic = keyStore.loadMnemonic(forUserId: userId) else {
            throw ApiException(code: -1, apiMessage: "钱包不存在")
        }
        return mnemonic
    }

    /// BNB Chain 是 EVM 兼容链，跟 Ethereum 同一条派生路径、地址完全相同（docs/WALLET.md
    /// 原文如此），所以这里没有单独派生一次，直接复用 Ethereum 地址。
    func deriveAddresses() throws -> [ChainId: String] {
        let userId = try requireUserId()
        guard let mnemonic = keyStore.loadMnemonic(forUserId: userId),
              let wallet = HDWallet(mnemonic: mnemonic, passphrase: "")
        else {
            throw ApiException(code: -1, apiMessage: "钱包不存在")
        }
        let ethAddress = CoinType.ethereum.deriveAddress(privateKey: wallet.getKeyForCoin(coin: .ethereum))
        let tronAddress = CoinType.tron.deriveAddress(privateKey: wallet.getKeyForCoin(coin: .tron))
        let solanaAddress = CoinType.solana.deriveAddress(privateKey: wallet.getKeyForCoin(coin: .solana))
        return [
            .ethereum: ethAddress,
            .bnbChain: ethAddress,
            .tron: tronAddress,
            .solana: solanaAddress,
        ]
    }

    func fetchBalanceText(chain: ChainId, address: String) async -> String {
        do {
            let rpcURL = rpcPrefs.currentEndpoint(for: chain)
            let raw: Decimal
            switch chain {
            case .ethereum, .bnbChain:
                raw = try await evmClient.getBalanceWei(address: address, rpcURL: rpcURL)
            case .tron:
                raw = try await tronClient.getBalanceSun(address: address, apiURL: rpcURL)
            case .solana:
                raw = try await solanaClient.getBalanceLamports(address: address, rpcURL: rpcURL)
            }
            return Self.format(raw, decimals: chain.decimals, symbol: chain.symbol)
        } catch {
            return "读取失败"
        }
    }

    func currentEndpoint(for chain: ChainId) -> String {
        rpcPrefs.currentEndpoint(for: chain)
    }

    func setCustomEndpoint(_ url: String?, for chain: ChainId) {
        rpcPrefs.setCustomEndpoint(url, for: chain)
    }

    /// 群聊持币门槛表单用——服务端的余额校验（EvmBalanceService）只硬编码了 ethereum/bsc 两条
    /// RPC，跟这两条链以外没有意义，调用方（TokenGateSheet）本来就只让选这两条链。
    func detectTokenMeta(chain: ChainId, tokenAddress: String) async -> (symbol: String, decimals: Int)? {
        let rpcURL = rpcPrefs.currentEndpoint(for: chain)
        async let symbol = try? evmClient.getTokenSymbol(tokenAddress: tokenAddress, rpcURL: rpcURL)
        async let decimals = try? evmClient.getTokenDecimals(tokenAddress: tokenAddress, rpcURL: rpcURL)
        guard let symbol = await symbol ?? nil, let decimals = await decimals ?? nil else { return nil }
        return (symbol, decimals)
    }

    private static func format(_ raw: Decimal, decimals: Int, symbol: String) -> String {
        var divisor = Decimal(1)
        for _ in 0..<decimals { divisor *= 10 }
        var value = raw / divisor
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 6, .down)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 6
        let numberText = formatter.string(from: rounded as NSDecimalNumber) ?? "\(rounded)"
        return "\(numberText) \(symbol)"
    }
}

/// 每条链的自定义 RPC 覆盖——存 UserDefaults 就够了，不是敏感数据（跟安卓端
/// SharedPreferences 存节点配置一个道理）。没设置过自定义节点就用 presetRpcEndpoints 的第一个。
private struct WalletRpcPrefs {
    private let defaults = UserDefaults.standard
    private func key(for chain: ChainId) -> String { "linku.wallet.rpc.\(chain.rawValue)" }

    func currentEndpoint(for chain: ChainId) -> String {
        defaults.string(forKey: key(for: chain)) ?? chain.presetRpcEndpoints[0]
    }

    func setCustomEndpoint(_ url: String?, for chain: ChainId) {
        if let url, !url.trimmingCharacters(in: .whitespaces).isEmpty {
            defaults.set(url, forKey: key(for: chain))
        } else {
            defaults.removeObject(forKey: key(for: chain))
        }
    }
}
