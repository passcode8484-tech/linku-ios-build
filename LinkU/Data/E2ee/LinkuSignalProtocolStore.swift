import Foundation
import LibSignalClient

/// 对应 android-native SignalProtocolStoreImpl.kt，实现 LibSignalClient 要求的全部六个 Store
/// 协议（IdentityKeyStore/PreKeyStore/SignedPreKeyStore/KyberPreKeyStore/SessionStore/
/// SenderKeyStore）。
///
/// 跟安卓那边不一样的地方：安卓受 SharedPreferences 的 API 形状所限，只能整个 Map 序列化成一份
/// blob，每次任何一条记录变化都要重写整份 blob，所以需要在内存里维护一份 Map 做缓存。Keychain
/// 没有这个限制，天然支持大量独立小条目，所以这里每条记录（每个 prekey/每个会话/每个 trusted
/// identity/每个 sender key）都是 Keychain 里独立的一条，不维护额外的内存缓存——少一层"内存缓存
/// 和磁盘不一致"的风险。
///
/// Swift 版 LibSignalClient 的 Store 协议本身比 Java 的 SignalProtocolStore 精简：没有
/// contains/delete/getSubDeviceSessions 这些方法（`loadSession` 直接返回 `SessionRecord?`，
/// nil 就是"没有会话"），"有没有会话"/"删会话" 这类需求要靠本类自己额外暴露的方法，不是协议要求的。
final class LinkuSignalProtocolStore {
    let userId: Int64
    let registrationId: UInt32
    private let identityKeyPairValue: IdentityKeyPair
    private let keyStore: E2eeKeyStore

    private init(keyStore: E2eeKeyStore, userId: Int64, registrationId: UInt32, identityKeyPair: IdentityKeyPair) {
        self.keyStore = keyStore
        self.userId = userId
        self.registrationId = registrationId
        self.identityKeyPairValue = identityKeyPair
    }

    /// 首次调用生成一份新身份并落盘；之后每次都是原样载入同一份——身份密钥这辈子不会自己变，
    /// 只有用户主动"重置本机加密身份"才会重新生成。
    static func open(keyStore: E2eeKeyStore, userId: Int64) -> LinkuSignalProtocolStore {
        if let keypairRaw = keyStore.read(userId: userId, suffix: "identity_keypair"),
           let registrationRaw = keyStore.read(userId: userId, suffix: "registration_id"),
           let keypairData = Data(base64Encoded: keypairRaw),
           let identityKeyPair = try? IdentityKeyPair(bytes: keypairData),
           let registrationId = UInt32(registrationRaw) {
            return LinkuSignalProtocolStore(
                keyStore: keyStore, userId: userId, registrationId: registrationId, identityKeyPair: identityKeyPair
            )
        }
        let identityKeyPair = IdentityKeyPair.generate()
        // 跟官方 InMemorySignalProtocolStore 示例一致的 14-bit 取值范围（0...0x3FFF）。
        let registrationId = UInt32.random(in: 1...0x3FFF)
        keyStore.write(userId: userId, suffix: "identity_keypair", value: identityKeyPair.serialize().base64EncodedString())
        keyStore.write(userId: userId, suffix: "registration_id", value: String(registrationId))
        return LinkuSignalProtocolStore(
            keyStore: keyStore, userId: userId, registrationId: registrationId, identityKeyPair: identityKeyPair
        )
    }

    // MARK: - 地址

    func addressName(peerUserId: Int64) -> String { "linku_\(peerUserId)" }

    func remoteAddress(peerUserId: Int64, deviceId: UInt32) throws -> ProtocolAddress {
        try ProtocolAddress(name: addressName(peerUserId: peerUserId), deviceId: deviceId)
    }

    // MARK: - 会话存在性/重置（协议之外的自定义方法，供 E2eeSessionManager 用）

    func hasSession(for address: ProtocolAddress) -> Bool {
        keyStore.read(userId: userId, suffix: sessionSuffix(address)) != nil
    }

    /// 对端身份变了（重装/换设备）时调用：删掉旧会话 + 旧 trusted identity，逼下一次通信重新走
    /// PreKeyBundle 握手，而不是卡在"身份不可信"报错——跟 android-native resetPeerIdentity 一样。
    func resetPeerIdentity(_ address: ProtocolAddress) {
        keyStore.delete(userId: userId, suffix: sessionSuffix(address))
        keyStore.delete(userId: userId, suffix: identitySuffix(address))
    }

    func needsPreKeyUpload(minimumOneTimePreKeys: Int = 20) -> Bool {
        let hasSignedPreKey = keyStore.count(userId: userId, suffixPrefix: "signedprekey_") > 0
        let oneTimeCount = keyStore.count(userId: userId, suffixPrefix: "prekey_")
        return !hasSignedPreKey || oneTimeCount < minimumOneTimePreKeys
    }

    // MARK: - 换加密身份

    /// 换加密身份（用户主动重置）用——把 E2eeKeyStore 里这个 userId 名下的一切都清空，
    /// 调用方（E2eeSessionManager）随后要重新调一次 open() 拿全新的 store。
    static func wipe(keyStore: E2eeKeyStore, userId: Int64) {
        keyStore.deleteAll(userId: userId)
    }

    // MARK: - 私有 key 命名 + base64 工具

    private func sessionSuffix(_ address: ProtocolAddress) -> String { "session_\(address.name)_\(address.deviceId)" }
    private func identitySuffix(_ address: ProtocolAddress) -> String {
        "trustedidentity_\(address.name)_\(address.deviceId)"
    }
    private func senderKeySuffix(_ address: ProtocolAddress, _ distributionId: UUID) -> String {
        "senderkey_\(address.name)_\(address.deviceId)_\(distributionId.uuidString)"
    }

    private func b64(_ data: Data) -> String { data.base64EncodedString() }
    private func unb64(_ value: String) -> Data { Data(base64Encoded: value) ?? Data() }
}

// MARK: - IdentityKeyStore

extension LinkuSignalProtocolStore: IdentityKeyStore {
    func identityKeyPair(context: StoreContext) throws -> IdentityKeyPair { identityKeyPairValue }

    func localRegistrationId(context: StoreContext) throws -> UInt32 { registrationId }

    func saveIdentity(_ identity: IdentityKey, for address: ProtocolAddress, context: StoreContext) throws -> IdentityChange {
        persistIdentity(identity, for: address) ? .replacedExisting : .newOrUnchanged
    }

    /// TOFU（首次信任）+ 对端身份变化时自动重置会话再信任新公钥——宁可无感知重建会话，也不因为
    /// 对端重装/换设备就把消息全部卡死在"身份不可信"报错上，这是主流 IM（WhatsApp/Signal 默认设置）
    /// 而不是最严格模式的取舍，跟 android-native 保持一致。
    func isTrustedIdentity(
        _ identity: IdentityKey,
        for address: ProtocolAddress,
        direction: Direction,
        context: StoreContext
    ) throws -> Bool {
        guard let trusted = loadIdentity(for: address) else { return true }
        if trusted == identity { return true }
        resetPeerIdentity(address)
        _ = persistIdentity(identity, for: address)
        return true
    }

    func identity(for address: ProtocolAddress, context: StoreContext) throws -> IdentityKey? {
        loadIdentity(for: address)
    }

    private func loadIdentity(for address: ProtocolAddress) -> IdentityKey? {
        guard let raw = keyStore.read(userId: userId, suffix: identitySuffix(address)) else { return nil }
        return try? IdentityKey(bytes: unb64(raw))
    }

    @discardableResult
    private func persistIdentity(_ identity: IdentityKey, for address: ProtocolAddress) -> Bool {
        let existing = loadIdentity(for: address)
        let changed = existing != nil && existing != identity
        keyStore.write(userId: userId, suffix: identitySuffix(address), value: b64(identity.serialize()))
        return changed
    }
}

// MARK: - PreKeyStore

extension LinkuSignalProtocolStore: PreKeyStore {
    func loadPreKey(id: UInt32, context: StoreContext) throws -> PreKeyRecord {
        guard let raw = keyStore.read(userId: userId, suffix: "prekey_\(id)") else {
            throw SignalError.invalidKeyIdentifier("no such prekey: \(id)")
        }
        return try PreKeyRecord(bytes: unb64(raw))
    }

    func storePreKey(_ record: PreKeyRecord, id: UInt32, context: StoreContext) throws {
        keyStore.write(userId: userId, suffix: "prekey_\(id)", value: b64(record.serialize()))
    }

    func removePreKey(id: UInt32, context: StoreContext) throws {
        keyStore.delete(userId: userId, suffix: "prekey_\(id)")
    }
}

// MARK: - SignedPreKeyStore

extension LinkuSignalProtocolStore: SignedPreKeyStore {
    func loadSignedPreKey(id: UInt32, context: StoreContext) throws -> SignedPreKeyRecord {
        guard let raw = keyStore.read(userId: userId, suffix: "signedprekey_\(id)") else {
            throw SignalError.invalidKeyIdentifier("no such signed prekey: \(id)")
        }
        return try SignedPreKeyRecord(bytes: unb64(raw))
    }

    func storeSignedPreKey(_ record: SignedPreKeyRecord, id: UInt32, context: StoreContext) throws {
        keyStore.write(userId: userId, suffix: "signedprekey_\(id)", value: b64(record.serialize()))
    }
}

// MARK: - KyberPreKeyStore

extension LinkuSignalProtocolStore: KyberPreKeyStore {
    func loadKyberPreKey(id: UInt32, context: StoreContext) throws -> KyberPreKeyRecord {
        guard let raw = keyStore.read(userId: userId, suffix: "kyberprekey_\(id)") else {
            throw SignalError.invalidKeyIdentifier("no such kyber prekey: \(id)")
        }
        return try KyberPreKeyRecord(bytes: unb64(raw))
    }

    func storeKyberPreKey(_ record: KyberPreKeyRecord, id: UInt32, context: StoreContext) throws {
        keyStore.write(userId: userId, suffix: "kyberprekey_\(id)", value: b64(record.serialize()))
    }

    /// Last-resort 密钥可以被多次使用（不像一次性 PreKey 用完就删），这里不做任何清理，
    /// 跟 android-native 一样。
    func markKyberPreKeyUsed(id: UInt32, signedPreKeyId: UInt32, baseKey: PublicKey, context: StoreContext) throws {}
}

// MARK: - SessionStore

// 显式写 LibSignalClient.SessionStore——这个 App 自己也有一个叫 SessionStore 的类
// （Storage/SessionStore.swift，管登录态），同名不同东西，不加模块前缀 Swift 会优先解析到
// 本模块自己的那个类，"inheritance from non-protocol type" 就是因为这样把协议名解析成了类名。
extension LinkuSignalProtocolStore: LibSignalClient.SessionStore {
    func loadSession(for address: ProtocolAddress, context: StoreContext) throws -> SessionRecord? {
        guard let raw = keyStore.read(userId: userId, suffix: sessionSuffix(address)) else { return nil }
        return try SessionRecord(bytes: unb64(raw))
    }

    func loadExistingSessions(for addresses: [ProtocolAddress], context: StoreContext) throws -> [SessionRecord] {
        try addresses.map { address in
            if let session = try loadSession(for: address, context: context) {
                return session
            }
            throw SignalError.sessionNotFound("\(address)")
        }
    }

    func storeSession(_ record: SessionRecord, for address: ProtocolAddress, context: StoreContext) throws {
        keyStore.write(userId: userId, suffix: sessionSuffix(address), value: b64(record.serialize()))
    }
}

// MARK: - SenderKeyStore（群聊 Sender Key，E2eeSessionManager 的群聊部分在用）

extension LinkuSignalProtocolStore: SenderKeyStore {
    func storeSenderKey(
        from sender: ProtocolAddress,
        distributionId: UUID,
        record: SenderKeyRecord,
        context: StoreContext
    ) throws {
        keyStore.write(userId: userId, suffix: senderKeySuffix(sender, distributionId), value: b64(record.serialize()))
    }

    func loadSenderKey(from sender: ProtocolAddress, distributionId: UUID, context: StoreContext) throws -> SenderKeyRecord? {
        guard let raw = keyStore.read(userId: userId, suffix: senderKeySuffix(sender, distributionId)) else { return nil }
        return try SenderKeyRecord(bytes: unb64(raw))
    }
}
