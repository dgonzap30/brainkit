import XCTest
@testable import BrainKit

final class RundownTypesTests: XCTestCase {
    func testSchemaVersionIsTheConstant() {
        let req = RundownIngestRequest(deviceId: "d", exportedAt: "2026-07-03T18:00:00.000Z",
                                       reason: "manual", takes: [], scripts: [])
        XCTAssertEqual(req.schemaVersion, "rundown.v1")
    }

    func testEncodeDecodeRoundTrip() throws {
        let req = RundownIngestRequest(
            deviceId: "mac-mini", exportedAt: "2026-07-03T18:00:00.000Z", reason: "manual",
            takes: [RundownTake(id: "TK-1", scriptId: "SC-1", fileName: "take-01.wav",
                                recordedAt: "2026-07-03T17:40:00.000Z", durationSec: 38.4,
                                picked: true, truncated: false)],
            scripts: [RundownScript(id: "SC-1", title: "UFC 311 preview", status: "recorded",
                                    durationSec: 42, pillar: "sports-analytics")])
        let data = try JSONEncoder().encode(req)
        let back = try JSONDecoder().decode(RundownIngestRequest.self, from: data)
        XCTAssertEqual(back, req)
        XCTAssertEqual(back.takes.first?.durationSec, 38.4)
        XCTAssertEqual(back.takes.first?.truncated, false)
        XCTAssertEqual(back.scripts.first?.pillar, "sports-analytics")
    }

    func testOptionalFieldsDecodeWhenAbsent() throws {
        let json = #"""
        {"schemaVersion":"rundown.v1","deviceId":"d","exportedAt":"2026-07-03T18:00:00.000Z","reason":"manual",
         "takes":[{"id":"TK-1","scriptId":"SC-1","fileName":"take-01.wav","recordedAt":"2026-07-03T17:40:00.000Z","durationSec":38.4,"picked":true}],
         "scripts":[{"id":"SC-1","title":"UFC 311 preview","status":"draft"}]}
        """#
        let req = try JSONDecoder().decode(RundownIngestRequest.self, from: json.data(using: .utf8)!)
        XCTAssertNil(req.takes.first?.truncated)
        XCTAssertNil(req.scripts.first?.durationSec)
        XCTAssertNil(req.scripts.first?.pillar)
    }

    func testOutcomeEquatable() {
        XCTAssertEqual(RundownIngestOutcome.accepted(takes: 1, scripts: 2),
                       .accepted(takes: 1, scripts: 2))
        XCTAssertNotEqual(RundownIngestOutcome.accepted(takes: 1, scripts: 0),
                          .discarded(reason: "x"))
    }

    /// Mirrors ContractFixtureTests' file-locating approach: decode the golden fixture by
    /// #filePath-relative path (a dev-time gate, never shipped in a bundle).
    func testRundownV1FixtureDecodesThroughBrainKit() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // Tests/BrainKitTests
            .deletingLastPathComponent()    // Tests
            .deletingLastPathComponent()    // <package root>
        let data = try Data(contentsOf: packageRoot.appendingPathComponent("Contract/fixtures/rundown.v1.json"))
        let req = try JSONDecoder().decode(RundownIngestRequest.self, from: data)
        XCTAssertEqual(req.schemaVersion, "rundown.v1")
        XCTAssertEqual(req.deviceId, "mac-mini")
        XCTAssertEqual(req.takes.count, 1)
        XCTAssertEqual(req.takes.first?.fileName, "take-01.wav")
        XCTAssertEqual(req.scripts.count, 1)
        XCTAssertEqual(req.scripts.first?.pillar, "sports-analytics")
    }
}
