import SwiftUI

/// Spacing scale, corner radii, and the standard card inset.
public enum LodestarMetrics {
    public static let spacingXS: CGFloat = 4
    public static let spacingS: CGFloat = 8
    public static let spacingM: CGFloat = 12
    public static let spacingL: CGFloat = 16
    public static let spacingXL: CGFloat = 24

    /// Cards and grouped rows.
    public static let radiusCard: CGFloat = 8
    /// Sheets and floating chrome.
    public static let radiusSheet: CGFloat = 12
    /// Standard interior padding for `LodestarCard`.
    public static let cardInset: CGFloat = 12
}
