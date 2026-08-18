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

    // MARK: exec-approver credential on the wire
    //
    // The brain 403s an exec-candidate decision that arrives without `x-lodestar-approver`
    // (core/http.ts, /core/agent/inbox/decide). Reach never sent that header, so the next exec
    // approval would have failed with no audit trace. These pin the header onto the wire.

    private func makeClient(approverToken: String?) -> BrainClient {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        return BrainClient(baseURL: URL(string: "http://mini:4317")!, token: "fd-tok",
                           approverToken: approverToken, session: URLSession(configuration: cfg))
    }

    private func respondOK() {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(#"{"ok":true}"#.utf8))
        }
    }

    override func tearDown() { MockURLProtocol.handler = nil; MockURLProtocol.lastRequest = nil }

    func testDecideSendsApproverHeaderAlongsideFrontDoorBearer() async throws {
        respondOK()
        _ = try await makeClient(approverToken: "appr-tok")
            .decideAgentInboxItem(id: "cap:x", decision: "approved", actor: "diego")
        let req = MockURLProtocol.lastRequest
        XCTAssertEqual(req?.url?.path, "/core/agent/inbox/decide")
        XCTAssertEqual(req?.value(forHTTPHeaderField: "x-lodestar-approver"), "Bearer appr-tok")
        // The approver credential is ADDITIONAL to the front-door bearer, never a replacement.
        XCTAssertEqual(req?.value(forHTTPHeaderField: "Authorization"), "Bearer fd-tok")
    }

    func testDecideOmitsApproverHeaderWhenUnset() async throws {
        respondOK()
        _ = try await makeClient(approverToken: nil)
            .decideAgentInboxItem(id: "cap:x", decision: "dismissed", actor: "diego")
        XCTAssertNil(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "x-lodestar-approver"))
    }

    /// An empty Keychain string must behave like "unset", not send `Bearer ` with nothing after it.
    func testDecideTreatsEmptyApproverTokenAsUnset() async throws {
        respondOK()
        _ = try await makeClient(approverToken: "")
            .decideAgentInboxItem(id: "cap:x", decision: "approved", actor: "diego")
        XCTAssertNil(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "x-lodestar-approver"))
    }

    /// /execute has no approver gate server-side — the secret must not be sprayed at routes that
    /// do not check it.
    func testExecuteDoesNotSendApproverHeader() async throws {
        respondOK()
        _ = try await makeClient(approverToken: "appr-tok")
            .executeAgentInboxItem(id: "cap:x", actor: "diego")
        let req = MockURLProtocol.lastRequest
        XCTAssertEqual(req?.url?.path, "/core/agent/inbox/execute")
        XCTAssertNil(req?.value(forHTTPHeaderField: "x-lodestar-approver"))
        XCTAssertEqual(req?.value(forHTTPHeaderField: "Authorization"), "Bearer fd-tok")
    }
}
