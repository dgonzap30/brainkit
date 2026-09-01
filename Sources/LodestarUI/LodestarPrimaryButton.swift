import SwiftUI

public enum LodestarPrimaryActionPolicy {
    public static let height: CGFloat = LodestarMetrics.primaryControlHeight
    public static let radius: CGFloat = LodestarMetrics.primaryControlRadius
    public static let fillRole: LodestarColorRole = .primary
}

public enum LodestarPrimaryButtonLayout: Sendable, Equatable {
    case standard
    case compactCapsule

    public var isFullWidth: Bool { self == .standard }
    public var usesCapsule: Bool { self == .compactCapsule }
    public var horizontalPadding: CGFloat { self == .compactCapsule ? 18 : 0 }
    public var verticalPadding: CGFloat { self == .compactCapsule ? 8 : 0 }
    public var fontSize: CGFloat { self == .compactCapsule ? 13 : 15 }
    public var semanticTextStyle: Font.TextStyle {
        self == .compactCapsule ? .footnote : .subheadline
    }
}

public struct LodestarPrimaryButton: View {
    public let title: String
    public let systemImage: String?
    public let isDisabled: Bool
    public let layout: LodestarPrimaryButtonLayout
    public let action: () -> Void

    public init(
        _ title: String,
        systemImage: String? = nil,
        isDisabled: Bool = false,
        layout: LodestarPrimaryButtonLayout = .standard,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isDisabled = isDisabled
        self.layout = layout
        self.action = action
    }

    @ViewBuilder
    public var body: some View {
        switch layout {
        case .standard:
            standardButton
        case .compactCapsule:
            compactButton
        }
    }

    private var standardButton: some View {
        Button(action: action) {
            label
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

    private var compactButton: some View {
        Button(action: action) {
            label
                .font(.system(layout.semanticTextStyle, weight: .semibold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.vertical, layout.verticalPadding)
                .frame(minHeight: LodestarPrimaryActionPolicy.height)
                .contentShape(.rect)
                .background(LodestarColor.textPrimary)
                .clipShape(Capsule())
        }
        .buttonStyle(LodestarPressableButtonStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .accessibilityLabel(Text(title))
    }

    private var label: some View {
        HStack(spacing: LodestarMetrics.spacingS) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
        }
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
