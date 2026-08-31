import SwiftUI

/// Standard empty placeholder: SF Symbol, title, one-line hint.
public struct EmptyState: View {
    let icon: String
    let title: String
    let hint: String

    public init(icon: String, title: String, hint: String) {
        self.icon = icon
        self.title = title
        self.hint = hint
    }

    public var body: some View {
        VStack(spacing: LodestarMetrics.spacingM) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(LodestarColor.textTertiary)
            Text(title)
                .font(LodestarType.sectionTitle)
                .foregroundStyle(LodestarColor.textPrimary)
            Text(hint)
                .font(LodestarType.secondary)
                .foregroundStyle(LodestarColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(LodestarMetrics.spacingXL)
        .accessibilityElement(children: .combine)
    }
}
