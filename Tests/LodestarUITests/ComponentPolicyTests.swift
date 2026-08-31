import SwiftUI
import XCTest
@testable import LodestarUI

final class ComponentPolicyTests: XCTestCase {
    func testPrimaryActionPolicyIsWhiteAndFortyFourPoints() {
        XCTAssertEqual(LodestarPrimaryActionPolicy.height, 44)
        XCTAssertEqual(LodestarPrimaryActionPolicy.radius, 10)
        XCTAssertEqual(LodestarPrimaryActionPolicy.fillRole, .primary)
    }

    func testCardPolicyUsesFamilyGeometry() {
        XCTAssertEqual(LodestarCardPolicy.inset, 14)
        XCTAssertEqual(LodestarCardPolicy.radius, 10)
        XCTAssertEqual(LodestarCardPolicy.borderWidth, 0.5)
    }

    func testSecondaryActionPolicyIsBorderedAndFortyFourPoints() {
        XCTAssertEqual(LodestarSecondaryActionPolicy.height, 44)
        XCTAssertEqual(LodestarSecondaryActionPolicy.radius, 10)
        XCTAssertEqual(LodestarSecondaryActionPolicy.fillRole, .neutral)
    }
}
