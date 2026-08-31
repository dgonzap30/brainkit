import SwiftUI

public enum LodestarType {
    public static let screenTitle = Font.headline.bold()
    public static let sectionTitle = Font.subheadline.weight(.semibold)
    public static let body = Font.subheadline
    public static let bodyEmphasis = Font.subheadline.weight(.semibold)
    public static let secondary = Font.footnote.weight(.medium)
    public static let small = Font.caption.weight(.medium)
    public static let caption = Font.caption2.weight(.medium)

    public static func heroNumber(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
            .width(.condensed)
            .monospacedDigit()
    }

    public static func mono(_ style: Font.TextStyle = .body) -> Font {
        .system(style, design: .monospaced)
    }

    public static func monoDigits(_ style: Font.TextStyle = .body) -> Font {
        Font.system(style).monospacedDigit()
    }
}
