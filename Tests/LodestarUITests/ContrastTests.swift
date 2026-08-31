import SwiftUI
import XCTest
@testable import LodestarUI

final class ContrastTests: XCTestCase {
    private func contrastRatio(_ foreground: Color, _ background: Color) -> Double {
        func relativeLuminance(_ color: Color) -> Double {
            let resolved = color.resolve(in: EnvironmentValues())
            let channels = [resolved.red, resolved.green, resolved.blue].map { channel in
                let value = Double(channel)
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        }

        let foregroundLuminance = relativeLuminance(foreground)
        let backgroundLuminance = relativeLuminance(background)
        return (max(foregroundLuminance, backgroundLuminance) + 0.05) / (min(foregroundLuminance, backgroundLuminance) + 0.05)
    }

    func testReadableTokensMeetContrastRequirementOnFamilySurfaces() {
        let readableTokens: [(name: String, color: Color)] = [
            ("textPrimary", LodestarColor.textPrimary),
            ("textSecondary", LodestarColor.textSecondary),
            ("textTertiary", LodestarColor.textTertiary),
            ("accent", LodestarColor.accent),
            ("success", LodestarColor.success),
            ("warning", LodestarColor.warning),
            ("danger", LodestarColor.danger),
        ]
        let surfaces: [(name: String, color: Color)] = [
            ("background", LodestarColor.background),
            ("surface", LodestarColor.surface),
            ("surfaceRaised", LodestarColor.surfaceRaised),
        ]

        for token in readableTokens {
            for surface in surfaces {
                XCTAssertGreaterThanOrEqual(
                    contrastRatio(token.color, surface.color),
                    4.5,
                    "\\(token.name) must meet 4.5:1 on \\(surface.name)"
                )
            }
        }
    }
}
