import CryptoKit
import Foundation
import LibSignalClient

/// 对应 android-native E2eeSessionManager.kt：本机身份/会话的建立、加解密、自愈修复、群聊
/// Sender Key 全在这。服务端接口早就有了（见 E2eeApi），这里是客户端这半套。
struct E2eePeerKeysOutOfSyncException: Error, LocalizedError {
    let peerUserId: Int64
    var errorDescription: String? { "对方加密密钥尚未同步，请让对方打开 LinkU 后再试" }
}

@MainActor
final class E2eeSessionManager {
    /// iOS 固定用设备 id 3——安卓 1:1 固定 "1"，windows-native 固定 "2"，三端互不相同，
    /// 避免同一账号手机+电脑+iPhone 同时登录时互相顶掉 E2EE 身份。
    static let singleDeviceId: UInt32 = 3
    static let serverDeviceId = "3"
    /// 群聊 Sender Key 地址固定用设备 id 1，**跟平台无关**——windows-native 踩过的坑：这里如果误用
    /// singleDeviceId，会导致三端互相解不开对方的群消息（M5 实现群聊时必须用这个常量，不是
    /// singleDeviceId）。
    static let groupSenderKeyDeviceId: UInt32 = 1

    private static let ownKeysSyncInterval: TimeInterval = 5 * 60

    private let api: E2eeApi
    private let keyStore: E2eeKeyStore
    private let sessionStore: SessionStore
    private let context = NullContext()

    private var store: LinkuSignalProtocolStore?
    private var userId: Int64 = -1
    private var ready = false
    private var lastOwnKeysSyncAt: Date = .distantPast

    init(api: E2eeApi, keyStore: E2eeKeyStore, sessionStore: SessionStore) {
        self.api = api
        self.keyStore = keyStore
        self.sessionStore = sessionStore
    }

    private func requireUserId() throws -> Int64 {
        guard let id = sessionStore.user?.id else {
            throw ApiException(code: -1, apiMessage: "未登录，拿不到 userId")
        }
        return id
    }

    func ensureReady() async throws {
        let uid = try requireUserId()
        if ready, let existing = store, userId == uid {
            try await syncOwnKeysWithServerIfStale(existing)
            if existing.needsPreKeyUpload() { try await uploadPreKeys(existing, includeOneTimePreKeys: true) }
            return
        }
        let opened = LinkuSignalProtocolStore.open(keyStore: keyStore, userId: uid)
        store = opened
        userId = uid
        try await syncOwnKeysWithServer(opened)
        lastOwnKeysSyncAt = Date()
        if opened.needsPreKeyUpload() { try await uploadPreKeys(opened, includeOneTimePreKeys: true) }
        ready = true
    }

    private func syncOwnKeysWithServerIfStale(_ store: LinkuSignalProtocolStore) async throws {
        guard Date().timeIntervalSince(lastOwnKeysSyncAt) >= Self.ownKeysSyncInterval else { return }
        try await syncOwnKeysWithServer(store)
        lastOwnKeysSyncAt = Date()
    }

    /// 对比本机身份跟服务端记录，并校验服务端 PreKey 签名是否跟本机公钥一致——不一致就自动
    /// 重新注册 + 上传，不用用户手动干预。
    private func syncOwnKeysWithServer(_ store: LinkuSignalProtocolStore) async throws {
        let uid = try requireUserId()
        let localPublic = b64(try store.identityKeyPair(context: context).publicKey.serialize())

        let serverPublic: String = (try? await api.listDevices(userId: uid))?
            .first(where: { $0.deviceId == Self.serverDeviceId })?
            .identityKeyPublic.trimmingCharacters(in: .whitespaces) ?? ""

        let identityMismatch = serverPublic.isEmpty || serverPublic != localPublic
        var bundleInvalid = false
        if !identityMismatch {
            if let peek = try? await api.peekPreKeyBundle(targetUserId: uid, deviceId: Self.serverDeviceId) {
                bundleInvalid = !verifyBundleSignature(peek, expectedIdentityPublic: localPublic)
            } else {
                bundleInvalid = true
            }
        }

        if !identityMismatch, !bundleInvalid, !store.needsPreKeyUpload() { return }

        if !identityMismatch {
            try await uploadPreKeys(store, includeOneTimePreKeys: store.needsPreKeyUpload())
            return
        }

        try await api.registerDevice(
            userId: uid, deviceId: Self.serverDeviceId,
            registrationId: Int(store.registrationId), identityKeyPublic: localPublic
        )
        try await uploadPreKeys(store, includeOneTimePreKeys: true)
    }

    private func verifyBundleSignature(_ bundle: E2eePreKeyBundleView, expectedIdentityPublic: String) -> Bool {
        guard bundle.identityKeyPublic.trimmingCharacters(in: .whitespaces) == expectedIdentityPublic else { return false }
        do {
            let identityKey = try IdentityKey(bytes: unb64(bundle.identityKeyPublic))
            let signedPublic = try PublicKey(unb64(bundle.signedPreKeyPublic))
            let signature = unb64(bundle.signedPreKeySignature)
            return try identityKey.publicKey.verifySignature(message: signedPublic.serialize(), signature: signature)
        } catch {
            return false
        }
    }

    private func uploadPreKeys(_ store: LinkuSignalProtocolStore, includeOneTimePreKeys: Bool) async throws {
        let identityKeyPair = try store.identityKeyPair(context: context)
        let nowMs = UInt64(Date().timeIntervalSince1970 * 1000)

        let signedPreKeyId = UInt32(Int(Date().timeIntervalSince1970) % 100_000)
        let signedPrivateKey = PrivateKey.generate()
        let signature = identityKeyPair.privateKey.generateSignature(message: signedPrivateKey.publicKey.serialize())
        let signedRecord = try SignedPreKeyRecord(
            id: signedPreKeyId, timestamp: nowMs, privateKey: signedPrivateKey, signature: signature
        )
        try store.storeSignedPreKey(signedRecord, id: signedPreKeyId, context: context)

        // PQXDH last-resort key，跟 signed prekey 同一节奏轮换，让用同一份最新 libsignal 主干的
        // 客户端（windows-native / 未来的其他 iOS 设备）能握手；LibSignalClient 的 PreKeyBundle
        // 构造函数本身也强制要求这三个字段，不传就没法建 bundle。
        let kyberPreKeyId = (signedPreKeyId + 1) % 100_000
        let kyberKeyPair = KEMKeyPair.generate()
        let kyberSignature = identityKeyPair.privateKey.generateSignature(message: kyberKeyPair.publicKey.serialize())
        let kyberRecord = try KyberPreKeyRecord(
            id: kyberPreKeyId, timestamp: nowMs, keyPair: kyberKeyPair, signature: kyberSignature
        )
        try store.storeKyberPreKey(kyberRecord, id: kyberPreKeyId, context: context)

        var oneTimePayload: [[String: Any]] = []
        if includeOneTimePreKeys {
            let baseId = Int(Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000)) * 1000
            for offset in 1...50 {
                let id = UInt32((baseId + offset) & 0x7fffff)
                let preKeyPrivate = PrivateKey.generate()
                let record = try PreKeyRecord(id: id, privateKey: preKeyPrivate)
                try store.storePreKey(record, id: id, context: context)
                oneTimePayload.append(["keyId": Int(id), "publicKey": b64(preKeyPrivate.publicKey.serialize())])
            }
        }
        let oneTimeJson = (try? JSONSerialization.data(withJSONObject: oneTimePayload))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        try await api.uploadPreKeys(
            userId: try requireUserId(),
            deviceId: Self.serverDeviceId,
            signedPreKeyId: Int(signedPreKeyId),
            signedPreKeyPublic: b64(signedPrivateKey.publicKey.serialize()),
            signedPreKeySignature: b64(signature),
            oneTimePreKeys: oneTimeJson,
            kyberPreKeyId: Int(kyberPreKeyId),
            kyberPreKeyPublic: b64(kyberKeyPair.publicKey.serialize()),
            kyberPreKeySignature: b64(kyberSignature)
        )
    }

    // MARK: - 单聊

    func warmPeerSession(peerUserId: Int64) async throws {
        guard peerUserId > 0 else { return }
        try await ensureReady()
        guard let store else { return }
        try await ensureSession(store, peerUserId: peerUserId, checkRemoteIdentity: true)
    }

    func repairPeerSession(peerUserId: Int64) async throws {
        guard peerUserId > 0 else { return }
        try await ensureReady()
        guard let store else { return }
        let address = try store.remoteAddress(peerUserId: peerUserId, deviceId: Self.singleDeviceId)
        store.resetPeerIdentity(address)
        try await ensureSession(store, peerUserId: peerUserId, checkRemoteIdentity: true)
    }

    func encryptSingleChatText(peerUserId: Int64, plaintext: String) async throws -> String {
        try await encryptSingleChatPayload(peerUserId: peerUserId, payload: ["body": plaintext, "kind": "TEXT"])
    }

    func encryptSingleChatPayload(
        peerUserId: Int64,
        payload: [String: Any],
        preview: E2eePreview? = nil
    ) async throws -> String {
        try await ensureReady()
        do {
            return try encryptSingleChatPayloadOnce(peerUserId: peerUserId, payload: payload, preview: preview)
        } catch let outOfSync as E2eePeerKeysOutOfSyncException {
            throw outOfSync
        } catch {
            guard isRecoverableSessionError(error) else { throw error }
            try await repairPeerSession(peerUserId: peerUserId)
            return try encryptSingleChatPayloadOnce(peerUserId: peerUserId, payload: payload, preview: preview)
        }
    }

    private func encryptSingleChatPayloadOnce(
        peerUserId: Int64,
        payload: [String: Any],
        preview: E2eePreview?
    ) throws -> String {
        guard let store else { throw ApiException(code: -1, apiMessage: "E2EE 未就绪") }
        let localAddress = try store.remoteAddress(peerUserId: userId, deviceId: Self.singleDeviceId)
        let address = try store.remoteAddress(peerUserId: peerUserId, deviceId: Self.singleDeviceId)
        let plaintextData = try JSONSerialization.data(withJSONObject: payload)
        let ciphertextMessage = try signalEncrypt(
            message: plaintextData,
            for: address,
            localAddress: localAddress,
            sessionStore: store,
            identityStore: store,
            context: context
        )
        return E2eeEnvelope(
            version: 1,
            scheme: "signal",
            type: ciphertextMessage.messageType == .preKey ? "prekey_message" : "ciphertext",
            conversationType: "SINGLE",
            senderDeviceId: Self.serverDeviceId,
            registrationId: Int(store.registrationId),
            ciphertext: b64(ciphertextMessage.serialize()),
            messageType: Int(ciphertextMessage.messageType.rawValue),
            preview: preview ?? defaultPreview(payload)
        ).encode()
    }

    private func ensureSession(
        _ store: LinkuSignalProtocolStore,
        peerUserId: Int64,
        checkRemoteIdentity: Bool = false
    ) async throws {
        let address = try store.remoteAddress(peerUserId: peerUserId, deviceId: Self.singleDeviceId)
        if !checkRemoteIdentity, store.hasSession(for: address) { return }

        let bundleJson = try await api.fetchPreKeyBundle(targetUserId: peerUserId, deviceId: Self.serverDeviceId)
        let remoteIdentity = try IdentityKey(bytes: unb64(bundleJson.identityKeyPublic))

        if let storedIdentity = try store.identity(for: address, context: context), storedIdentity != remoteIdentity {
            store.resetPeerIdentity(address)
        }
        if store.hasSession(for: address) { return }

        try await applyPreKeyBundleWithRetry(store, peerUserId: peerUserId, bundleJson: bundleJson)
    }

    private func applyPreKeyBundleWithRetry(
        _ store: LinkuSignalProtocolStore,
        peerUserId: Int64,
        bundleJson: E2eePreKeyBundleView
    ) async throws {
        do {
            try applyPreKeyBundle(store, peerUserId: peerUserId, bundleJson: bundleJson)
        } catch {
            guard isPreKeySignatureError(error) else { throw error }
            try await syncOwnKeysWithServer(store)
            let fresh = try await api.fetchPreKeyBundle(targetUserId: peerUserId, deviceId: Self.serverDeviceId)
            do {
                try applyPreKeyBundle(store, peerUserId: peerUserId, bundleJson: fresh)
            } catch {
                if isPreKeySignatureError(error) { throw E2eePeerKeysOutOfSyncException(peerUserId: peerUserId) }
                throw error
            }
        }
    }

    private func applyPreKeyBundle(
        _ store: LinkuSignalProtocolStore,
        peerUserId: Int64,
        bundleJson: E2eePreKeyBundleView
    ) throws {
        let address = try store.remoteAddress(peerUserId: peerUserId, deviceId: Self.singleDeviceId)
        let localAddress = try store.remoteAddress(peerUserId: userId, deviceId: Self.singleDeviceId)
        let identityKey = try IdentityKey(bytes: unb64(bundleJson.identityKeyPublic))
        let signedPreKeyPublic = try PublicKey(unb64(bundleJson.signedPreKeyPublic))
        let signature = unb64(bundleJson.signedPreKeySignature)

        guard let kyberId = bundleJson.kyberPreKeyId,
              let kyberPublicRaw = bundleJson.kyberPreKeyPublic,
              let kyberSignatureRaw = bundleJson.kyberPreKeySignature else {
            throw E2eePeerKeysOutOfSyncException(peerUserId: peerUserId)
        }
        let kyberPublic = try KEMPublicKey(unb64(kyberPublicRaw))
        let kyberSignature = unb64(kyberSignatureRaw)

        let bundle: PreKeyBundle
        if let oneTimeId = bundleJson.oneTimePreKeyId, let oneTimePublicRaw = bundleJson.oneTimePreKeyPublic {
            let oneTimePublic = try PublicKey(unb64(oneTimePublicRaw))
            bundle = try PreKeyBundle(
                registrationId: UInt32(bundleJson.registrationId),
                deviceId: Self.singleDeviceId,
                prekeyId: UInt32(oneTimeId),
                prekey: oneTimePublic,
                signedPrekeyId: UInt32(bundleJson.signedPreKeyId),
                signedPrekey: signedPreKeyPublic,
                signedPrekeySignature: signature,
                identity: identityKey,
                kyberPrekeyId: UInt32(kyberId),
                kyberPrekey: kyberPublic,
                kyberPrekeySignature: kyberSignature
            )
        } else {
            bundle = try PreKeyBundle(
                registrationId: UInt32(bundleJson.registrationId),
                deviceId: Self.singleDeviceId,
                signedPrekeyId: UInt32(bundleJson.signedPreKeyId),
                signedPrekey: signedPreKeyPublic,
                signedPrekeySignature: signature,
                identity: identityKey,
                kyberPrekeyId: UInt32(kyberId),
                kyberPrekey: kyberPublic,
                kyberPrekeySignature: kyberSignature
            )
        }
        try LibSignalClient.processPreKeyBundle(
            bundle, for: address, ourAddress: localAddress, sessionStore: store, identityStore: store, context: context
        )
    }

    // MARK: - 群聊（Sender Key，WhatsApp/Signal 同款）

    private func groupDistributionSuffix(_ conversationId: Int64) -> String { "group_distribution_\(conversationId)" }
    private func groupPublishedSuffix(_ conversationId: Int64) -> String { "group_sk_published_\(conversationId)" }
    private func groupMembersSuffix(_ conversationId: Int64) -> String { "group_members_\(conversationId)" }

    private func currentDistributionId(_ conversationId: Int64) -> UUID? {
        keyStore.read(userId: userId, suffix: groupDistributionSuffix(conversationId)).flatMap { UUID(uuidString: $0) }
    }

    private func setCurrentDistributionId(_ conversationId: Int64, _ id: UUID) {
        keyStore.write(userId: userId, suffix: groupDistributionSuffix(conversationId), value: id.uuidString)
    }

    private func isGroupPublished(_ conversationId: Int64) -> Bool {
        keyStore.read(userId: userId, suffix: groupPublishedSuffix(conversationId)) == "1"
    }

    private func markGroupPublished(_ conversationId: Int64) {
        keyStore.write(userId: userId, suffix: groupPublishedSuffix(conversationId), value: "1")
    }

    private func unmarkGroupPublished(_ conversationId: Int64) {
        keyStore.delete(userId: userId, suffix: groupPublishedSuffix(conversationId))
    }

    private func memberFingerprint(_ memberUserIds: [Int64]) -> String {
        Array(Set(memberUserIds.filter { $0 > 0 })).sorted().map(String.init).joined(separator: ",")
    }

    private func readGroupMemberFingerprint(_ conversationId: Int64) -> String? {
        keyStore.read(userId: userId, suffix: groupMembersSuffix(conversationId))
    }

    private func writeGroupMemberFingerprint(_ conversationId: Int64, _ memberUserIds: [Int64]) {
        keyStore.write(userId: userId, suffix: groupMembersSuffix(conversationId), value: memberFingerprint(memberUserIds))
    }

    /// 库里 SenderKeyStore 协议只有 store/load，没有 remove——没法真的把已经写盘的 SenderKeyRecord
    /// 字节抹掉，但清掉本地"当前 distributionId"记账就够了：下次真要用群加密会生成一个全新的随机
    /// distributionId，跟这条旧记录是完全不同的存储槽位，旧记录留着不用不是安全问题。
    private func clearGroupSenderState(_ conversationId: Int64) {
        unmarkGroupPublished(conversationId)
        keyStore.delete(userId: userId, suffix: groupDistributionSuffix(conversationId))
        keyStore.delete(userId: userId, suffix: groupMembersSuffix(conversationId))
    }

    /// 群成员集合变了（拉人/踢人）就轮换自己的 Sender Key——返回需要广播给全群的新分发信封，
    /// 没变化或者自己已经不在群里了就返回 nil（不用发）。
    @discardableResult
    func handleGroupMembershipChange(conversationId: Int64, memberUserIds: [Int64]) async throws -> String? {
        try await ensureReady()
        let normalized = Array(Set(memberUserIds.filter { $0 > 0 })).sorted()
        let fingerprint = memberFingerprint(normalized)
        let previous = readGroupMemberFingerprint(conversationId)
        guard previous != fingerprint else { return nil }
        writeGroupMemberFingerprint(conversationId, normalized)

        guard normalized.contains(userId) else {
            clearGroupSenderState(conversationId)
            return nil
        }
        guard previous != nil else { return nil }
        return try await rotateGroupSenderKey(conversationId: conversationId)
    }

    func rotateGroupSenderKey(conversationId: Int64) async throws -> String? {
        try await ensureReady()
        unmarkGroupPublished(conversationId)
        keyStore.delete(userId: userId, suffix: groupDistributionSuffix(conversationId))
        return try await ensureGroupSenderKeyDistribution(conversationId: conversationId)
    }

    /// 第一次向群发 E2EE 消息前调用；已经分发过就返回 nil（不用重复广播）。
    @discardableResult
    func ensureGroupSenderKeyDistribution(conversationId: Int64) async throws -> String? {
        try await ensureReady()
        guard !isGroupPublished(conversationId) else { return nil }
        guard let store else { throw ApiException(code: -1, apiMessage: "E2EE 未就绪") }
        // 群 Sender Key 地址固定用 groupSenderKeyDeviceId（1），不是这台设备自己的 singleDeviceId——
        // 这是三端互认群消息的硬性要求，见类顶部注释。
        let myAddress = try store.remoteAddress(peerUserId: userId, deviceId: Self.groupSenderKeyDeviceId)
        let distributionId = UUID()
        let distribution = try SenderKeyDistributionMessage(
            from: myAddress, distributionId: distributionId, store: store, context: context
        )
        setCurrentDistributionId(conversationId, distributionId)
        markGroupPublished(conversationId)
        return encodeGroupDistributionEnvelope(store: store, distribution: distribution)
    }

    func ingestGroupSenderKeyDistribution(conversationId: Int64, senderUserId: Int64, content: String) async throws {
        guard let envelope = E2eeEnvelope.tryParse(content), envelope.type == "sender_key_distribution" else { return }
        try await ensureReady()
        guard let store else { return }
        let distribution = try SenderKeyDistributionMessage(bytes: unb64(envelope.ciphertext))
        let senderAddress = try store.remoteAddress(peerUserId: senderUserId, deviceId: Self.groupSenderKeyDeviceId)
        try processSenderKeyDistributionMessage(distribution, from: senderAddress, store: store, context: context)
    }

    private func encodeGroupDistributionEnvelope(store: LinkuSignalProtocolStore, distribution: SenderKeyDistributionMessage) -> String {
        E2eeEnvelope(
            version: 1,
            scheme: "signal",
            type: "sender_key_distribution",
            conversationType: "GROUP",
            senderDeviceId: Self.serverDeviceId,
            registrationId: Int(store.registrationId),
            ciphertext: b64(distribution.serialize()),
            messageType: Int(CiphertextMessage.MessageType.senderKey.rawValue)
        ).encode()
    }

    func encryptGroupText(conversationId: Int64, plaintext: String) async throws -> String {
        try await encryptGroupPayload(conversationId: conversationId, payload: ["body": plaintext, "kind": "TEXT"])
    }

    func encryptGroupPayload(conversationId: Int64, payload: [String: Any], preview: E2eePreview? = nil) async throws -> String {
        try await ensureReady()
        guard let store else { throw ApiException(code: -1, apiMessage: "E2EE 未就绪") }
        let myAddress = try store.remoteAddress(peerUserId: userId, deviceId: Self.groupSenderKeyDeviceId)
        let distributionId: UUID
        if let existing = currentDistributionId(conversationId) {
            distributionId = existing
        } else {
            let newId = UUID()
            _ = try SenderKeyDistributionMessage(from: myAddress, distributionId: newId, store: store, context: context)
            setCurrentDistributionId(conversationId, newId)
            distributionId = newId
        }
        let plaintextData = try JSONSerialization.data(withJSONObject: payload)
        let ciphertextMessage = try groupEncrypt(
            plaintextData, from: myAddress, distributionId: distributionId, store: store, context: context
        )
        return E2eeEnvelope(
            version: 1,
            scheme: "signal",
            type: "ciphertext",
            conversationType: "GROUP",
            senderDeviceId: Self.serverDeviceId,
            registrationId: Int(store.registrationId),
            ciphertext: b64(ciphertextMessage.serialize()),
            messageType: Int(CiphertextMessage.MessageType.senderKey.rawValue),
            preview: preview ?? defaultPreview(payload)
        ).encode()
    }

    private func decryptGroupPayloadOnce(conversationId: Int64, senderUserId: Int64, envelope: E2eeEnvelope) throws -> [String: Any] {
        guard let store else { throw ApiException(code: -1, apiMessage: "E2EE 未就绪") }
        let senderAddress = try store.remoteAddress(peerUserId: senderUserId, deviceId: Self.groupSenderKeyDeviceId)
        let plaintext = try groupDecrypt(unb64(envelope.ciphertext), from: senderAddress, store: store, context: context)
        return parsePayloadBytes(plaintext)
    }

    func encryptOutgoingGroup(conversationId: Int64, content: String, kind: String) async throws -> String {
        try await encryptGroupPayload(conversationId: conversationId, payload: ["body": content, "kind": kind])
    }

    // MARK: - 解密（单聊 + 群聊统一入口）

    func decryptPayloadMap(senderUserId: Int64, content: String, conversationId: Int64? = nil) async -> [String: Any] {
        guard E2eeEnvelope.looksEncrypted(content) else {
            return ["body": content, "kind": "TEXT"]
        }
        do { try await ensureReady() } catch {
            return ["body": content, "kind": "TEXT"]
        }
        guard let envelope = E2eeEnvelope.tryParse(content) else {
            return ["body": content, "kind": "TEXT"]
        }

        if envelope.type == "sender_key_distribution" {
            if let conversationId, conversationId > 0, senderUserId > 0 {
                try? await ingestGroupSenderKeyDistribution(conversationId: conversationId, senderUserId: senderUserId, content: content)
            }
            return ["kind": "SENDER_KEY_DISTRIBUTION"]
        }

        if envelope.conversationType == "GROUP" {
            guard let conversationId, conversationId > 0 else {
                return ["body": content, "kind": "TEXT"]
            }
            if let decrypted = try? decryptGroupPayloadOnce(conversationId: conversationId, senderUserId: senderUserId, envelope: envelope) {
                return decrypted
            }
            return ["body": content, "kind": "TEXT"]
        }

        do {
            return try decryptSinglePayloadOnce(senderUserId: senderUserId, envelope: envelope)
        } catch {
            if isLocalKeyStoreError(error) {
                try? await repairLocalKeyStore()
                if let retried = try? decryptSinglePayloadOnce(senderUserId: senderUserId, envelope: envelope) {
                    return retried
                }
                return ["kind": "UNDECRYPTABLE", "body": ""]
            }
            if isRecoverableSessionError(error) {
                try? await repairPeerSession(peerUserId: senderUserId)
                if let retried = try? decryptSinglePayloadOnce(senderUserId: senderUserId, envelope: envelope) {
                    return retried
                }
            }
            return ["kind": "UNDECRYPTABLE", "body": ""]
        }
    }

    private func decryptSinglePayloadOnce(senderUserId: Int64, envelope: E2eeEnvelope) throws -> [String: Any] {
        guard let store else { throw ApiException(code: -1, apiMessage: "E2EE 未就绪") }
        let address = try store.remoteAddress(peerUserId: senderUserId, deviceId: Self.singleDeviceId)
        let localAddress = try store.remoteAddress(peerUserId: userId, deviceId: Self.singleDeviceId)
        let bytes = unb64(envelope.ciphertext)
        let plaintext: Data
        if envelope.messageType == Int(CiphertextMessage.MessageType.preKey.rawValue) {
            let message = try PreKeySignalMessage(bytes: bytes)
            plaintext = try signalDecryptPreKey(
                message: message,
                from: address,
                localAddress: localAddress,
                sessionStore: store,
                identityStore: store,
                preKeyStore: store,
                signedPreKeyStore: store,
                kyberPreKeyStore: store,
                context: context
            )
        } else {
            let message = try SignalMessage(bytes: bytes)
            plaintext = try signalDecrypt(
                message: message, from: address, to: localAddress, sessionStore: store, identityStore: store, context: context
            )
        }
        return parsePayloadBytes(plaintext)
    }

    private func parsePayloadBytes(_ data: Data) -> [String: Any] {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
        return ["body": String(data: data, encoding: .utf8) ?? "", "kind": "TEXT"]
    }

    /// 只要一段能直接显示的文字（聊天气泡/列表预览用）——媒体类型给通用占位文案。
    func decryptContent(senderUserId: Int64, content: String, conversationId: Int64? = nil) async -> String {
        let decoded = await decryptPayloadMap(senderUserId: senderUserId, content: content, conversationId: conversationId)
        let kind = decoded["kind"] as? String
        if kind == "UNDECRYPTABLE" { return E2eeEnvelope.previewText(content) }
        if kind == "SENDER_KEY_DISTRIBUTION" { return "" }
        let caption = (decoded["caption"] as? String)?.trimmingCharacters(in: .whitespaces)
        switch kind {
        case "IMAGE": return (caption?.isEmpty == false) ? caption! : "[图片]"
        case "VOICE": return "[语音]"
        case "VIDEO": return (caption?.isEmpty == false) ? caption! : "[视频]"
        default: return decoded["body"] as? String ?? ""
        }
    }

    // MARK: - 给 ChatRepository 用的统一收发口

    func encryptOutgoingSingle(peerUserId: Int64, content: String, kind: String) async throws -> String {
        try await encryptSingleChatPayload(peerUserId: peerUserId, payload: ["body": content, "kind": kind])
    }

    /// 跟 decryptContent 不一样：这个是给"原样还原 content 字符串"用的，媒体消息的 body 本身就是
    /// JSON，不能被 decryptContent 那套"给人看的占位文案"逻辑处理掉。
    func decryptToContentString(senderUserId: Int64, content: String, conversationId: Int64? = nil) async -> String? {
        let decoded = await decryptPayloadMap(senderUserId: senderUserId, content: content, conversationId: conversationId)
        let kind = decoded["kind"] as? String
        if kind == "UNDECRYPTABLE" || kind == "SENDER_KEY_DISTRIBUTION" { return nil }
        return decoded["body"] as? String
    }

    private func defaultPreview(_ payload: [String: Any]) -> E2eePreview? {
        let kind = payload["kind"] as? String ?? "TEXT"
        let rawDuration = (payload["durationMs"] as? NSNumber)?.int64Value
        let durationMs = (rawDuration ?? 0) > 0 ? rawDuration : nil
        switch kind {
        case "IMAGE": return E2eePreview(kind: "IMAGE", text: "[图片]")
        case "VOICE": return E2eePreview(kind: "VOICE", text: "[语音]", durationMs: durationMs)
        case "VIDEO": return E2eePreview(kind: "VIDEO", text: "[视频]", durationMs: durationMs)
        case "FILE":
            let fileName = (payload["fileName"] as? String)?.trimmingCharacters(in: .whitespaces)
            return E2eePreview(kind: "FILE", text: (fileName?.isEmpty ?? true) ? "[文件]" : "[文件] \(fileName!)")
        default:
            let body = (payload["body"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !body.isEmpty else { return nil }
            let text = body.count > 48 ? String(body.prefix(48)) + "…" : body
            return E2eePreview(kind: "TEXT", text: text)
        }
    }

    // MARK: - 自己发的消息的明文缓存
    // Double Ratchet 是非对称的：自己没法把自己刚加密出去的密文再解密回来，所以自己发的消息要在
    // 加密之前就把明文记下来，后面翻聊天记录时直接读这份缓存，不走"解密"那条路。

    private func ownPlaintextCacheSuffix() -> String { "own_plaintext_cache" }

    private func readOwnPlaintextMap() -> [String: String] {
        guard let raw = keyStore.read(userId: userId, suffix: ownPlaintextCacheSuffix()),
              let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return [:] }
        return obj
    }

    func rememberOwnPlaintext(messageId: Int64, plaintext: String) {
        var map = readOwnPlaintextMap()
        map[String(messageId)] = plaintext
        guard let data = try? JSONSerialization.data(withJSONObject: map), let json = String(data: data, encoding: .utf8) else {
            return
        }
        keyStore.write(userId: userId, suffix: ownPlaintextCacheSuffix(), value: json)
    }

    func readOwnPlaintext(messageId: Int64) -> String? {
        readOwnPlaintextMap()[String(messageId)]
    }

    /// 换加密身份（用户主动重置）——本机身份/会话/PreKey/Sender Key 全清，重新走一遍 ensureReady。
    func resetLocalIdentity() async throws {
        ready = false
        store = nil
        let uid = try requireUserId()
        LinkuSignalProtocolStore.wipe(keyStore: keyStore, userId: uid)
        try await ensureReady()
    }

    // MARK: - 安全码

    /// 身份指纹校验码——本机 + 对方的身份公钥拼起来算一个双方各自独立计算也会得到同一个结果的
    /// 数字安全码，供用户线下或其他可信渠道核对，能防中间人攻击偷换公钥。用 peek 接口，不消耗
    /// 对方的 One-Time PreKey。
    func getSafetyNumber(peerUserId: Int64) async -> String? {
        do {
            try await ensureReady()
            guard let store else { return nil }
            let localPublic = try store.identityKeyPair(context: context).publicKey.serialize()
            let bundle = try await api.peekPreKeyBundle(targetUserId: peerUserId, deviceId: Self.serverDeviceId)
            let peerPublic = unb64(bundle.identityKeyPublic)
            let (first, second) = compareKeyBytes(localPublic, peerPublic) <= 0
                ? (localPublic, peerPublic) : (peerPublic, localPublic)
            let hash = SHA256.hash(data: first + second)
            return formatSafetyNumber(Array(hash))
        } catch {
            return nil
        }
    }

    /// 本机安全码——只对本机身份公钥算指纹，用于"这就是我自己的身份"这层确认。
    func getLocalIdentityFingerprint() async -> String? {
        do {
            try await ensureReady()
            guard let store else { return nil }
            let localPublic = try store.identityKeyPair(context: context).publicKey.serialize()
            let hash = SHA256.hash(data: localPublic)
            return formatSafetyNumber(Array(hash))
        } catch {
            return nil
        }
    }

    private func formatSafetyNumber(_ hashBytes: [UInt8]) -> String {
        var result = ""
        for (index, byte) in hashBytes.enumerated() {
            if index > 0, index % 5 == 0 { result += " " }
            result += String(Int(byte) % 10)
        }
        return result
    }

    private func compareKeyBytes(_ left: Data, _ right: Data) -> Int {
        let leftBytes = [UInt8](left)
        let rightBytes = [UInt8](right)
        let minLength = min(leftBytes.count, rightBytes.count)
        for i in 0..<minLength where leftBytes[i] != rightBytes[i] {
            return leftBytes[i] < rightBytes[i] ? -1 : 1
        }
        return leftBytes.count == rightBytes.count ? 0 : (leftBytes.count < rightBytes.count ? -1 : 1)
    }

    // MARK: - 错误分类（用 SignalError 精确匹配，比 android 端靠字符串匹配异常类名更可靠）

    private func isRecoverableSessionError(_ error: Error) -> Bool {
        guard !isLocalKeyStoreError(error) else { return false }
        guard let signalError = error as? SignalError else { return false }
        switch signalError {
        case .untrustedIdentity, .invalidMessage, .sessionNotFound:
            return true
        default:
            return false
        }
    }

    private func isLocalKeyStoreError(_ error: Error) -> Bool {
        guard let signalError = error as? SignalError else { return false }
        if case .invalidKeyIdentifier = signalError { return true }
        return false
    }

    private func isPreKeySignatureError(_ error: Error) -> Bool {
        guard let signalError = error as? SignalError else { return false }
        if case .invalidSignature = signalError { return true }
        return false
    }

    private func repairLocalKeyStore() async throws {
        guard let store else { return }
        try await uploadPreKeys(store, includeOneTimePreKeys: true)
    }

    // MARK: - base64 工具

    private func b64(_ data: Data) -> String { data.base64EncodedString() }
    private func unb64(_ value: String) -> Data { Data(base64Encoded: value) ?? Data() }
}
