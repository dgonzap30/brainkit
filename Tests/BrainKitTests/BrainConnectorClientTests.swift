import XCTest
@testable import BrainKit

/// E2-1 — the connector-pull surface: BrainConnectorClient pulls a limb's approved write-outbox
/// from the brain. Reuses MockURLProtocol + XCTAssertThrowsErrorAsync from BrainClientTests (same
/// test target). Body decoding is lossy (malformed records dropped, never thrown); transport/auth
/// failures surface as typed BrainError.
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

    override func tearDown() { MockURLProtocol.handler = nil; MockURLProtocol.lastRequest = nil }

    // MARK: ConnectorRecord decode (canonical wire shape)

    func testConnectorRecordDecodesCanonicalShape() throws {
        let json = #"{"executionId":"exec:1","executedAt":"2026-06-26T18:00:00.000Z","payload":{"text":"Push leg day to Thursday"}}"#
        let r = try JSONDecoder().decode(ConnectorRecord.self, from: Data(json.utf8))
        XCTAssertEqual(r.executionId, "exec:1")
        XCTAssertEqual(r.executedAt, "2026-06-26T18:00:00.000Z")
        XCTAssertEqual(r.payload.text, "Push leg day to Thursday")
    }

    func testConnectorRecordDecodesWithoutExecutedAt() throws {
        let r = try JSONDecoder().decode(ConnectorRecord.self, from: Data(#"{"executionId":"e2","payload":{"text":"keep me"}}"#.utf8))
        XCTAssertNil(r.executedAt)
        XCTAssertEqual(r.payload.text, "keep me")
    }

    // MARK: pendingWrites — request shape + happy path

    func testPendingWritesSendsGetWithBearerToAppOutbox() async throws {
        respond(status: 200, json: #"{"records":[{"executionId":"e1","payload":{"text":"hi"}}]}"#)
        let records = try await makeClient(token: "tok123").pendingWrites(appId: "lockin")
        let req = MockURLProtocol.lastRequest
        XCTAssertEqual(req?.url?.path, "/core/personal-apps/lockin/outbox")
        XCTAssertEqual(req?.httpMethod, "GET")
        XCTAssertEqual(req?.value(forHTTPHeaderField: "Authorization"), "Bearer tok123")
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.executionId, "e1")
        XCTAssertEqual(records.first?.payload.text, "hi")
    }

    func testPendingWritesUsesAppIdInPath() async throws {
        respond(status: 200, json: #"{"records":[]}"#)
        _ = try await makeClient(token: "t").pendingWrites(appId: "ledger")
        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.path, "/core/personal-apps/ledger/outbox")
    }

    func testPendingWritesOmitsBearerWhenTokenNil() async throws {
        respond(status: 200, json: #"{"records":[]}"#)
        _ = try await makeClient(token: nil).pendingWrites(appId: "lockin")
        XCTAssertNil(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"))
    }

    // MARK: pendingWrites — lossy body robustness (never throws on a bad record / bad 200 body)

    func testPendingWritesDropsMalformedRecordsNeverThrows() async throws {
        respond(status: 200, json: #"{"records":[{"executionId":"e1","payload":{"text":"keep"}},{"executionId":"e2","payload":{}},{"garbage":true}]}"#)
        let records = try await makeClient(token: "t").pendingWrites(appId: "lockin")
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.executionId, "e1")
    }

    func testPendingWritesGarbageBodyReturnsEmpty() async throws {
        respond(status: 200, json: "not json")
        let records = try await makeClient(token: "t").pendingWrites(appId: "lockin")
        XCTAssertTrue(records.isEmpty)
    }

    // MARK: pendingWrites — transport/auth/server failures surface as typed BrainError

    func testTransportFailureMapsToUnreachable() async {
        MockURLProtocol.handler = nil // no handler → URLProtocol fails the request
        await XCTAssertThrowsErrorAsync(try await makeClient(token: "t").pendingWrites(appId: "lockin")) {
            XCTAssertEqual($0 as? BrainError, .unreachable)
        }
    }

    func testUnauthorizedMapsToBrainError() async {
        respond(status: 401, json: #"{"error":"unauthorized"}"#)
        await XCTAssertThrowsErrorAsync(try await makeClient(token: "bad").pendingWrites(appId: "lockin")) {
            XCTAssertEqual($0 as? BrainError, .unauthorized)
        }
    }

    func testRateLimitedMapsToBrainError() async {
        respond(status: 429, json: "{}")
        await XCTAssertThrowsErrorAsync(try await makeClient(token: "t").pendingWrites(appId: "lockin")) {
            XCTAssertEqual($0 as? BrainError, .rateLimited)
        }
    }

    func testServerErrorMapsToBrainError() async {
        respond(status: 503, json: "{}")
        await XCTAssertThrowsErrorAsync(try await makeClient(token: "t").pendingWrites(appId: "lockin")) {
            XCTAssertEqual($0 as? BrainError, .server(status: 503))
        }
    }
}
