import XCTest
@testable import BrainKit

final class EaClientTests: XCTestCase {
    func testParsesDeltaFrame() {
        XCTAssertEqual(BrainClient.parseEaSseLine(#"data: {"delta":"Hel"}"#), .delta("Hel"))
    }
    func testParsesDoneFrame() {
        let ev = BrainClient.parseEaSseLine(#"data: {"done":true,"text":"Hello","error":null,"turnId":"t1"}"#)
        XCTAssertEqual(ev, .done(text: "Hello", error: nil, turnId: "t1"))
    }
    func testParsesErrorFrame() {
        XCTAssertEqual(BrainClient.parseEaSseLine(#"data: {"error":"boom"}"#), .error("boom"))
    }
    func testIgnoresNonDataAndMalformedLines() {
        XCTAssertNil(BrainClient.parseEaSseLine(""))
        XCTAssertNil(BrainClient.parseEaSseLine(": keepalive"))
        XCTAssertNil(BrainClient.parseEaSseLine("data: {not json"))
    }
}

final class EaClientRequestTests: XCTestCase {
    private func makeClient() -> BrainClient {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        return BrainClient(baseURL: URL(string: "http://mini:4317")!, token: "tok",
                           session: URLSession(configuration: cfg))
    }
    private func respond(status: Int, json: String) {
        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
             Data(json.utf8))
        }
    }
    override func tearDown() { MockURLProtocol.handler = nil; MockURLProtocol.lastRequest = nil }

    func testEaRenameThreadSendsPatch() async throws {
        respond(status: 200, json: #"{"ok":true}"#)
        try await makeClient().eaRenameThread(id: "abc-123", title: "Fiara")
        XCTAssertEqual(MockURLProtocol.lastRequest?.httpMethod, "PATCH")
        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.path, "/ea/threads/abc-123")
        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func testEaThreadsPassesQueryAndLimit() async throws {
        respond(status: 200, json: #"{"threads":[]}"#)
        _ = try await makeClient().eaThreads(q: "fiara", limit: 30)
        let comps = URLComponents(url: MockURLProtocol.lastRequest!.url!, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(comps.queryItems?.first(where: { $0.name == "q" })?.value, "fiara")
        XCTAssertEqual(comps.queryItems?.first(where: { $0.name == "limit" })?.value, "30")
    }

    func testEaThreadsOmitsQueryWhenNilKeepingLegacyShape() async throws {
        respond(status: 200, json: #"{"threads":[]}"#)
        _ = try await makeClient().eaThreads()
        XCTAssertNil(MockURLProtocol.lastRequest?.url?.query)
    }
}
