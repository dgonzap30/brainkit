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
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
            Text(hint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(LodestarMetrics.spacingXL)
        .accessibilityElement(children: .combine)
    }
}
