import Foundation

/// 跟 android-native data/remote/AuthApi.kt 逐接口对应。服务端 AuthController 全部是
/// @RequestParam（表单/query），不是 JSON body，所以这里全走 ApiClient.postForm。
struct AuthApi {
    let client: ApiClient

    func sendEmailCode(email: String, scene: String) async throws -> VerificationCodeResult {
        try await client.postForm(
            "/api/auth/code/email/send",
            fields: ["email": email, "scene": scene],
            authorized: false
        ).dataOrThrow()
    }

    func sendPhoneCode(phone: String, scene: String) async throws -> VerificationCodeResult {
        try await client.postForm(
            "/api/auth/code/phone/send",
            fields: ["phone": phone, "scene": scene],
            authorized: false
        ).dataOrThrow()
    }

    func register(
        username: String?,
        email: String?,
        phone: String?,
        password: String?,
        code: String,
        nickname: String?,
        inviteCode: String?
    ) async throws -> AuthResult {
        try await client.postForm(
            "/api/auth/register",
            fields: [
                "username": username,
                "email": email,
                "phone": phone,
                "password": password,
                "code": code,
                "nickname": nickname,
                "inviteCode": inviteCode,
            ],
            authorized: false
        ).dataOrThrow()
    }

    func loginByPassword(account: String, password: String) async throws -> AuthResult {
        try await client.postForm(
            "/api/auth/login/password",
            fields: ["account": account, "password": password],
            authorized: false
        ).dataOrThrow()
    }

    func loginByEmailCode(email: String, code: String) async throws -> AuthResult {
        try await client.postForm(
            "/api/auth/login/email",
            fields: ["email": email, "code": code],
            authorized: false
        ).dataOrThrow()
    }

    func loginByPhoneCode(phone: String, code: String) async throws -> AuthResult {
        try await client.postForm(
            "/api/auth/login/phone",
            fields: ["phone": phone, "code": code],
            authorized: false
        ).dataOrThrow()
    }

    func currentSession() async throws -> AuthResult {
        try await client.getJSON("/api/auth/me", authorized: true).dataOrThrow()
    }

    func logout() async throws {
        let response: ApiResponse<EmptyData> = try await client.postForm(
            "/api/auth/logout",
            fields: [:],
            authorized: true
        )
        try response.throwIfFailed()
    }
}
