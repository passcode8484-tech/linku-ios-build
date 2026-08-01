import Foundation

/// 服务端统一响应包裹：{code, msg, data}。code=0 才算成功，HTTP 状态码本身不可靠
/// （比如参数校验失败也是 HTTP 200，只是 code=400）——跟 android-native 的
/// ApiResponse.kt 是同一份约定，两边必须保持一致。
struct ApiResponse<T: Decodable>: Decodable {
    let code: Int
    let msg: String
    let data: T?

    var isSuccess: Bool { code == 0 }
}

/// 部分接口（登出等）成功时不返回业务数据，只需要校验 code；用这个占位当 T。
struct EmptyData: Decodable {}

struct ApiException: Error, LocalizedError {
    let code: Int
    let apiMessage: String

    var errorDescription: String? { apiMessage }
}

extension ApiResponse {
    func dataOrThrow() throws -> T {
        guard isSuccess else { throw ApiException(code: code, apiMessage: msg) }
        guard let data else { throw ApiException(code: code, apiMessage: "响应数据为空") }
        return data
    }
}

extension ApiResponse where T == EmptyData {
    func throwIfFailed() throws {
        guard isSuccess else { throw ApiException(code: code, apiMessage: msg) }
    }
}
