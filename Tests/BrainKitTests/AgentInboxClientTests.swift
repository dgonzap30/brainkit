import XCTest
@testable import BrainKit

final class AgentInboxClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        MockURLProtocol.lastRequest = nil
    }

    // MARK: Review capability on the wire
    //
    // The brain 403s ANY decision on an exec candidate that arrives without Review authority
    // (`brain/src/core/http.ts`, `(decision === "approved" || isExec) && !hasReviewAuthority`).
    // Exec-ness is server-side state the client cannot see, so the header has to ride every
    // decision — gating it on `decision == "approved"` 403s every dismiss/steer of an exec item.

    private func makeClient(reviewCapability: String?) -> BrainClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return BrainClient(
            baseURL: URL(string: "http://mini:4317")!,
            token: "front-door",
            reviewCapability: reviewCapability,
            session: URLSession(configuration: config)
        )
    }

    private func respondOK() {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(#"{"ok":true}"#.utf8))
        }
    }

    func testEveryDecisionSendsScopedReviewCapabilityAlongsideFrontDoorBearer() async throws {
        respondOK()
        let client = makeClient(reviewCapability: "review-only")

        for decision in ["approved", "dismissed", "steered"] {
            _ = try await client.decideAgentInboxItem(
                id: "candidate",
                decision: decision,
                actor: "forged"
            )
            XCTAssertEqual(
                MockURLProtocol.lastRequest?.url?.path,
                "/core/agent/inbox/decide",
                "decision \(decision)"
            )
            XCTAssertEqual(
                MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "X-Lodestar-Review-Capability"),
                "review-only",
                "decision \(decision) must carry Review authority — the gate keys off the item's exec-ness"
            )
            // The capability is ADDITIONAL to the front-door bearer, never a replacement.
            XCTAssertEqual(
                MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"),
                "Bearer front-door",
                "decision \(decision)"
            )
        }
    }

    func testDecideOmitsReviewCapabilityWhenUnset() async throws {
        respondOK()
        _ = try await makeClient(reviewCapability: nil).decideAgentInboxItem(
            id: "candidate",
            decision: "dismissed",
            actor: "forged"
        )
        XCTAssertNil(
            MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "X-Lodestar-Review-Capability")
        )
    }

    /// An empty/whitespace Keychain string behaves like "unset" — never an empty header the brain
    /// would have to reject as malformed.
    func testDecideTreatsBlankReviewCapabilityAsUnset() async throws {
        respondOK()
        _ = try await makeClient(reviewCapability: " \n ").decideAgentInboxItem(
            id: "candidate",
            decision: "approved",
            actor: "forged"
        )
        XCTAssertNil(
            MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "X-Lodestar-Review-Capability")
        )
    }

    /// /execute has no Review gate server-side — the capability must not be sprayed at routes that
    /// do not check it.
    func testExecuteDoesNotSendReviewCapability() async throws {
        respondOK()
        _ = try await makeClient(reviewCapability: "review-only").executeAgentInboxItem(
            id: "candidate",
            actor: "diego"
        )
        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.path, "/core/agent/inbox/execute")
        XCTAssertNil(
            MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "X-Lodestar-Review-Capability")
        )
        XCTAssertEqual(
            MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"),
            "Bearer front-door"
        )
    }

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

    func testDecodesSteerRevisionFieldsAndPayload() throws {
        let json = """
        {"items":[{"id":"rev:c1","kind":"memory","text":"Short","status":"proposed","confidence":0.7,
          "observedAt":"2026-07-20T12:00:00.000Z","revisesId":"c1","steerNote":"shorter","revisionMode":"model",
          "writePlan":{"id":"wp:rev:c1","appId":"lodestar-core","environment":"personal-local","target":"observations",
                       "operation":"insert","mode":"life","rows":1,"payload":{"text":"Short","n":2}}}]}
        """.data(using: .utf8)!
        let items = BrainClient.decodeAgentInboxList(json)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].revisesId, "c1")
        XCTAssertEqual(items[0].steerNote, "shorter")
        XCTAssertEqual(items[0].revisionMode, "model")
        XCTAssertEqual(items[0].writePlan?.target, "observations")
        XCTAssertEqual(items[0].writePlan?.payload["text"], .string("Short"))
        XCTAssertEqual(items[0].writePlan?.payload["n"], .number(2))
    }

    func testLegacyItemsWithoutNewFieldsStillDecode() throws {
        let json = """
        {"items":[{"id":"c2","kind":"task","text":"T","status":"proposed","confidence":0.5,
          "observedAt":"2026-07-20T12:00:00.000Z",
          "writePlan":{"id":"wp:c2","appId":"lockin","environment":"personal-local","target":"tasks",
                       "operation":"upsert","mode":"work","rows":1}}]}
        """.data(using: .utf8)!
        let items = BrainClient.decodeAgentInboxList(json)
        XCTAssertEqual(items.count, 1)
        XCTAssertNil(items[0].revisesId)
        XCTAssertEqual(items[0].writePlan?.payload, [:])
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
