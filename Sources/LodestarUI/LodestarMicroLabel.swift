import SwiftUI

public struct LodestarMicroLabel: View {
    public let text: String

    @ScaledMetric(relativeTo: .caption2) private var fontSize: CGFloat = 9

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .semibold))
            .tracking(0.7)
            .textCase(.uppercase)
            .foregroundStyle(LodestarColor.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
