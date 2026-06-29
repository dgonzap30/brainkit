import XCTest
@testable import BrainKit

/// E2-2 — ledger.v1 wire DTOs lifted into BrainKit. Dates are wire strings (the brain validator
/// requires `exportedAt`/`timestamp` to be strings; a plain JSONEncoder would encode Date as a
/// number), so a plain encoder produces brain-valid JSON with no date strategy — same as HealthTypes.
final class LedgerTypesTests: XCTestCase {
    private func sampleTxn() -> LedgerBridgeTransaction {
        LedgerBridgeTransaction(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            dedupeKey: "amex-2026-06-29-blue-bottle-540",
            timestamp: "2026-06-29T15:30:00.000Z",
            amount: 5.40, currency: "USD", merchant: "Blue Bottle",
            cardName: "Amex Centurion", source: "applePay", pending: false, declined: false)
    }

    func testLedgerIngestPayloadRoundTripsLosslesslyAndPinsSchemaVersion() throws {
        let txn = sampleTxn()
        let payload = LedgerIngestPayload(
            deviceId: "iphone-1", exportedAt: "2026-06-29T15:31:00.000Z", reason: "transaction",
            snapshot: LedgerFinanceSnapshot(
                todayTotals: ["USD": 47.0], monthTotals: ["USD": 1203.55],
                pendingCount: 1, latestTransaction: txn, sourceCounts: ["applePay": 12]),
            transactions: [txn])

        XCTAssertEqual(payload.schemaVersion, "ledger.v1")
        let data = try JSONEncoder().encode(payload)
        let back = try JSONDecoder().decode(LedgerIngestPayload.self, from: data)
        XCTAssertEqual(back, payload)                // lossless
        XCTAssertEqual(back.schemaVersion, "ledger.v1")
    }

    func testEncodedJSONCarriesTheWireKeysAndTypesTheBrainValidatorRequires() throws {
        let payload = LedgerIngestPayload(
            deviceId: "iphone-1", exportedAt: "2026-06-29T15:31:00.000Z", reason: "manual",
            snapshot: LedgerFinanceSnapshot(todayTotals: [:], monthTotals: [:], pendingCount: 0,
                                            latestTransaction: nil, sourceCounts: [:]),
            transactions: [sampleTxn()])
        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as! [String: Any]
        XCTAssertEqual(obj["schemaVersion"] as? String, "ledger.v1")            // brain rejects anything else
        XCTAssertEqual(obj["deviceId"] as? String, "iphone-1")
        XCTAssertEqual(obj["exportedAt"] as? String, "2026-06-29T15:31:00.000Z") // string, NOT a number
        XCTAssertNotNil(obj["snapshot"] as? [String: Any])
        XCTAssertNotNil(obj["transactions"] as? [Any])
        let txn0 = (obj["transactions"] as? [[String: Any]])?.first
        XCTAssertEqual(txn0?["timestamp"] as? String, "2026-06-29T15:30:00.000Z") // string, NOT a number
        XCTAssertNotNil(txn0?["id"] as? String)                                    // UUID encodes as a string
    }

    func testTransactionDeclinedDefaultsToFalseWhenAbsent() throws {
        // mirrors the app's decodeIfPresent(declined) ?? false so an older client without the field decodes
        let json = #"{"id":"11111111-1111-1111-1111-111111111111","dedupeKey":"k","timestamp":"2026-06-29T00:00:00.000Z","amount":1.0,"currency":"USD","merchant":"m","cardName":"c","source":"s","pending":false}"#
        let txn = try JSONDecoder().decode(LedgerBridgeTransaction.self, from: Data(json.utf8))
        XCTAssertFalse(txn.declined)
    }
}
