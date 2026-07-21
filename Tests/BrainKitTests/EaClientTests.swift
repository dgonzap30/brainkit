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

    func testEaThreadDecodesWithAndWithoutPreview() throws {
        let with = Data(#"{"id":"t1","title":"Taco","status":"active","createdAt":"2026-07-16T12:00:00.000Z","updatedAt":"2026-07-16T12:00:00.000Z","preview":"logged $45"}"#.utf8)
        let without = Data(#"{"id":"t2","title":"New thread","status":"active","createdAt":"c","updatedAt":"u"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(EaThread.self, from: with).preview, "logged $45")
        XCTAssertNil(try JSONDecoder().decode(EaThread.self, from: without).preview)
    }

    func testEaTurnDTODecodesAttachments() throws {
        let json = #"{"id":"t1","role":"user","content":"look","error":null,"createdAt":"2026-07-20","attachments":[{"id":"a1","width":100,"height":50}]}"#
        let dto = try JSONDecoder().decode(EaTurnDTO.self, from: Data(json.utf8))
        XCTAssertEqual(dto.attachments, [AttachmentRef(id: "a1", width: 100, height: 50)])
    }

    func testEaTurnDTODecodesWithoutAttachments() throws {
        let json = #"{"id":"t1","role":"user","content":"hi","error":null,"createdAt":"2026-07-20"}"#
        XCTAssertNil(try JSONDecoder().decode(EaTurnDTO.self, from: Data(json.utf8)).attachments)
    }

    func testEaUploadAttachmentPostsJpegBytesAndDecodesRef() async throws {
        respond(status: 200, json: #"{"id":"a1","width":100,"height":50}"#)
        let ref = try await makeClient().eaUploadAttachment(jpegData: Data([0xFF, 0xD8, 0xFF]))
        XCTAssertEqual(ref, AttachmentRef(id: "a1", width: 100, height: 50))
        XCTAssertEqual(MockURLProtocol.lastRequest?.httpMethod, "POST")
        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.path, "/ea/attachments")
        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Content-Type"), "image/jpeg")
    }

    func testEaAttachmentDataGetsRawBytes() async throws {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0x01])
        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, jpeg)
        }
        let data = try await makeClient().eaAttachmentData(id: "a1")
        XCTAssertEqual(data, jpeg)
        XCTAssertEqual(MockURLProtocol.lastRequest?.httpMethod, "GET")
        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.path, "/ea/attachments/a1")
    }
}
