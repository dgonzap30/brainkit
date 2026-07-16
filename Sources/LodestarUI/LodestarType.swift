import SwiftUI

/// U1 type ramp: SF system styles ONLY — largeTitle / title / headline / body /
/// footnote, straight from `Font.TextStyle` (no bundled fonts, no custom faces).
/// This type exists for the one thing the system ramp doesn't standardize:
/// SF Mono for data (amounts, commits, timestamps).
public enum LodestarType {
    /// SF Mono at a Dynamic-Type-tracking style — for data values.
    public static func mono(_ style: Font.TextStyle = .body) -> Font {
        .system(style, design: .monospaced)
    }

    /// Proportional face with monospaced digits — for numerals inside prose
    /// (tabular alignment without switching the whole run to SF Mono).
    public static func monoDigits(_ style: Font.TextStyle = .body) -> Font {
        Font.system(style).monospacedDigit()
    }
}
