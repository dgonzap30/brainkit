import XCTest
import SwiftUI
@testable import LodestarUI

/// Spec §error-handling: every status surface renders ok / warn / error / stale —
/// the kind→hue mapping is the load-bearing behavior (hue is reserved for status).
final class StatusPillTests: XCTestCase {
    private func rgba(_ c: Color) -> (r: Double, g: Double, b: Double) {
        let resolved = c.resolve(in: EnvironmentValues())
        return (Double(resolved.red), Double(resolved.green), Double(resolved.blue))
    }

    func testKindMapsToSemanticColor() {
        XCTAssertEqual(rgba(StatusPillKind.ok.color).g, rgba(LodestarColor.statusOK).g, accuracy: 0.001)
        XCTAssertEqual(rgba(StatusPillKind.warn.color).r, rgba(LodestarColor.statusWarn).r, accuracy: 0.001)
        XCTAssertEqual(rgba(StatusPillKind.error.color).r, rgba(LodestarColor.statusError).r, accuracy: 0.001)
    }

    func testStaleIsMonochromeNotAStatusHue() {
        let v = rgba(StatusPillKind.stale.color)
        XCTAssertEqual(v.r, v.g, accuracy: 0.001)
        XCTAssertEqual(v.g, v.b, accuracy: 0.001)
    }
}
