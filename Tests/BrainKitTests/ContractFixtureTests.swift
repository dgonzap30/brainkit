import XCTest
@testable import BrainKit

/// E2-6 — the Swift half of the wire-contract drift gate. Decodes the CANONICAL golden fixtures (the
/// same files the brain vendors byte-for-byte) through the BrainKit DTOs and asserts the values
/// round-trip. With brain/src/contract.test.ts this proves both languages agree on health.v1 / ledger.v1:
/// if a field is renamed/retyped on the Swift side without a version bump, decoding the frozen fixture
/// breaks here. Fixtures are read by #filePath-relative path — a dev-time gate, never shipped in a bundle.
final class ContractFixtureTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()    // Tests/BrainKitTests
            .deletingLastPathComponent()    // Tests
            .deletingLastPathComponent()    // <package root>
        return try Data(contentsOf: packageRoot.appendingPathComponent("Contract/fixtures/\(name)"))
    }

    func testHealthV1FixtureDecodesThroughBrainKit() throws {
        let req = try JSONDecoder().decode(HealthIngestRequest.self, from: fixture("health.v1.json"))
        XCTAssertEqual(req.schemaVersion, "health.v1")
        XCTAssertEqual(req.deviceId, "iphone-15-pro")
        XCTAssertEqual(req.reason, .observer)
        XCTAssertEqual(req.days.count, 1)
        XCTAssertEqual(req.days.first?.day, "2026-06-28")
        XCTAssertEqual(req.days.first?.steps, 9420)
        XCTAssertEqual(req.days.first?.sleep?.durationMin, 451)
        XCTAssertEqual(req.days.first?.vo2Max, 48)            // integer-valued double decodes fine
        XCTAssertEqual(req.workouts.count, 1)
        XCTAssertEqual(req.workouts.first?.type, "running")
        XCTAssertEqual(req.workouts.first?.durationMin, 32)
    }

    func testLedgerV1FixtureDecodesThroughBrainKit() throws {
        let payload = try JSONDecoder().decode(LedgerIngestPayload.self, from: fixture("ledger.v1.json"))
        XCTAssertEqual(payload.schemaVersion, "ledger.v1")
        XCTAssertEqual(payload.deviceId, "iphone-15-pro")
        XCTAssertEqual(payload.transactions.count, 2)
        XCTAssertEqual(payload.transactions.first?.merchant, "Blue Bottle")
        XCTAssertEqual(payload.transactions.first?.amount, 5.4)
        XCTAssertEqual(payload.transactions.first?.id, UUID(uuidString: "A1B2C3D4-E5F6-7788-99AA-BBCCDDEEFF00"))
        XCTAssertTrue(payload.transactions[1].pending)
        XCTAssertEqual(payload.transactions[1].currency, "MXN")
        XCTAssertFalse(payload.transactions[1].declined)
        XCTAssertEqual(payload.snapshot.pendingCount, 1)
        XCTAssertEqual(payload.snapshot.latestTransaction?.merchant, "Blue Bottle")
        XCTAssertEqual(payload.snapshot.todayTotals["USD"], 47.2)
    }

    func testTemperV1FixtureDecodesThroughBrainKit() throws {
        let req = try JSONDecoder().decode(TemperIngestRequest.self, from: fixture("temper.v1.json"))
        XCTAssertEqual(req.schemaVersion, "temper.v1")
        XCTAssertEqual(req.deviceId, "iphone-17-pro")
        XCTAssertEqual(req.reason, .observer)
        XCTAssertEqual(req.workouts.count, 1)
        XCTAssertEqual(req.workouts.first?.workoutId, "hk-1")
        XCTAssertEqual(req.workouts.first?.whoopStrain, 14.3)
        XCTAssertEqual(req.foodDays.count, 1)
        XCTAssertEqual(req.foodDays.first?.totalCalories, 2100)
        XCTAssertEqual(req.whoopDays.count, 1)
        XCTAssertEqual(req.whoopDays.first?.recoveryScore, 66)
    }

    func testConnectorV1FixtureDecodesThroughBrainKit() throws {
        let rec = try JSONDecoder().decode(ConnectorRecord.self, from: fixture("connector.v1.json"))
        XCTAssertEqual(rec.schemaVersion, "connector.v1")
        XCTAssertEqual(rec.executionId, "exec:7f1c0a9e-2b3d-4c5e-8a9b-0c1d2e3f4a5b")
        XCTAssertEqual(rec.itemId, "cand:9a8b7c6d")
        XCTAssertEqual(rec.writePlanId, "wp:1e2d3c4b")
        XCTAssertEqual(rec.appId, "lockin")
        XCTAssertEqual(rec.environment, "personal-local")
        XCTAssertEqual(rec.target, "tasks")
        XCTAssertEqual(rec.operation, "upsert")
        XCTAssertEqual(rec.mode, "work")
        XCTAssertEqual(rec.actor, "diego")
        XCTAssertEqual(rec.executedAt, "2026-06-29T15:31:00.000Z")
        XCTAssertEqual(rec.payload["text"], .string("Task: send the Rocio finance request today"))
        XCTAssertEqual(rec.approval.status, "approved")
        XCTAssertEqual(rec.approval.actor, "diego")
        XCTAssertEqual(rec.approval.decidedAt, "2026-06-29T15:30:00.000Z")
        XCTAssertNil(rec.approval.reason)                                  // null reason -> nil
        XCTAssertEqual(rec.rollback.type, "append-only")
        XCTAssertEqual(rec.rollback.outboxPath, "/core/personal-app-outbox/lockin/tasks.jsonl")
        XCTAssertEqual(rec.rollback.removeExecutionId, rec.executionId)
    }

    /// Re-encoding a decoded fixture and decoding again must be lossless — proves the BrainKit DTOs are
    /// a faithful representation of the on-wire shape (no field silently dropped on the round trip).
    func testFixturesRoundTripLosslessly() throws {
        let req = try JSONDecoder().decode(HealthIngestRequest.self, from: fixture("health.v1.json"))
        let req2 = try JSONDecoder().decode(HealthIngestRequest.self, from: JSONEncoder().encode(req))
        XCTAssertEqual(req, req2)
        let pay = try JSONDecoder().decode(LedgerIngestPayload.self, from: fixture("ledger.v1.json"))
        let pay2 = try JSONDecoder().decode(LedgerIngestPayload.self, from: JSONEncoder().encode(pay))
        XCTAssertEqual(pay, pay2)
        let rec = try JSONDecoder().decode(ConnectorRecord.self, from: fixture("connector.v1.json"))
        let rec2 = try JSONDecoder().decode(ConnectorRecord.self, from: JSONEncoder().encode(rec))
        XCTAssertEqual(rec, rec2)
        let temper = try JSONDecoder().decode(TemperIngestRequest.self, from: fixture("temper.v1.json"))
        let temper2 = try JSONDecoder().decode(TemperIngestRequest.self, from: JSONEncoder().encode(temper))
        XCTAssertEqual(temper, temper2)
    }
}
