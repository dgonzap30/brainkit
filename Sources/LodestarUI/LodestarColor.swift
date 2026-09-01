import SwiftUI

public enum LodestarColor {
    public static let background = Color(lodestarHex: 0x000000)
    public static let surface = Color(lodestarHex: 0x0D0D0E)
    public static let surfaceRaised = Color(lodestarHex: 0x161617)
    public static let surfaceElevated = Color(lodestarHex: 0x0F0F10)
    public static let surfaceMuted = Color.white.opacity(0.05)
    public static let border = Color(lodestarHex: 0x232324)
    public static let hairline = Color.white.opacity(0.052)
    public static let textPrimary = Color(lodestarHex: 0xFAFAFA)
    public static let textSecondary = Color(lodestarHex: 0xA1A1AA)
    public static let textTertiary = Color(lodestarHex: 0x82828C)
    public static let textMuted = Color(lodestarHex: 0x3F3F46)
    public static let accent = Color(lodestarHex: 0xA78BFA)
    public static let success = Color(lodestarHex: 0x38CF82)
    public static let warning = Color(lodestarHex: 0xFF9F0A)
    public static let danger = Color(lodestarHex: 0xEF4444)

    public static let bg = background
    public static let elevated = surfaceRaised
    public static let statusOK = success
    public static let statusWarn = warning
    public static let statusError = danger
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
