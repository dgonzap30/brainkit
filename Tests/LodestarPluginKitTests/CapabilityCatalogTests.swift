import XCTest
@testable import LodestarPluginKit

final class CapabilityCatalogTests: XCTestCase {
    func testReportBodyMatchesBrainContract() throws {
        let checked = ISO8601DateFormatter().date(from: "2026-07-09T20:00:00Z")!
        let body = makeCapabilityReportBody(app: "ledger", entries: [
            .init(id: "sms-channel", title: "SMS capture", status: .actionNeeded, checkedAt: checked),
        ])
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(obj["app"] as? String, "ledger")
        let caps = try XCTUnwrap(obj["capabilities"] as? [[String: Any]])
        XCTAssertEqual(caps.first?["status"] as? String, "action-needed")
        XCTAssertEqual(caps.first?["id"] as? String, "sms-channel")
        XCTAssertNotNil(caps.first?["checkedAt"] as? String)
    }
    func testStatusRawValuesArePinned() {
        XCTAssertEqual(CapabilityStatus.actionNeeded.rawValue, "action-needed")
        XCTAssertEqual(CapabilityStatus.ok.rawValue, "ok")
    }
    func testHeardFromWindowIsSevenDays() {
        XCTAssertEqual(heardFromWindowDays, 7)
    }
}
