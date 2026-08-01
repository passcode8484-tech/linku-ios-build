import CryptoKit
import Foundation

/// 媒体文件本体的加密——跟消息文字/媒体指针走的 Signal 双棘轮不是一回事：独立一次性密钥的
/// AES-256-GCM，密钥/nonce 跟着消息内容（本身已经被 Signal 加密）一起传给对方。对应
/// android-native E2eeFileCrypto.kt，输出格式必须逐字节兼容：Java 的 `Cipher.getInstance
/// ("AES/GCM/NoPadding")` 输出是 `密文 || 16字节 tag`（IV 不包含在输出里，单独通过 fileIv
/// 字段传输）——所以这里用 `ciphertext + tag`，不能用 CryptoKit SealedBox 的 `.combined`
/// （那个是 `nonce + 密文 + tag`，会跟安卓端对不上）。
///
/// 跟安卓端的一个真实差异：CryptoKit 的 AES.GCM 只有整体加解密 API，没有流式 CipherInputStream/
/// CipherOutputStream 那一套，所以这里是一次性读完整个文件到内存再加解密——M4 范围只做图片/文件，
/// 体积可控；以后要支持大视频文件流式加密，得改用分块处理，这里先不做。
enum E2eeFileCrypto {
    static func generateKey() -> Data {
        Data(SymmetricKey(size: .bits256).withUnsafeBytes { Array($0) })
    }

    static func generateIv() -> Data {
        var bytes = [UInt8](repeating: 0, count: 12)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    static func encryptData(_ plaintext: Data, key: Data, iv: Data) throws -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let nonce = try AES.GCM.Nonce(data: iv)
        let sealedBox = try AES.GCM.seal(plaintext, using: symmetricKey, nonce: nonce)
        return sealedBox.ciphertext + sealedBox.tag
    }

    static func decryptData(_ combined: Data, key: Data, iv: Data) throws -> Data {
        guard combined.count >= 16 else {
            throw ApiException(code: -1, apiMessage: "密文数据过短")
        }
        let ciphertext = combined.prefix(combined.count - 16)
        let tag = combined.suffix(16)
        let nonce = try AES.GCM.Nonce(data: iv)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        return try AES.GCM.open(sealedBox, using: SymmetricKey(data: key))
    }

    static func encodeKey(_ data: Data) -> String { data.base64EncodedString() }
    static func decodeKey(_ value: String) -> Data { Data(base64Encoded: value) ?? Data() }
}
