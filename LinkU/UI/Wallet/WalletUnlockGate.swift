import LocalAuthentication

/// 对应 android-native WalletUnlockGate.kt——查看助记词/私钥这类最敏感操作前，
/// 用设备自带的生物识别/密码再确认一次身份。失败或设备没设置锁屏就直接拒绝，不做"跳过"这种口子。
enum WalletUnlockGate {
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return false
        }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}
