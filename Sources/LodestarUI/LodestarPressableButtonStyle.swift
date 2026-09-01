import SwiftUI

public enum LodestarPressFeedbackPolicy {
    public static func scale(isPressed: Bool, reduceMotion: Bool) -> CGFloat {
        isPressed && !reduceMotion ? 0.97 : 1
    }

    public static func opacity(isPressed: Bool) -> Double {
        isPressed ? 0.9 : 1
    }

    public static func animation(reduceMotion: Bool) -> Animation? {
        LodestarMotion.resolved(LodestarMotion.press, reduceMotion: reduceMotion)
    }
}

public struct LodestarPressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(
                LodestarPressFeedbackPolicy.scale(
                    isPressed: configuration.isPressed,
                    reduceMotion: reduceMotion
                )
            )
            .opacity(LodestarPressFeedbackPolicy.opacity(isPressed: configuration.isPressed))
            .animation(
                LodestarPressFeedbackPolicy.animation(reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}
