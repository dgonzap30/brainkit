import SwiftUI

public enum LodestarSectionHeaderStyle: Sendable, Equatable {
    case standard
    case settings

    public var fontSize: CGFloat { self == .settings ? 11 : 15 }
    public var tracking: CGFloat { self == .settings ? 1.6 : 0 }
    public var uppercasesTitle: Bool { self == .settings }
    public var usesSecondaryForeground: Bool { self == .settings }
}

public struct LodestarSectionHeader: View {
    public let title: String
    public let detail: String?
    public let style: LodestarSectionHeaderStyle
    @ScaledMetric private var settingsFontSize: CGFloat

    public init(
        title: String,
        detail: String? = nil,
        style: LodestarSectionHeaderStyle = .standard
    ) {
        self.title = title
        self.detail = detail
        self.style = style
        _settingsFontSize = ScaledMetric(wrappedValue: style.fontSize, relativeTo: .caption2)
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LodestarMetrics.spacingS) {
            titleView
            Spacer(minLength: LodestarMetrics.spacingS)
            if let detail {
                Text(detail)
                    .font(LodestarType.secondary)
                    .foregroundStyle(LodestarColor.textSecondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var titleView: some View {
        switch style {
        case .standard:
            Text(title)
                .font(LodestarType.sectionTitle)
                .foregroundStyle(LodestarColor.textPrimary)
        case .settings:
            Text(title)
                .font(.system(size: settingsFontSize, weight: .bold))
                .foregroundStyle(LodestarColor.textSecondary)
                .textCase(.uppercase)
                .tracking(style.tracking)
        }
    }
}
