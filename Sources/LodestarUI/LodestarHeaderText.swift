import SwiftUI

public enum LodestarHeaderTextStyle: Sendable, Equatable {
    case standard
    case prominentRoot

    public var eyebrowSize: CGFloat { self == .prominentRoot ? 10 : 9 }
    public var eyebrowTracking: CGFloat { self == .prominentRoot ? 2.8 : 0.7 }
    public var titleSize: CGFloat { self == .prominentRoot ? 31 : 17 }
    public var titleTracking: CGFloat { self == .prominentRoot ? 0.5 : 0 }
    public var usesHeavyWeight: Bool { self == .prominentRoot }
    public var usesCondensedTitle: Bool { self == .prominentRoot }
    public var uppercasesTitle: Bool { self == .prominentRoot }
}

public struct LodestarHeaderText: View {
    public let eyebrow: String
    public let title: String
    public let style: LodestarHeaderTextStyle
    @ScaledMetric private var eyebrowSize: CGFloat
    @ScaledMetric private var titleSize: CGFloat

    public init(
        eyebrow: String,
        title: String,
        style: LodestarHeaderTextStyle = .standard
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.style = style
        _eyebrowSize = ScaledMetric(wrappedValue: style.eyebrowSize, relativeTo: .caption2)
        _titleSize = ScaledMetric(wrappedValue: style.titleSize, relativeTo: .largeTitle)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LodestarMetrics.space2) {
            Text(eyebrow)
                .font(.system(size: eyebrowSize, weight: eyebrowWeight))
                .tracking(style.eyebrowTracking)
                .foregroundStyle(LodestarColor.textTertiary)
            Text(title)
                .font(titleFont)
                .textCase(style.uppercasesTitle ? .uppercase : nil)
                .tracking(style.titleTracking)
                .foregroundStyle(LodestarColor.textPrimary)
        }
    }

    private var eyebrowWeight: Font.Weight {
        style.usesHeavyWeight ? .heavy : .semibold
    }

    private var titleFont: Font {
        let font = Font.system(size: titleSize, weight: style.usesHeavyWeight ? .heavy : .bold)
        return style.usesCondensedTitle ? font.width(.condensed) : font
    }
}
