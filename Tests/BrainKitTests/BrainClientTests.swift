import XCTest
@testable import BrainKit

/// Intercepts URLSession requests so we can assert request shape and return canned responses.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastRequest = request
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        let (resp, data) = handler(request)
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class BrainClientTests: XCTestCase {
    private func makeClient(token: String?) -> BrainClient {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: cfg)
        return BrainClient(baseURL: URL(string: "http://mini:4317")!, token: token, session: session)
    }

    private func respond(status: Int, json: String) {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (resp, json.data(using: .utf8)!)
        }
    }

    override func tearDown() { MockURLProtocol.handler = nil; MockURLProtocol.lastRequest = nil }

    func testFrontDoorSendsBearerAndPostsToFrontDoor() async throws {
        respond(status: 200, json: #"{"kind":"capture","action":"captured","formatted":"ok"}"#)
        _ = try await makeClient(token: "tok123").frontDoor(text: "hi", mode: .auto)
        let req = MockURLProtocol.lastRequest
        XCTAssertEqual(req?.url?.path, "/front-door")
        XCTAssertEqual(req?.httpMethod, "POST")
        XCTAssertEqual(req?.value(forHTTPHeaderField: "Authorization"), "Bearer tok123")
    }

    func testFrontDoorOmitsBearerWhenTokenNil() async throws {
        respond(status: 200, json: #"{"kind":"capture"}"#)
        _ = try await makeClient(token: nil).frontDoor(text: "hi", mode: .auto)
        XCTAssertNil(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"))
    }

    func testFrontDoorDecodesCapture() async throws {
        respond(status: 200, json: #"{"kind":"capture","action":"captured","surface":"body","formatted":"✓ body"}"#)
        let r = try await makeClient(token: "t").frontDoor(text: "ran 8mi", mode: .auto)
        XCTAssertEqual(r.kind, "capture")
        XCTAssertEqual(r.surface, "body")
    }

    func testUnauthorizedMapsToBrainError() async {
        respond(status: 401, json: #"{"error":"unauthorized"}"#)
        await XCTAssertThrowsErrorAsync(try await makeClient(token: "bad").frontDoor(text: "x", mode: .auto)) {
            XCTAssertEqual($0 as? BrainError, .unauthorized)
        }
    }

    func testRateLimitedMapsToBrainError() async {
        respond(status: 429, json: #"{"error":"rate limited","code":"rate_limited"}"#)
        await XCTAssertThrowsErrorAsync(try await makeClient(token: "t").frontDoor(text: "x", mode: .auto)) {
            XCTAssertEqual($0 as? BrainError, .rateLimited)
        }
    }

    func testServerErrorMapsToBrainError() async {
        respond(status: 500, json: #"{"error":"front-door failed"}"#)
        await XCTAssertThrowsErrorAsync(try await makeClient(token: "t").frontDoor(text: "x", mode: .auto)) {
            XCTAssertEqual($0 as? BrainError, .server(status: 500))
        }
    }

    func testBadJSONMapsToDecoding() async {
        respond(status: 200, json: "not json")
        await XCTAssertThrowsErrorAsync(try await makeClient(token: "t").frontDoor(text: "x", mode: .auto)) {
            XCTAssertEqual($0 as? BrainError, .decoding)
        }
    }

    func testHealthTrueOn200() async {
        respond(status: 200, json: #"{"ok":true}"#)
        let ok = await makeClient(token: "t").health()
        XCTAssertTrue(ok)
    }

    func testHealthFalseOn500() async {
        respond(status: 500, json: "{}")
        let ok = await makeClient(token: "t").health()
        XCTAssertFalse(ok)
    }
}

extension BrainClientTests {
    func testFrontDoorWithHistoryPostsAndDecodes() async throws {
        respond(status: 200, json: #"{"kind":"ask","action":"answered","answer":"ok"}"#)
        let r = try await makeClient(token: "t").frontDoor(
            text: "and tomorrow?", mode: .ask,
            history: [HistoryTurn(role: "user", text: "readiness today?")])
        XCTAssertEqual(r.kind, "ask")
        XCTAssertEqual(r.answer, "ok")
        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.path, "/front-door")
        XCTAssertEqual(MockURLProtocol.lastRequest?.httpMethod, "POST")
    }
}

/// Async throwing-assertion helper (XCTAssertThrowsError has no async overload).
func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void,
    file: StaticString = #filePath, line: UInt = #line
) async {
    do { _ = try await expression(); XCTFail("expected throw", file: file, line: line) }
    catch { errorHandler(error) }
}
