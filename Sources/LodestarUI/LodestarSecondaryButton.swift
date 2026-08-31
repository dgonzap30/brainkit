import SwiftUI

public enum LodestarSecondaryActionPolicy {
    public static let height: CGFloat = LodestarMetrics.primaryControlHeight
    public static let radius: CGFloat = LodestarMetrics.primaryControlRadius
    public static let fillRole: LodestarColorRole = .neutral
    public static let borderWidth: CGFloat = 0.5
}

public struct LodestarSecondaryButton: View {
    public let title: String
    public let systemImage: String?
    public let isDisabled: Bool
    public let action: () -> Void

    public init(
        _ title: String,
        systemImage: String? = nil,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isDisabled = isDisabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: LodestarMetrics.spacingS) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(LodestarType.bodyEmphasis)
            .frame(maxWidth: .infinity)
            .frame(minHeight: LodestarSecondaryActionPolicy.height)
            .contentShape(.rect)
        }
        .buttonStyle(LodestarSecondaryButtonStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .accessibilityLabel(Text(title))
    }
}

private struct LodestarSecondaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(LodestarColor.textPrimary)
            .background(
                LodestarColor.surfaceMuted,
                in: .rect(cornerRadius: LodestarSecondaryActionPolicy.radius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: LodestarSecondaryActionPolicy.radius, style: .continuous)
                    .strokeBorder(
                        LodestarColor.border,
                        lineWidth: LodestarSecondaryActionPolicy.borderWidth
                    )
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(
                LodestarMotion.resolved(LodestarMotion.fast, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}
