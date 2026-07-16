import XCTest
@testable import LodestarUI

/// U1 §config-lock — the lock state machine. The four-quadrant matrix is the
/// spec's table: locked only when provisioned AND healthy AND not overridden.
final class LockedFieldStateTests: XCTestCase {
    func testProvisionedHealthyLocks() {
        XCTAssertEqual(LockedFieldState.resolve(provisioned: true, healthy: true, overridden: false), .locked)
    }
    func testOverrideBeatsLock() {
        XCTAssertEqual(LockedFieldState.resolve(provisioned: true, healthy: true, overridden: true), .overridden)
    }
    func testUnprovisionedStaysEditable() {
        XCTAssertEqual(LockedFieldState.resolve(provisioned: false, healthy: false, overridden: false), .editable)
        XCTAssertEqual(LockedFieldState.resolve(provisioned: false, healthy: true, overridden: false), .editable)
    }
    func testUnhealthyStaysEditable() {
        XCTAssertEqual(LockedFieldState.resolve(provisioned: true, healthy: false, overridden: false), .editable)
    }
    func testOverriddenSurvivesUnhealthy() {
        // The user's explicit override outranks health flapping — still shows Reset.
        XCTAssertEqual(LockedFieldState.resolve(provisioned: true, healthy: false, overridden: true), .overridden)
    }
}
