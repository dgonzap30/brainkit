import SwiftUI

/// Suite-wide OLED palette. Monochrome by construction — hue is reserved for status.
/// The per-app accent is deliberately NOT a token here: apps keep their existing
/// accents and components inherit them through the environment (`.tint`).
/// System dark mode only; no custom color science.
public enum LodestarColor {
    /// True-black app background (OLED).
    public static let bg = Color.black
    /// Card / grouped-row surface (#131313).
    public static let surface = Color(white: 0.075)
    /// Elevated chrome: sheets, popovers, secondary cards (~#1F1F1F).
    public static let elevated = Color(white: 0.12)
    /// Hairlines and strokes (~#292929).
    public static let border = Color(white: 0.16)

    /// Semantic status hues — the only color in the system.
    public static let statusOK = Color(lodestarHex: 0x22C55E)
    public static let statusWarn = Color(lodestarHex: 0xF59E0B)
    public static let statusError = Color(lodestarHex: 0xEF4444)
}

extension Color {
    init(lodestarHex hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
