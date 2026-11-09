import SwiftUI

/// The desktop app's dark theme (web/src/index.css), colour for colour.
enum Theme {
    static let bg = Color(hex: 0x1A1A1C)          // app canvas
    static let panel = Color(hex: 0x151517)       // chrome rail, tab bar
    static let card = Color(hex: 0x222225)        // surface
    static let hover = Color(hex: 0x29292C)       // raised / selected
    static let border = Color(hex: 0x343438)      // hairline
    static let input = Color(hex: 0x1F1F22)
    static let inputBorder = Color(hex: 0x3C3C40)

    static let text = Color(hex: 0xE4E4E7)
    static let secondary = Color(hex: 0xA8A8AD)
    static let muted = Color(hex: 0x808086)

    static let teal = Color(hex: 0x14B8A6)
    static let cyan = Color(hex: 0x2DD4BF)
    static let violet = Color(hex: 0x8B5CF6)
    static let rose = Color(hex: 0xF43F5E)
    static let amber = Color(hex: 0xF59E0B)
    static let green = Color(hex: 0x22C55E)

    /// Our side of a conversation.
    static let outBubble = Color(hex: 0x14B8A6).opacity(0.16)
    static let atlasBubble = Color(hex: 0x8B5CF6).opacity(0.16)

    static let atlasGradient = [Color(hex: 0xC4B5FD), Color(hex: 0x8B5CF6), Color(hex: 0x6D28D9), Color(hex: 0xC4B5FD)]
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension Font {
    /// The desktop's text-ui (14px) and text-meta (12px), on iOS's scale.
    static let ui = Font.system(size: 15)
    static let uiMedium = Font.system(size: 15, weight: .medium)
    static let meta = Font.system(size: 12.5)
    static let metaMedium = Font.system(size: 12.5, weight: .medium)
    static let tag = Font.system(size: 10.5, weight: .semibold)
}

/// A card on the canvas: the surface, a hairline, rounded 12.
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}
