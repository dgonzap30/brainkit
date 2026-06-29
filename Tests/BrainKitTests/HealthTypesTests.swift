import XCTest
@testable import BrainKit

final class HealthTypesTests: XCTestCase {
    func testEncodesHealthV1WithExactKeysAndOmitsNilMetrics() throws {
        let req = HealthIngestRequest(
            deviceId: "device-abc",
            exportedAt: "2026-06-28T18:00:00.000Z",
            reason: .observer,
            days: [HealthDaySummary(
                day: "2026-06-28",
                sleep: HealthSleep(durationMin: 432, remMin: 100, deepMin: 55, coreMin: 260, awakeMin: 17, inBedMin: 451),
                restingHeartRate: 51, hrvMs: 48, activeEnergyKcal: 540, exerciseMin: 38, steps: 9420,
                walkRunDistanceKm: 6.8, vo2Max: 47.2, respiratoryRate: 14.2, spo2: 97, bodyMassKg: 74.1, mindfulMin: 10)],
            workouts: [HealthWorkout(uuid: "wk-1", type: "running", start: "2026-06-28T13:00:00.000Z",
                end: "2026-06-28T13:32:00.000Z", durationMin: 32, energyKcal: 410, distanceKm: 5.1, avgHeartRate: 152)])

        let data = try JSONEncoder().encode(req)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["schemaVersion"] as? String, "health.v1")
        XCTAssertEqual(obj["deviceId"] as? String, "device-abc")
        XCTAssertEqual(obj["reason"] as? String, "observer")
        let day0 = (obj["days"] as! [[String: Any]])[0]
        XCTAssertEqual(day0["day"] as? String, "2026-06-28")
        XCTAssertEqual(day0["hrvMs"] as? Double, 48)
        XCTAssertEqual((day0["sleep"] as! [String: Any])["remMin"] as? Int, 100)
        let wk0 = (obj["workouts"] as! [[String: Any]])[0]
        XCTAssertEqual(wk0["uuid"] as? String, "wk-1")
    }

    func testNilMetricKeysAreOmittedNotNull() throws {
        let req = HealthIngestRequest(deviceId: "d", exportedAt: "2026-06-28T18:00:00.000Z", reason: .manual,
            days: [HealthDaySummary(day: "2026-06-28", sleep: nil, restingHeartRate: 51)], workouts: [])
        let data = try JSONEncoder().encode(req)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let day0 = (obj["days"] as! [[String: Any]])[0]
        XCTAssertNil(day0.index(forKey: "hrvMs"), "nil metric must omit its key entirely")
        XCTAssertNil(day0.index(forKey: "sleep"))
        XCTAssertNotNil(day0.index(forKey: "restingHeartRate"))
    }
}
