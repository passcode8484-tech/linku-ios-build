import SwiftUI

/// 跟 android-native LinkuAvatarColors.kt 逐字段对应：按名称 hash 取柔和色占位头像。
enum LinkuAvatarColors {
    private static let fallback = Color(hex: 0xC8C8C8)

    private static let palette: [Color] = [
        Color(hex: 0x576B95),
        Color(hex: 0x787878),
        Color(hex: 0xFA9D3B),
        Color(hex: 0x10AEFF),
        Color(hex: 0x91D300),
        Color(hex: 0x1485EE),
        Color(hex: 0x7B68EE),
        Color(hex: 0xE17055),
        Color(hex: 0x00B894),
        Color(hex: 0x636E72),
    ]

    static func forName(_ name: String) -> Color {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        var hash = 0
        for unit in trimmed.unicodeScalars {
            hash = (hash + Int(unit.value)) % palette.count
        }
        return palette[hash]
    }
}
