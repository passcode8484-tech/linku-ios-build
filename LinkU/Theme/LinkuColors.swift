import SwiftUI

/// 跟 android-native ui/theme/Color.kt + LinkuColors.kt 逐字段对应的微信风格配色，
/// 保证三端（Flutter/Android/iOS）视觉上是同一套设计语言，不是"差不多"。
enum LinkuBrand {
    static let primary = Color(hex: 0x07C160)
    static let primaryDark = Color(hex: 0x049A54)
    static let danger = Color(hex: 0xFF5252)
}

struct LinkuColors {
    let background: Color
    let sectionGap: Color
    let searchFill: Color
    let divider: Color
    let secondaryText: Color
    let subtitleText: Color
    let primaryText: Color
    let chatBackground: Color
    let incomingBubble: Color
    let myBubble: Color
    let composerBar: Color
    let composerButtonFill: Color
    let composerIconColor: Color

    static let light = LinkuColors(
        background: Color(hex: 0xFFFFFF),
        sectionGap: Color(hex: 0xF7F7F7),
        searchFill: Color(hex: 0xEFEFF4),
        divider: Color(hex: 0xEDEDED),
        secondaryText: Color(hex: 0x8A93A3),
        subtitleText: Color(hex: 0x6B7280),
        primaryText: Color(hex: 0x111827),
        chatBackground: Color(hex: 0xEDEDED),
        incomingBubble: Color(hex: 0xFFFFFF),
        myBubble: LinkuBrand.primary,
        composerBar: Color(hex: 0xFFFFFF),
        composerButtonFill: Color(hex: 0xEFEFF4),
        composerIconColor: Color(hex: 0x4B5563)
    )

    static let dark = LinkuColors(
        background: Color(hex: 0x191919),
        sectionGap: Color(hex: 0x111111),
        searchFill: Color(hex: 0x2C2C2C),
        divider: Color(hex: 0x2E2E2E),
        secondaryText: Color(hex: 0x888888),
        subtitleText: Color(hex: 0x888888),
        primaryText: Color(hex: 0xE5E5E5),
        chatBackground: Color(hex: 0x111111),
        incomingBubble: Color(hex: 0x191919),
        myBubble: LinkuBrand.primary,
        composerBar: Color(hex: 0x191919),
        composerButtonFill: Color(hex: 0x2C2C2C),
        composerIconColor: Color(hex: 0xCCCCCC)
    )
}

private struct LinkuColorsKey: EnvironmentKey {
    static let defaultValue = LinkuColors.light
}

extension EnvironmentValues {
    var linkuColors: LinkuColors {
        get { self[LinkuColorsKey.self] }
        set { self[LinkuColorsKey.self] = newValue }
    }
}

extension View {
    /// 跟 Compose 的 `CompositionLocalProvider(LocalLinkuColors provides ...)` 对应，
    /// 在 RootView 里按 colorScheme 切换 light/dark 两套调色板。
    func linkuColorScheme(_ colorScheme: ColorScheme) -> some View {
        environment(\.linkuColors, colorScheme == .dark ? .dark : .light)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
