import XCTest
import SwiftUI
@testable import LodestarUI

/// U1 §tokens — the OLED ramp and status hues are the suite-wide contract
/// (canonical values standardized in the icon suite / LedgerColorTokens).
final class TokenTests: XCTestCase {
    private func rgba(_ c: Color) -> (r: Double, g: Double, b: Double) {
        let resolved = c.resolve(in: EnvironmentValues())
        return (Double(resolved.red), Double(resolved.green), Double(resolved.blue))
    }

    func testSurfaceRampIsPureBlackBased() {
        XCTAssertEqual(rgba(LodestarColor.bg).r, 0, accuracy: 0.001)
        XCTAssertEqual(rgba(LodestarColor.surface).r, 0.075, accuracy: 0.005)
        XCTAssertEqual(rgba(LodestarColor.elevated).r, 0.12, accuracy: 0.005)
        XCTAssertEqual(rgba(LodestarColor.border).r, 0.16, accuracy: 0.005)
        // monochrome: r == g == b on every surface token
        for token in [LodestarColor.surface, LodestarColor.elevated, LodestarColor.border] {
            let v = rgba(token)
            XCTAssertEqual(v.r, v.g, accuracy: 0.001)
            XCTAssertEqual(v.g, v.b, accuracy: 0.001)
        }
    }

    func testStatusHuesMatchSuitePalette() {
        // #22C55E / #F59E0B / #EF4444
        XCTAssertEqual(rgba(LodestarColor.statusOK).g, Double(0xC5) / 255, accuracy: 0.005)
        XCTAssertEqual(rgba(LodestarColor.statusWarn).r, Double(0xF5) / 255, accuracy: 0.005)
        XCTAssertEqual(rgba(LodestarColor.statusError).r, Double(0xEF) / 255, accuracy: 0.005)
    }

    func testMetricsScale() {
        XCTAssertEqual(LodestarMetrics.spacingXS, 4)
        XCTAssertEqual(LodestarMetrics.spacingS, 8)
        XCTAssertEqual(LodestarMetrics.spacingM, 12)
        XCTAssertEqual(LodestarMetrics.spacingL, 16)
        XCTAssertEqual(LodestarMetrics.spacingXL, 24)
        XCTAssertEqual(LodestarMetrics.radiusCard, 8)
        XCTAssertEqual(LodestarMetrics.radiusSheet, 12)
        XCTAssertEqual(LodestarMetrics.cardInset, 12)
    }
}
