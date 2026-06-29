import XCTest
@testable import BrainKit

/// E2-2 — BrainClient.ingestLedger HTTP branches, mirroring IngestHealthTests. Uses MockURLProtocol +
/// XCTAssertThrowsErrorAsync from BrainClientTests (same target).
final class IngestLedgerTests: XCTestCase {
    private func makeClient() -> BrainClient {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        return BrainClient(baseURL: URL(string: "http://mini:4317")!, token: nil, session: URLSession(configuration: cfg))
    }

    private func respond(status: Int, json: String) {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (resp, json.data(using: .utf8)!)
        }
    }

    override func tearDown() { MockURLProtocol.handler = nil; MockURLProtocol.lastRequest = nil }

    private func sample() -> LedgerIngestPayload {
        LedgerIngestPayload(
            deviceId: "iphone-1", exportedAt: "2026-06-29T15:31:00.000Z", reason: "manual",
            snapshot: LedgerFinanceSnapshot(todayTotals: [:], monthTotals: [:], pendingCount: 0,
                                            latestTransaction: nil, sourceCounts: [:]),
            transactions: [])
    }

    func testIngestLedgerPostsToLedgerIngestWithIngestBearer() async throws {
        respond(status: 200, json: #"{"ok":true,"received":3,"snapshotAt":"2026-06-29T15:31:00.000Z"}"#)
        let outcome = try await makeClient().ingestLedger(sample(), ingestToken: "ing-tok")
        let req = MockURLProtocol.lastRequest
        XCTAssertEqual(req?.url?.path, "/core/personal-apps/ledger/ingest")
        XCTAssertEqual(req?.httpMethod, "POST")
        XCTAssertEqual(req?.value(forHTTPHeaderField: "Authorization"), "Bearer ing-tok")
        XCTAssertEqual(outcome, .accepted(received: 3))
    }

    func testIngestLedgerOkFalseIsDiscardedWithReason() async throws {
        respond(status: 200, json: #"{"ok":false,"error":"unsupported schemaVersion"}"#)
        let outcome = try await makeClient().ingestLedger(sample(), ingestToken: "t")
        XCTAssertEqual(outcome, .discarded(reason: "unsupported schemaVersion"))
    }

    func testIngestLedgerUnauthorizedThrows() async {
        respond(status: 401, json: "{}")
        await XCTAssertThrowsErrorAsync(try await makeClient().ingestLedger(sample(), ingestToken: "bad")) {
            XCTAssertEqual($0 as? BrainError, .unauthorized)
        }
    }

    func testIngestLedgerServerErrorThrows() async {
        respond(status: 503, json: "{}")
        await XCTAssertThrowsErrorAsync(try await makeClient().ingestLedger(sample(), ingestToken: "t")) {
            XCTAssertEqual($0 as? BrainError, .server(status: 503))
        }
    }

    func testIngestLedgerTransportFailureThrowsUnreachable() async {
        MockURLProtocol.handler = nil
        await XCTAssertThrowsErrorAsync(try await makeClient().ingestLedger(sample(), ingestToken: "t")) {
            XCTAssertEqual($0 as? BrainError, .unreachable)
        }
    }
}
