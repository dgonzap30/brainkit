import XCTest
@testable import BrainKit

final class PairingTypesTests: XCTestCase {
    func testDecodesPairingConfigResponse() throws {
        let json = #"{"schemaVersion":1,"hosts":["http://a:4317","http://b:4317"],"newsroomBFFHost":"https://bff","token":{"value":"cur"},"ingestToken":{"value":"ing"},"authenticatedWith":"previous","apps":{}}"#
        let cfg = try JSONDecoder().decode(PairingConfig.self, from: Data(json.utf8))
        XCTAssertEqual(cfg.hosts, ["http://a:4317", "http://b:4317"])
        XCTAssertEqual(cfg.token.value, "cur")
        XCTAssertEqual(cfg.ingestToken?.value, "ing")
        XCTAssertEqual(cfg.authenticatedWith, "previous")
    }
    func testDecodesNullIngestToken() throws {
        let json = #"{"schemaVersion":1,"hosts":[],"newsroomBFFHost":null,"token":{"value":"cur"},"ingestToken":null,"authenticatedWith":"current","apps":{}}"#
        let cfg = try JSONDecoder().decode(PairingConfig.self, from: Data(json.utf8))
        XCTAssertNil(cfg.ingestToken)
        XCTAssertNil(cfg.newsroomBFFHost)
    }
}
