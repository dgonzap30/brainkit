import XCTest
@testable import BrainKit

final class TemperTypesTests: XCTestCase {
    func testSchemaVersionIsTheConstant() {
        let req = TemperIngestRequest(deviceId: "d", exportedAt: "2026-06-29T18:00:00.000Z",
                                      reason: .foreground, workouts: [], foodDays: [], whoopDays: [])
        XCTAssertEqual(req.schemaVersion, "temper.v1")
    }

    func testEncodeDecodeRoundTrip() throws {
        let req = TemperIngestRequest(
            deviceId: "iphone-17-pro", exportedAt: "2026-06-29T18:00:00.000Z", reason: .observer,
            workouts: [TemperWorkout(id: "WK-1", workoutId: "hk-1", sessionDate: "2026-06-29T00:00:00.000Z",
                                     startedAt: "2026-06-29T15:00:00.000Z", endedAt: "2026-06-29T15:42:00.000Z",
                                     lockInDurationMinutes: 42, whoopStrain: 14.3, whoopAvgHR: 148,
                                     whoopKilojoules: 2100, whoopDurationMinutes: 41)],
            foodDays: [TemperFoodDay(date: "2026-06-29", totalCalories: 2100, totalProtein: 180,
                                     totalCarbs: 190, totalFat: 70, entryCount: 5)],
            whoopDays: [TemperWHOOPDay(date: "2026-06-29", recoveryScore: 66, hrv: 48, rhr: 51,
                                       strain: 14.3, sleepHours: 7.2, sleepPerformance: 88)])
        let data = try JSONEncoder().encode(req)
        let back = try JSONDecoder().decode(TemperIngestRequest.self, from: data)
        XCTAssertEqual(back, req)
        XCTAssertEqual(back.workouts.first?.whoopStrain, 14.3)
        XCTAssertEqual(back.foodDays.first?.entryCount, 5)
        XCTAssertEqual(back.whoopDays.first?.recoveryScore, 66)
    }

    func testOutcomeEquatable() {
        XCTAssertEqual(TemperIngestOutcome.accepted(workouts: 1, foodDays: 2, whoopDays: 3),
                       .accepted(workouts: 1, foodDays: 2, whoopDays: 3))
        XCTAssertNotEqual(TemperIngestOutcome.accepted(workouts: 1, foodDays: 0, whoopDays: 0),
                          .discarded(reason: "x"))
    }
}
