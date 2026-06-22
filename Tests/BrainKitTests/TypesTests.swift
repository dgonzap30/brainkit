import XCTest
@testable import BrainKit

final class TypesTests: XCTestCase {
    func testRequestEncodesTextAndModeRawValue() throws {
        let data = try JSONEncoder().encode(FrontDoorRequest(text: "ran 8mi", mode: .auto))
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(obj?["text"] as? String, "ran 8mi")
        XCTAssertEqual(obj?["mode"] as? String, "auto")
    }

    func testCaptureResponseDecodesWithNulls() throws {
        let json = """
        {"kind":"capture","action":"captured","answer":null,"confidence":0.82,
         "surface":"body","destination":"body.daily","formatted":"✓ captured → body",
         "reviewId":null,"reason":"high confidence","cost":0.0}
        """.data(using: .utf8)!
        let r = try JSONDecoder().decode(FrontDoorResponse.self, from: json)
        XCTAssertEqual(r.kind, "capture")
        XCTAssertEqual(r.formatted, "✓ captured → body")
        XCTAssertEqual(r.surface, "body")
        XCTAssertNil(r.answer)
        XCTAssertEqual(r.confidence, 0.82)
    }

    func testAskResponseDecodes() throws {
        let json = """
        {"kind":"ask","action":"answered","answer":"caution — HRV down","confidence":1,
         "surface":null,"destination":null,"formatted":null,"reviewId":null,
         "reason":"answered","cost":0.01}
        """.data(using: .utf8)!
        let r = try JSONDecoder().decode(FrontDoorResponse.self, from: json)
        XCTAssertEqual(r.kind, "ask")
        XCTAssertEqual(r.answer, "caution — HRV down")
    }
}
