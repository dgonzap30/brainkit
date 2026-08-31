import SwiftUI

public enum LodestarPrimaryActionPolicy {
    public static let height: CGFloat = LodestarMetrics.primaryControlHeight
    public static let radius: CGFloat = LodestarMetrics.primaryControlRadius
    public static let fillRole: LodestarColorRole = .primary
}

public struct LodestarPrimaryButton: View {
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
            .frame(minHeight: LodestarPrimaryActionPolicy.height)
            .contentShape(.rect)
        }
        .buttonStyle(LodestarPrimaryButtonStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .accessibilityLabel(Text(title))
    }
}

private struct LodestarPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.black)
            .background(
                LodestarColor.textPrimary,
                in: .rect(cornerRadius: LodestarPrimaryActionPolicy.radius)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(
                LodestarMotion.resolved(LodestarMotion.fast, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}
