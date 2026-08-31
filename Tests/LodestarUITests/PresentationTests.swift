import XCTest
import SwiftUI
@testable import LodestarUI

final class PresentationTests: XCTestCase {
    func testPresentationToneMapsWithoutInventingMeaning() {
        XCTAssertEqual(LodestarPresentationTone.progress.colorRole, .neutral)
        XCTAssertEqual(LodestarPresentationTone.success.colorRole, .success)
        XCTAssertEqual(LodestarPresentationTone.warning.colorRole, .warning)
        XCTAssertEqual(LodestarPresentationTone.danger.colorRole, .danger)
        XCTAssertFalse(LodestarPresentationTone.progress.requiresAttention)
        XCTAssertTrue(LodestarPresentationTone.warning.requiresAttention)
    }

    func testReducedMotionRemovesSpatialAnimation() {
        XCTAssertNil(LodestarMotion.resolved(LodestarMotion.entrance, reduceMotion: true))
    }
}
