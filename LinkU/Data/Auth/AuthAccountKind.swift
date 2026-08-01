import Foundation

enum AuthAccountKind: Equatable {
    case email
    case phone
}

/// 邮箱看起来像邮箱就当邮箱，否则当手机号——真正的合法性校验交给服务端，
/// 跟 android-native detectAccountKind 是同一个"看起来像"策略。
func detectAccountKind(_ input: String) -> AuthAccountKind {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if let range = trimmed.range(of: "^.+@.+$", options: .regularExpression), range == trimmed.startIndex..<trimmed.endIndex {
        return .email
    }
    return .phone
}
