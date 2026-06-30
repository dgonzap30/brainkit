import XCTest
@testable import BrainKit

final class IngestTemperTests: XCTestCase {
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
    private func batch() -> TemperIngestRequest {
        TemperIngestRequest(deviceId: "d", exportedAt: "2026-06-29T18:00:00.000Z", reason: .observer,
                            workouts: [], foodDays: [], whoopDays: [])
    }

    func testPostsToTemperIngestWithIngestBearer() async throws {
        respond(status: 200, json: #"{"ok":true,"workouts":0,"foodDays":0,"whoopDays":0,"snapshotAt":"x"}"#)
        _ = try await makeClient(token: "fd").ingestTemper(batch(), ingestToken: "ingest-secret")
        let req = MockURLProtocol.lastRequest
        XCTAssertEqual(req?.url?.path, "/core/personal-apps/temper/ingest")
        XCTAssertEqual(req?.httpMethod, "POST")
        XCTAssertEqual(req?.value(forHTTPHeaderField: "Authorization"), "Bearer ingest-secret")
    }

    func testAcceptedMapsOkTrue() async throws {
        respond(status: 200, json: #"{"ok":true,"workouts":2,"foodDays":3,"whoopDays":1,"snapshotAt":"x"}"#)
        let out = try await makeClient(token: nil).ingestTemper(batch(), ingestToken: "t")
        XCTAssertEqual(out, .accepted(workouts: 2, foodDays: 3, whoopDays: 1))
    }

    func testDiscardedMapsOkFalse() async throws {
        respond(status: 200, json: #"{"ok":false,"rejected":"unsupported schemaVersion"}"#)
        let out = try await makeClient(token: nil).ingestTemper(batch(), ingestToken: "t")
        XCTAssertEqual(out, .discarded(reason: "unsupported schemaVersion"))
    }

    func testTransientServerErrorThrowsRetryable() async {
        respond(status: 503, json: #"{"ok":false,"error":"internal_error"}"#)
        await XCTAssertThrowsErrorAsync(try await makeClient(token: nil).ingestTemper(batch(), ingestToken: "t")) {
            XCTAssertEqual($0 as? BrainError, .server(status: 503))
        }
    }

    func testUnauthorizedThrows() async {
        respond(status: 401, json: #"{"error":"unauthorized"}"#)
        await XCTAssertThrowsErrorAsync(try await makeClient(token: nil).ingestTemper(batch(), ingestToken: "t")) {
            XCTAssertEqual($0 as? BrainError, .unauthorized)
        }
    }

    func testRateLimitedThrows() async {
        respond(status: 429, json: #"{"error":"rate_limited"}"#)
        await XCTAssertThrowsErrorAsync(try await makeClient(token: nil).ingestTemper(batch(), ingestToken: "t")) {
            XCTAssertEqual($0 as? BrainError, .rateLimited)
        }
    }

    func testMalformed200ThrowsDecoding() async {
        respond(status: 200, json: #"not-json"#)
        await XCTAssertThrowsErrorAsync(try await makeClient(token: nil).ingestTemper(batch(), ingestToken: "t")) {
            XCTAssertEqual($0 as? BrainError, .decoding)
        }
    }

    func testTransportFailureThrowsUnreachable() async {
        // Don't set a handler — MockURLProtocol will call didFailWithError, causing URLSession to throw
        MockURLProtocol.handler = nil
        await XCTAssertThrowsErrorAsync(try await makeClient(token: nil).ingestTemper(batch(), ingestToken: "t")) {
            XCTAssertEqual($0 as? BrainError, .unreachable)
        }
    }
}
