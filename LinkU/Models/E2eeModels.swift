import Foundation

/// 跟 android-native remote/dto/E2eeDtos.kt 逐字段对应。
struct E2eeDeviceView: Codable, Equatable {
    let userId: Int64
    let deviceId: String
    let registrationId: Int
    let identityKeyPublic: String
}

struct E2eePreKeyBundleView: Codable, Equatable {
    let userId: Int64
    let deviceId: String
    let registrationId: Int
    let identityKeyPublic: String
    let signedPreKeyId: Int
    let signedPreKeyPublic: String
    let signedPreKeySignature: String
    let oneTimePreKeyId: Int?
    let oneTimePreKeyPublic: String?
    /// PQXDH last-resort 密钥；对方尚未上传时为 nil。iOS 这边用的 LibSignalClient（跟 windows-native
    /// 同源的 signalapp/libsignal 主干）的 PreKeyBundle 构造函数**强制要求** kyber 三件套，
    /// 没有经典 X3DH-only 的构造路径——所以如果这三个字段是 nil，iOS 端没法跟对方建会话，
    /// 只能报"对方加密密钥尚未同步"，这跟 android/windows 端"两条路径都支持"不一样，是 Swift
    /// binding 本身的限制，不是我们能绕开的实现选择。
    let kyberPreKeyId: Int?
    let kyberPreKeyPublic: String?
    let kyberPreKeySignature: String?
}
