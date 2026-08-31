import SwiftUI

public struct LodestarStatePanel: View {
    public let icon: String
    public let title: String
    public let detail: String
    public let tone: LodestarPresentationTone
    public let actionLabel: String?
    public let action: (() -> Void)?

    public init(
        icon: String,
        title: String,
        detail: String,
        tone: LodestarPresentationTone = .neutral,
        actionLabel: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.detail = detail
        self.tone = tone
        self.actionLabel = actionLabel
        self.action = action
    }

    public var body: some View {
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
                        Text(detail)
                            .font(LodestarType.secondary)
                            .foregroundStyle(LodestarColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
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
