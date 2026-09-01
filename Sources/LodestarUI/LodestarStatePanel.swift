import SwiftUI

public enum LodestarStatePanelContentAlignment: Sendable, Equatable {
    case leading
    case centered
}

public enum LodestarStatePanelLayout: Sendable, Equatable {
    case card
    case compact
    case hero

    public var isFramed: Bool { self == .card }

    public var contentAlignment: LodestarStatePanelContentAlignment {
        self == .hero ? .centered : .leading
    }

    public var iconSize: CGFloat {
        switch self {
        case .card: 20
        case .compact: 16
        case .hero: 28
        }
    }

    public var contentSpacing: CGFloat {
        switch self {
        case .card, .hero: 12
        case .compact: 10
        }
    }

    public var verticalPadding: CGFloat {
        self == .compact ? 16 : 0
    }
}

public struct LodestarStatePanel: View {
    public let icon: String
    public let title: String
    public let detail: String?
    public let tone: LodestarPresentationTone
    public let layout: LodestarStatePanelLayout
    public let actionLabel: String?
    public let action: (() -> Void)?

    public init(
        icon: String,
        title: String,
        detail: String? = nil,
        tone: LodestarPresentationTone = .neutral,
        layout: LodestarStatePanelLayout = .card,
        actionLabel: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.detail = detail
        self.tone = tone
        self.layout = layout
        self.actionLabel = actionLabel
        self.action = action
    }

    @ViewBuilder
    public var body: some View {
        switch layout {
        case .card:
            cardPanel
        case .compact:
            compactPanel
        case .hero:
            heroPanel
        }
    }

    private var cardPanel: some View {
        LodestarCard {
            VStack(alignment: .leading, spacing: LodestarMetrics.spacingM) {
                HStack(alignment: .top, spacing: LodestarMetrics.spacingM) {
                    Image(systemName: icon)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(tone.foregroundColor)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: LodestarMetrics.spacingXS) {
                        Text(title)
                            .font(LodestarType.bodyEmphasis)
                            .foregroundStyle(LodestarColor.textPrimary)
                        if let detail {
                            Text(detail)
                                .font(LodestarType.secondary)
                                .foregroundStyle(LodestarColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .accessibilityElement(children: .combine)

                if let actionLabel, let action {
                    LodestarSecondaryButton(actionLabel, action: action)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var compactPanel: some View {
        HStack(spacing: layout.contentSpacing) {
            Image(systemName: icon)
                .font(.system(size: layout.iconSize, weight: .medium))
                .foregroundStyle(compactForegroundColor)
            VStack(alignment: .leading, spacing: LodestarMetrics.spacingXS) {
                Text(title)
                    .font(LodestarType.caption)
                    .foregroundStyle(LodestarColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(LodestarType.caption)
                        .foregroundStyle(LodestarColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, layout.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var heroPanel: some View {
        VStack(spacing: layout.contentSpacing) {
            Image(systemName: icon)
                .font(.system(size: layout.iconSize, weight: .medium))
                .foregroundStyle(LodestarColor.textTertiary)

            VStack(spacing: LodestarMetrics.spacingXS) {
                Text(title)
                    .font(LodestarType.secondary)
                    .foregroundStyle(LodestarColor.textSecondary)
                    .multilineTextAlignment(.center)
                if let detail {
                    Text(detail)
                        .font(LodestarType.small)
                        .foregroundStyle(LodestarColor.textTertiary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var compactForegroundColor: Color {
        tone.colorRole == .neutral ? LodestarColor.textTertiary : tone.foregroundColor
    }
}

private extension LodestarPresentationTone {
    var foregroundColor: Color {
        switch colorRole {
        case .primary: LodestarColor.textPrimary
        case .neutral: LodestarColor.textSecondary
        case .success: LodestarColor.success
        case .warning: LodestarColor.warning
        case .danger: LodestarColor.danger
        case .disabled: LodestarColor.textMuted
        }
    }
}
