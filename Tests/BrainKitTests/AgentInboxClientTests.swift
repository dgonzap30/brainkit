import XCTest
@testable import BrainKit

final class AgentInboxClientTests: XCTestCase {
    func testDecodeInboxListDropsMalformedItemsAndKeepsWritePlan() {
        let json = Data("""
        {"items": [
          {"id":"i1","observationId":"o1","kind":"task","text":"Log $45 tacos","mode":null,
           "status":"proposed","evidenceState":"exact","staleReason":null,"confidence":0.92,
           "observedAt":"2026-07-16T18:00:00.000Z","agentId":"a1","surfaceId":null,
           "provenance":{"sourceId":null,"refId":null,"sourceRefStatus":null,"sourceRefLastSeenAt":null,"evidence":null},
           "writePlan":{"id":"wp1","appId":"ledger","environment":"prod","target":"transactions",
                        "operation":"append","mode":"rows","rows":1,"payload":{},
                        "decision":{"allowed":true},"dryRun":true},
           "latestDecision":null},
          {"totally":"malformed"}
        ]}
        """.utf8)
        let items = BrainClient.decodeAgentInboxList(json)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, "i1")
        XCTAssertEqual(items[0].kind, "task")
        XCTAssertEqual(items[0].writePlan?.appId, "ledger")
        XCTAssertEqual(items[0].writePlan?.rows, 1)
        XCTAssertEqual(items[0].confidence, 0.92, accuracy: 0.0001)
    }

    func testDecodeInboxListWithoutWritePlan() {
        let json = Data(#"{"items":[{"id":"i2","kind":"memory","text":"note","status":"proposed","confidence":0.5,"observedAt":"t","writePlan":null}]}"#.utf8)
        let items = BrainClient.decodeAgentInboxList(json)
        XCTAssertEqual(items.count, 1)
        XCTAssertNil(items[0].writePlan)
    }

    func testDecodeActionResultOkAndFailure() throws {
        let ok = Data(#"{"ok":true,"itemId":"i1","status":"approved","actionId":"a1","dryRun":true}"#.utf8)
        let bad = Data(#"{"ok":false,"code":"stale_item","message":"newer plan exists","dryRun":true}"#.utf8)
        let okResult = try JSONDecoder().decode(AgentInboxActionResult.self, from: ok)
        XCTAssertTrue(okResult.ok)
        XCTAssertNil(okResult.code)
        let badResult = try JSONDecoder().decode(AgentInboxActionResult.self, from: bad)
        XCTAssertFalse(badResult.ok)
        XCTAssertEqual(badResult.code, "stale_item")
        XCTAssertEqual(badResult.message, "newer plan exists")
    }
}
