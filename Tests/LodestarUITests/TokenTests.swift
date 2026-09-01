import SwiftUI
import XCTest
@testable import LodestarUI

final class TokenTests: XCTestCase {
    private func assertHex(_ color: Color, _ hex: UInt32, file: StaticString = #filePath, line: UInt = #line) {
        let resolved = color.resolve(in: EnvironmentValues())

        XCTAssertEqual(Int((Double(resolved.red) * 255).rounded()), Int((hex >> 16) & 0xFF), file: file, line: line)
        XCTAssertEqual(Int((Double(resolved.green) * 255).rounded()), Int((hex >> 8) & 0xFF), file: file, line: line)
        XCTAssertEqual(Int((Double(resolved.blue) * 255).rounded()), Int(hex & 0xFF), file: file, line: line)
    }

    private func assertOpacity(
        _ color: Color,
        _ opacity: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let resolved = color.resolve(in: EnvironmentValues())
        XCTAssertEqual(Double(resolved.opacity), opacity, accuracy: 0.001, file: file, line: line)
    }

    func testTemperDerivedPaletteIsExact() {
        assertHex(LodestarColor.background, 0x000000)
        assertHex(LodestarColor.surface, 0x0D0D0E)
        assertHex(LodestarColor.surfaceRaised, 0x161617)
        assertHex(LodestarColor.border, 0x232324)
        assertHex(LodestarColor.textPrimary, 0xFAFAFA)
        assertHex(LodestarColor.textSecondary, 0xA1A1AA)
        assertHex(LodestarColor.textTertiary, 0x82828C)
        assertHex(LodestarColor.textMuted, 0x3F3F46)
        assertHex(LodestarColor.accent, 0xA78BFA)
        assertHex(LodestarColor.success, 0x38CF82)
        assertHex(LodestarColor.warning, 0xFF9F0A)
        assertHex(LodestarColor.danger, 0xEF4444)
    }

    func testElevatedSurfaceAndHairlineMatchTheReferenceRoles() {
        assertHex(LodestarColor.surfaceElevated, 0x0F0F10)
        assertHex(LodestarColor.hairline, 0xFFFFFF)
        assertOpacity(LodestarColor.hairline, 0.052)
    }

    func testFamilyMetricsAreExact() {
        XCTAssertEqual(LodestarMetrics.cardInset, 14)
        XCTAssertEqual(LodestarMetrics.radiusCard, 10)
        XCTAssertEqual(LodestarMetrics.radiusSheet, 16)
        XCTAssertEqual(LodestarMetrics.primaryControlHeight, 44)
    }
}
