import SwiftUI

public enum LodestarMotion {
    public static let fast = Animation.easeOut(duration: 0.12)
    public static let standard = Animation.easeOut(duration: 0.20)
    public static let entrance = Animation.spring(response: 0.30, dampingFraction: 0.80)

    public static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}
