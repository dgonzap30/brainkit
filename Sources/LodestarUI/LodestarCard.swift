import SwiftUI

public enum LodestarCardPolicy {
    public static let inset: CGFloat = LodestarMetrics.cardInset
    public static let radius: CGFloat = LodestarMetrics.radiusCard
    public static let borderWidth: CGFloat = 0.5
    public static let recessedFillOpacity = 0.035
    public static let recessedBorderOpacity = 0.05
}

public enum LodestarCardStyle: Sendable, Equatable {
    case standard
    case recessed

    public var isRecessed: Bool { self == .recessed }
}

/// Standard card: surface fill, card radius, standard inset.
public struct LodestarCard<Content: View>: View {
    public let inset: CGFloat
    public let radius: CGFloat
    public let style: LodestarCardStyle
    private let content: Content

    public init(
        inset: CGFloat = LodestarCardPolicy.inset,
        radius: CGFloat = LodestarCardPolicy.radius,
        style: LodestarCardStyle = .standard,
        @ViewBuilder content: () -> Content
    ) {
        self.inset = inset
        self.radius = radius
        self.style = style
        self.content = content()
    }

    @ViewBuilder
    public var body: some View {
        switch style {
        case .standard:
            cardContent
                .background(LodestarColor.surface, in: .rect(cornerRadius: radius))
                .overlay {
                    cardShape.strokeBorder(
                        LodestarColor.border,
                        lineWidth: LodestarCardPolicy.borderWidth
                    )
                }
        case .recessed:
            cardContent
                .background {
                    cardShape.fill(Color.white.opacity(LodestarCardPolicy.recessedFillOpacity))
                    cardShape.fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color.black.opacity(0.14), location: 0),
                                .init(color: Color.clear, location: 0.48),
                                .init(color: Color.white.opacity(0.010), location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .overlay {
                    cardShape.strokeBorder(
                        Color.white.opacity(LodestarCardPolicy.recessedBorderOpacity),
                        lineWidth: LodestarCardPolicy.borderWidth
                    )
                }
        }
    }

    private var cardContent: some View {
        content
            .padding(inset)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}
