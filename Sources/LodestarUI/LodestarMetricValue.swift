import SwiftUI

public struct LodestarMetricValue: View {
    public let value: String
    public let detail: String?

    @ScaledMetric(relativeTo: .largeTitle) private var displaySize: CGFloat = 34

    public init(value: String, detail: String? = nil, displaySize: CGFloat = 34) {
        self.value = value
        self.detail = detail
        self._displaySize = ScaledMetric(wrappedValue: displaySize, relativeTo: .largeTitle)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LodestarMetrics.spacingXS) {
            Text(value)
                .font(LodestarType.heroNumber(size: displaySize))
                .foregroundStyle(LodestarColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(LodestarType.secondary)
                    .foregroundStyle(LodestarColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
