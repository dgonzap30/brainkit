import XCTest
@testable import BrainKit

final class IngestHealthTests: XCTestCase {
    override func tearDown() { MockURLProtocol.handler = nil; MockURLProtocol.lastRequest = nil }

    private func makeClient(token: String?) -> BrainClient {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        return BrainClient(baseURL: URL(string: "http://mini:4317")!, token: token,
                           session: URLSession(configuration: cfg))
    }
    private func respond(status: Int, json: String) {
        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
             json.data(using: .utf8)!)
        }
    }
    private func batch() -> HealthIngestRequest {
        HealthIngestRequest(deviceId: "d", exportedAt: "2026-06-28T18:00:00.000Z", reason: .observer,
                            days: [HealthDaySummary(day: "2026-06-28", restingHeartRate: 51)], workouts: [])
    }

    func testPostsToHealthIngestWithIngestBearer() async throws {
        respond(status: 200, json: #"{"ok":true,"days":1,"workouts":0,"snapshotAt":"2026-06-28T18:00:00.000Z"}"#)
        // front-door token is "fd" but we pass a DIFFERENT ingest token — the request must carry the ingest one.
        _ = try await makeClient(token: "fd").ingestHealth(batch(), ingestToken: "ingest-secret")
        let req = MockURLProtocol.lastRequest
        XCTAssertEqual(req?.url?.path, "/core/personal-apps/health/ingest")
        XCTAssertEqual(req?.httpMethod, "POST")
        XCTAssertEqual(req?.value(forHTTPHeaderField: "Authorization"), "Bearer ingest-secret")
    }

    func testAcceptedMapsOkTrue() async throws {
        respond(status: 200, json: #"{"ok":true,"days":2,"workouts":3,"snapshotAt":"x"}"#)
        let out = try await makeClient(token: nil).ingestHealth(batch(), ingestToken: "t")
        XCTAssertEqual(out, .accepted(days: 2, workouts: 3))
    }

    func testDiscardedMapsOkFalse() async throws {
        respond(status: 200, json: #"{"ok":false,"rejected":"unsupported schemaVersion"}"#)
        let out = try await makeClient(token: nil).ingestHealth(batch(), ingestToken: "t")
        XCTAssertEqual(out, .discarded(reason: "unsupported schemaVersion"))
    }

    func testTransientServerErrorThrowsRetryable() async {
        respond(status: 503, json: #"{"ok":false,"error":"internal_error"}"#)
        await XCTAssertThrowsErrorAsync(try await makeClient(token: nil).ingestHealth(batch(), ingestToken: "t")) {
            XCTAssertEqual($0 as? BrainError, .server(status: 503))
        }
    }

    func testUnauthorizedThrows() async {
        respond(status: 401, json: #"{"error":"unauthorized"}"#)
        await XCTAssertThrowsErrorAsync(try await makeClient(token: nil).ingestHealth(batch(), ingestToken: "t")) {
            XCTAssertEqual($0 as? BrainError, .unauthorized)
        }
    }
}
