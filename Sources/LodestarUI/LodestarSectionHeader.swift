import SwiftUI

public struct LodestarSectionHeader: View {
    public let title: String
    public let detail: String?

    public init(title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LodestarMetrics.spacingS) {
            Text(title)
                .font(LodestarType.sectionTitle)
                .foregroundStyle(LodestarColor.textPrimary)
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
}
