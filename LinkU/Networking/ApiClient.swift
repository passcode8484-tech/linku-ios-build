import Foundation
import os

/// 给 ApiClient 提供当前登录 token 的接口，避免 Networking 层直接依赖 Storage 层
/// （对应 android-native AuthHeaderInterceptor 依赖 SessionStore 的关系，这里反过来
/// 用协议解耦，SessionStore 在 M1 实现这个协议）。
protocol AuthTokenProviding {
    func currentToken() async -> String?
}

/// 服务端 AuthController 等接口很多是 @RequestParam（表单/query）而不是 JSON body，
/// 所以 ApiClient 同时支持 form-urlencoded 和 JSON 两种请求体，跟 android-native
/// 的 Retrofit 接口注解（@FormUrlEncoded vs JSON converter）对应。
final class ApiClient {
    private let session: URLSession
    private let baseURL: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let tokenProvider: AuthTokenProviding?
    private let logger = Logger(subsystem: "com.linku.ios", category: "ApiClient")

    init(baseURLString: String = AppConfig.baseURL, tokenProvider: AuthTokenProviding? = nil) {
        guard let url = URL(string: baseURLString) else {
            fatalError("Invalid base URL: \(baseURLString)")
        }
        self.baseURL = url
        self.tokenProvider = tokenProvider

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 20
        self.session = URLSession(configuration: configuration)

        let decoder = JSONDecoder()
        self.decoder = decoder
        self.encoder = JSONEncoder()
    }

    // MARK: - Public API

    @discardableResult
    func getJSON<T: Decodable>(
        _ path: String,
        query: [String: String?] = [:],
        authorized: Bool = true
    ) async throws -> ApiResponse<T> {
        var request = try makeRequest(path: path, query: query, method: "GET")
        if authorized { try await attachAuthHeader(&request) }
        return try await execute(request)
    }

    @discardableResult
    func postForm<T: Decodable>(
        _ path: String,
        fields: [String: String?],
        authorized: Bool = true
    ) async throws -> ApiResponse<T> {
        var request = try makeRequest(path: path, query: [:], method: "POST")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(fields).data(using: .utf8)
        if authorized { try await attachAuthHeader(&request) }
        return try await execute(request)
    }

    @discardableResult
    func postJSON<T: Decodable, Body: Encodable>(
        _ path: String,
        body: Body,
        authorized: Bool = true
    ) async throws -> ApiResponse<T> {
        var request = try makeRequest(path: path, query: [:], method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        if authorized { try await attachAuthHeader(&request) }
        return try await execute(request)
    }

    /// 媒体上传——服务端 /api/im/media/upload 是 multipart/form-data，不是表单/JSON。
    @discardableResult
    func uploadMultipart<T: Decodable>(
        _ path: String,
        fields: [String: String],
        fileFieldName: String,
        fileData: Data,
        fileName: String,
        mimeType: String,
        authorized: Bool = true
    ) async throws -> ApiResponse<T> {
        var request = try makeRequest(path: path, query: [:], method: "POST")
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(
            boundary: boundary, fields: fields, fileFieldName: fileFieldName,
            fileData: fileData, fileName: fileName, mimeType: mimeType
        )
        if authorized { try await attachAuthHeader(&request) }
        return try await execute(request)
    }

    /// 有些 POST 接口（比如 CallApi 那几个）参数是 @Query 不是表单 body——服务端方法上
    /// 同时标了 @PostMapping 和 @RequestParam，参数走 URL query string，body 留空。
    @discardableResult
    func postFormWithQuery<T: Decodable>(
        _ path: String,
        query: [String: String?],
        authorized: Bool = true
    ) async throws -> ApiResponse<T> {
        var request = try makeRequest(path: path, query: query, method: "POST")
        if authorized { try await attachAuthHeader(&request) }
        return try await execute(request)
    }

    /// 媒体下载——服务端直接返回原始字节，不是 {code,msg,data} 包裹，所以单独一条路径，
    /// 不走 execute() 的 ApiResponse<T> 解码。
    func downloadRaw(_ path: String, query: [String: String?] = [:], authorized: Bool = true) async throws -> Data {
        var request = try makeRequest(path: path, query: query, method: "GET")
        if authorized { try await attachAuthHeader(&request) }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ApiException(code: code, apiMessage: "下载失败")
        }
        return data
    }

    // MARK: - Private helpers

    private func makeRequest(path: String, query: [String: String?], method: String) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw ApiException(code: -1, apiMessage: "非法请求路径: \(path)")
        }
        let items = query.compactMap { key, value -> URLQueryItem? in
            guard let value else { return nil }
            return URLQueryItem(name: key, value: value)
        }
        if !items.isEmpty { components.queryItems = items }
        guard let url = components.url else {
            throw ApiException(code: -1, apiMessage: "非法请求路径: \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// 对应 android-native AuthHeaderInterceptor：几乎所有接口都要带 Authorization: Bearer <token>。
    private func attachAuthHeader(_ request: inout URLRequest) async {
        guard let token = await tokenProvider?.currentToken(), !token.isEmpty else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> ApiResponse<T> {
        #if DEBUG
        logger.debug("\(request.httpMethod ?? "GET", privacy: .public) \(request.url?.absoluteString ?? "", privacy: .public)")
        #endif
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ApiException(code: -1, apiMessage: "无效的响应")
        }
        guard (200...299).contains(http.statusCode) else {
            throw ApiException(code: http.statusCode, apiMessage: "HTTP \(http.statusCode)")
        }
        do {
            return try decoder.decode(ApiResponse<T>.self, from: data)
        } catch {
            #if DEBUG
            logger.error("decode failed: \(error.localizedDescription, privacy: .public)")
            #endif
            throw ApiException(code: -1, apiMessage: "响应解析失败")
        }
    }

    private static func formEncode(_ fields: [String: String?]) -> String {
        fields.compactMap { key, value -> String? in
            guard let value else { return nil }
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
    }

    private static func multipartBody(
        boundary: String,
        fields: [String: String],
        fileFieldName: String,
        fileData: Data,
        fileName: String,
        mimeType: String
    ) -> Data {
        var body = Data()
        for (key, value) in fields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!
        )
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }
}
