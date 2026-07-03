import XCTest
@testable import BrainKit

final class IngestRundownTests: XCTestCase {
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
    private func batch() -> RundownIngestRequest {
        RundownIngestRequest(deviceId: "d", exportedAt: "2026-07-03T18:00:00.000Z", reason: "manual",
                             takes: [], scripts: [])
    }

    func testPostsToRundownIngestWithIngestBearer() async throws {
        respond(status: 200, json: #"{"ok":true,"takes":0,"scripts":0}"#)
        _ = try await makeClient(token: "fd").ingestRundown(batch(), ingestToken: "ingest-secret")
        let req = MockURLProtocol.lastRequest
        XCTAssertEqual(req?.url?.path, "/core/personal-apps/rundown/ingest")
        XCTAssertEqual(req?.httpMethod, "POST")
        XCTAssertEqual(req?.value(forHTTPHeaderField: "Authorization"), "Bearer ingest-secret")
    }

    func testAcceptedMapsOkTrue() async throws {
        respond(status: 200, json: #"{"ok":true,"takes":2,"scripts":1}"#)
        let out = try await makeClient(token: nil).ingestRundown(batch(), ingestToken: "t")
        XCTAssertEqual(out, .accepted(takes: 2, scripts: 1))
    }

    func testDiscardedMapsOkFalse() async throws {
        respond(status: 200, json: #"{"ok":false,"rejected":"unsupported schemaVersion"}"#)
        let out = try await makeClient(token: nil).ingestRundown(batch(), ingestToken: "t")
        XCTAssertEqual(out, .discarded(reason: "unsupported schemaVersion"))
    }

    func testTransientServerErrorThrowsRetryable() async {
        respond(status: 503, json: #"{"ok":false,"error":"internal_error"}"#)
        await XCTAssertThrowsErrorAsync(try await makeClient(token: nil).ingestRundown(batch(), ingestToken: "t")) {
            XCTAssertEqual($0 as? BrainError, .server(status: 503))
        }
    }

    func testUnauthorizedThrows() async {
        respond(status: 401, json: #"{"error":"unauthorized"}"#)
        await XCTAssertThrowsErrorAsync(try await makeClient(token: nil).ingestRundown(batch(), ingestToken: "t")) {
            XCTAssertEqual($0 as? BrainError, .unauthorized)
        }
    }

    func testRateLimitedThrows() async {
        respond(status: 429, json: #"{"error":"rate_limited"}"#)
        await XCTAssertThrowsErrorAsync(try await makeClient(token: nil).ingestRundown(batch(), ingestToken: "t")) {
            XCTAssertEqual($0 as? BrainError, .rateLimited)
        }
    }

    func testMalformed200ThrowsDecoding() async {
        respond(status: 200, json: #"not-json"#)
        await XCTAssertThrowsErrorAsync(try await makeClient(token: nil).ingestRundown(batch(), ingestToken: "t")) {
            XCTAssertEqual($0 as? BrainError, .decoding)
        }
    }

    func testTransportFailureThrowsUnreachable() async {
        // Don't set a handler — MockURLProtocol will call didFailWithError, causing URLSession to throw
        MockURLProtocol.handler = nil
        await XCTAssertThrowsErrorAsync(try await makeClient(token: nil).ingestRundown(batch(), ingestToken: "t")) {
            XCTAssertEqual($0 as? BrainError, .unreachable)
        }
    }
}
