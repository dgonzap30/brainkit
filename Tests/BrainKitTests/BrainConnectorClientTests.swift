import XCTest
@testable import BrainKit

/// The connector-pull surface: BrainConnectorClient pulls a limb's approved write-outbox from the
/// brain. Reuses MockURLProtocol + XCTAssertThrowsErrorAsync from BrainClientTests (same test target).
/// Body decoding is lossy (malformed records dropped, never thrown); transport/auth failures surface
/// as typed BrainError. Records are full connector.v1 envelopes (E3-4).
final class BrainConnectorClientTests: XCTestCase {
    private func makeClient(token: String?) -> BrainConnectorClient {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: cfg)
        return BrainConnectorClient(baseURL: URL(string: "http://mini:4317")!, token: token, session: session)
    }

    private func respond(status: Int, json: String) {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (resp, json.data(using: .utf8)!)
        }
    }

    /// A complete connector.v1 record on the wire — only executionId/payload-text vary per test.
    private func record(executionId: String, text: String) -> String {
        """
        {"schemaVersion":"connector.v1","executionId":"\(executionId)","itemId":"cand:x","writePlanId":"wp:x","appId":"lockin","environment":"personal-local","target":"tasks","operation":"upsert","mode":"work","actor":"diego","executedAt":"2026-06-29T15:31:00.000Z","payload":{"text":"\(text)"},"approval":{"status":"approved","actor":"diego","decidedAt":"2026-06-29T15:30:00.000Z","reason":null},"rollback":{"type":"append-only","outboxPath":"/core/personal-app-outbox/lockin/tasks.jsonl","removeExecutionId":"\(executionId)"}}
        """
    }

    override func tearDown() { MockURLProtocol.handler = nil; MockURLProtocol.lastRequest = nil }

    // MARK: ConnectorRecord decode (full connector.v1 wire shape)

    func testConnectorRecordDecodesCanonicalShape() throws {
        let r = try JSONDecoder().decode(ConnectorRecord.self, from: Data(record(executionId: "exec:1", text: "Push leg day to Thursday").utf8))
        XCTAssertEqual(r.schemaVersion, "connector.v1")
        XCTAssertEqual(r.executionId, "exec:1")
        XCTAssertEqual(r.executedAt, "2026-06-29T15:31:00.000Z")
        XCTAssertEqual(r.payload["text"], .string("Push leg day to Thursday"))
        XCTAssertEqual(r.approval.status, "approved")
        XCTAssertEqual(r.rollback.removeExecutionId, "exec:1")
    }

    func testConnectorRecordDecodesNonNullApprovalReason() throws {
        let json = record(executionId: "exec:r", text: "x").replacingOccurrences(of: "\"reason\":null", with: "\"reason\":\"looks duplicated\"")
        let r = try JSONDecoder().decode(ConnectorRecord.self, from: Data(json.utf8))
        XCTAssertEqual(r.approval.reason, "looks duplicated")
    }

    func testConnectorRecordMissingRequiredFieldThrows() {
        // executedAt is required in connector.v1 (the brain always writes it) — absence must throw, not default.
        let json = #"{"schemaVersion":"connector.v1","executionId":"e","payload":{"text":"t"}}"#
        XCTAssertThrowsError(try JSONDecoder().decode(ConnectorRecord.self, from: Data(json.utf8)))
    }

    // MARK: pollOutbox — request shape + happy path

    func testPollOutboxSendsGetWithBearerToAppOutbox() async throws {
        respond(status: 200, json: #"{"records":[\#(record(executionId: "e1", text: "hi"))]}"#)
        let records = try await makeClient(token: "tok123").pollOutbox(appId: "lockin")
        let req = MockURLProtocol.lastRequest
        XCTAssertEqual(req?.url?.path, "/core/personal-apps/lockin/outbox")
        XCTAssertEqual(req?.httpMethod, "GET")
        XCTAssertEqual(req?.value(forHTTPHeaderField: "Authorization"), "Bearer tok123")
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.executionId, "e1")
        XCTAssertEqual(records.first?.payload["text"], .string("hi"))
    }

    func testPollOutboxUsesAppIdInPath() async throws {
        respond(status: 200, json: #"{"records":[]}"#)
        _ = try await makeClient(token: "t").pollOutbox(appId: "ledger")
        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.path, "/core/personal-apps/ledger/outbox")
    }

    func testPollOutboxOmitsBearerWhenTokenNil() async throws {
        respond(status: 200, json: #"{"records":[]}"#)
        _ = try await makeClient(token: nil).pollOutbox(appId: "lockin")
        XCTAssertNil(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"))
    }

    // MARK: pollOutbox — lossy body robustness (never throws on a bad record / bad 200 body)

    func testPollOutboxDropsMalformedRecordsNeverThrows() async throws {
        let good = record(executionId: "e1", text: "keep")
        respond(status: 200, json: #"{"records":[\#(good),{"executionId":"e2","payload":{}},{"garbage":true}]}"#)
        let records = try await makeClient(token: "t").pollOutbox(appId: "lockin")
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.executionId, "e1")
    }

    func testPollOutboxGarbageBodyReturnsEmpty() async throws {
        respond(status: 200, json: "not json")
        let records = try await makeClient(token: "t").pollOutbox(appId: "lockin")
        XCTAssertTrue(records.isEmpty)
    }

    // MARK: pollOutbox — transport/auth/server failures surface as typed BrainError

    func testTransportFailureMapsToUnreachable() async {
        MockURLProtocol.handler = nil // no handler → URLProtocol fails the request
        await XCTAssertThrowsErrorAsync(try await makeClient(token: "t").pollOutbox(appId: "lockin")) {
            XCTAssertEqual($0 as? BrainError, .unreachable)
        }
    }

    func testUnauthorizedMapsToBrainError() async {
        respond(status: 401, json: #"{"error":"unauthorized"}"#)
        await XCTAssertThrowsErrorAsync(try await makeClient(token: "bad").pollOutbox(appId: "lockin")) {
            XCTAssertEqual($0 as? BrainError, .unauthorized)
        }
    }

    func testRateLimitedMapsToBrainError() async {
        respond(status: 429, json: "{}")
        await XCTAssertThrowsErrorAsync(try await makeClient(token: "t").pollOutbox(appId: "lockin")) {
            XCTAssertEqual($0 as? BrainError, .rateLimited)
        }
    }

    func testServerErrorMapsToBrainError() async {
        respond(status: 503, json: "{}")
        await XCTAssertThrowsErrorAsync(try await makeClient(token: "t").pollOutbox(appId: "lockin")) {
            XCTAssertEqual($0 as? BrainError, .server(status: 503))
        }
    }
}
