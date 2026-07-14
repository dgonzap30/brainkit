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
