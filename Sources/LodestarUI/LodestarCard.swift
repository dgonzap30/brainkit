import SwiftUI

public enum LodestarCardPolicy {
    public static let inset: CGFloat = LodestarMetrics.cardInset
    public static let radius: CGFloat = LodestarMetrics.radiusCard
    public static let borderWidth: CGFloat = 0.5
}

/// Standard card: surface fill, card radius, standard inset.
public struct LodestarCard<Content: View>: View {
    public let inset: CGFloat
    public let radius: CGFloat
    private let content: Content

    public init(
        inset: CGFloat = LodestarCardPolicy.inset,
        radius: CGFloat = LodestarCardPolicy.radius,
        @ViewBuilder content: () -> Content
    ) {
        self.inset = inset
        self.radius = radius
        self.content = content()
    }

    public var body: some View {
        content
            .padding(inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LodestarColor.surface, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LodestarColor.border, lineWidth: LodestarCardPolicy.borderWidth)
            }
    }
}
