import Foundation

/// 三条链的余额查询——只读，不签名、不广播，风险面很小（最坏情况是显示错误的余额，不会丢钱）。
/// 直接打公共 RPC 节点，不经过 LinkU 服务端（跟 docs/WALLET.md「公共 RPC 仅用于读余额」一致）。
enum ChainRpcError: Error {
    case invalidResponse
}

/// EVM 链（Ethereum / BNB Chain）用标准 JSON-RPC `eth_getBalance`，两条链共用同一个客户端，
/// 只是 RPC URL 不同。
struct EvmRpcClient {
    func getBalanceWei(address: String, rpcURL: String) async throws -> Decimal {
        guard let url = URL(string: rpcURL) else { throw ChainRpcError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "jsonrpc": "2.0", "id": 1, "method": "eth_getBalance", "params": [address, "latest"],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hex = obj["result"] as? String
        else { throw ChainRpcError.invalidResponse }
        return Decimal(hexString: hex) ?? 0
    }

    /// 群聊持币门槛检测用——只读 `eth_call`，不签名不广播，跟余额查询一个风险等级。
    /// selector 是 `symbol()`/`decimals()` 的 keccak256 前 4 字节，标准 ERC-20 ABI 固定值。
    func getTokenSymbol(tokenAddress: String, rpcURL: String) async throws -> String? {
        guard let raw = try await ethCall(to: tokenAddress, data: "0x95d89b41", rpcURL: rpcURL) else { return nil }
        return Self.decodeAbiString(raw)
    }

    func getTokenDecimals(tokenAddress: String, rpcURL: String) async throws -> Int? {
        guard let raw = try await ethCall(to: tokenAddress, data: "0x313ce567", rpcURL: rpcURL) else { return nil }
        var hex = raw
        if hex.hasPrefix("0x") { hex.removeFirst(2) }
        guard !hex.isEmpty, let value = UInt64(hex.suffix(64), radix: 16) else { return nil }
        return Int(value)
    }

    private func ethCall(to: String, data: String, rpcURL: String) async throws -> String? {
        guard let url = URL(string: rpcURL) else { throw ChainRpcError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "jsonrpc": "2.0", "id": 1, "method": "eth_call",
            "params": [["to": to, "data": data], "latest"],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (responseData, _) = try await URLSession.shared.data(for: request)
        guard let obj = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let hex = obj["result"] as? String, hex != "0x"
        else { return nil }
        return hex
    }

    /// 标准 ABI 动态 string 返回：前 32 字节是偏移量、接着 32 字节是长度、然后是内容本身
    /// （右侧补零到 32 字节倍数）。极少数老代币不遵守这个编码，解析失败按 android 端同样的
    /// 处理方式直接返回 nil，调用方兜底显示合约地址，不强行猜测别的编码方式。
    private static func decodeAbiString(_ hex: String) -> String? {
        var clean = hex
        if clean.hasPrefix("0x") { clean.removeFirst(2) }
        guard clean.count >= 128 else { return nil }
        let lengthHex = clean.dropFirst(64).prefix(64)
        guard let length = UInt64(lengthHex, radix: 16) else { return nil }
        let dataStart = clean.index(clean.startIndex, offsetBy: 128)
        let byteLength = Int(length) * 2
        guard clean.distance(from: dataStart, to: clean.endIndex) >= byteLength else { return nil }
        let contentHex = clean[dataStart..<clean.index(dataStart, offsetBy: byteLength)]
        var bytes: [UInt8] = []
        var index = contentHex.startIndex
        while index < contentHex.endIndex {
            let next = contentHex.index(index, offsetBy: 2)
            guard let byte = UInt8(contentHex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return String(bytes: bytes, encoding: .utf8)
    }
}

/// TRON 走 TronGrid REST API，不是 JSON-RPC——`balance` 字段账户没有 TRX 时服务端直接不返回
/// 这个字段（不是返回 0），要按缺省当 0 处理。
struct TronRpcClient {
    func getBalanceSun(address: String, apiURL: String) async throws -> Decimal {
        guard let url = URL(string: "\(apiURL)/wallet/getaccount") else { throw ChainRpcError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["address": address, "visible": true])
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ChainRpcError.invalidResponse
        }
        let balance = (obj["balance"] as? NSNumber)?.decimalValue ?? 0
        return balance
    }
}

/// Solana 标准 JSON-RPC `getBalance`，单位是 lamports。
struct SolanaRpcClient {
    func getBalanceLamports(address: String, rpcURL: String) async throws -> Decimal {
        guard let url = URL(string: rpcURL) else { throw ChainRpcError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "getBalance", "params": [address]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = obj["result"] as? [String: Any],
              let value = result["value"] as? NSNumber
        else { throw ChainRpcError.invalidResponse }
        return value.decimalValue
    }
}

extension Decimal {
    /// EVM `eth_getBalance` 返回的是 0x 前缀十六进制字符串（可能很大，超出 UInt64 范围，
    /// 所以逐位累加到 Decimal，不能直接 `UInt64(hex, radix: 16)`）。
    init?(hexString: String) {
        var hex = hexString
        if hex.hasPrefix("0x") { hex.removeFirst(2) }
        guard !hex.isEmpty else { return nil }
        var result = Decimal(0)
        for character in hex {
            guard let digit = character.hexDigitValue else { return nil }
            result = result * 16 + Decimal(digit)
        }
        self = result
    }
}
