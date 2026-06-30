import Foundation

public struct TemperWorkout: Codable, Sendable, Equatable {
    public var id: String                 // WorkoutSessionSummary.id (UUID) as string
    public var workoutId: String
    public var sessionDate: String        // ISO-8601 of WorkoutSessionSummary.sessionDate
    public var startedAt: String          // ISO-8601
    public var endedAt: String            // ISO-8601
    public var lockInDurationMinutes: Double
    public var whoopStrain: Double?
    public var whoopAvgHR: Int?
    public var whoopKilojoules: Double?
    public var whoopDurationMinutes: Double?
    public init(id: String, workoutId: String, sessionDate: String, startedAt: String, endedAt: String,
                lockInDurationMinutes: Double, whoopStrain: Double? = nil, whoopAvgHR: Int? = nil,
                whoopKilojoules: Double? = nil, whoopDurationMinutes: Double? = nil) {
        self.id = id; self.workoutId = workoutId; self.sessionDate = sessionDate
        self.startedAt = startedAt; self.endedAt = endedAt; self.lockInDurationMinutes = lockInDurationMinutes
        self.whoopStrain = whoopStrain; self.whoopAvgHR = whoopAvgHR
        self.whoopKilojoules = whoopKilojoules; self.whoopDurationMinutes = whoopDurationMinutes
    }
}

public struct TemperFoodDay: Codable, Sendable, Equatable {
    public var date: String               // device-local "YYYY-MM-DD"
    public var totalCalories: Int
    public var totalProtein: Int
    public var totalCarbs: Int
    public var totalFat: Int
    public var entryCount: Int
    public init(date: String, totalCalories: Int, totalProtein: Int, totalCarbs: Int, totalFat: Int, entryCount: Int) {
        self.date = date; self.totalCalories = totalCalories; self.totalProtein = totalProtein
        self.totalCarbs = totalCarbs; self.totalFat = totalFat; self.entryCount = entryCount
    }
}

public struct TemperWHOOPDay: Codable, Sendable, Equatable {
    public var date: String               // device-local "YYYY-MM-DD"
    public var recoveryScore: Int?
    public var hrv: Double?
    public var rhr: Int?
    public var strain: Double?
    public var sleepHours: Double?
    public var sleepPerformance: Int?
    public init(date: String, recoveryScore: Int? = nil, hrv: Double? = nil, rhr: Int? = nil,
                strain: Double? = nil, sleepHours: Double? = nil, sleepPerformance: Int? = nil) {
        self.date = date; self.recoveryScore = recoveryScore; self.hrv = hrv; self.rhr = rhr
        self.strain = strain; self.sleepHours = sleepHours; self.sleepPerformance = sleepPerformance
    }
}

public enum TemperSyncReason: String, Codable, Sendable {
    case observer, foreground, manual, backfill
}

public struct TemperIngestRequest: Codable, Sendable, Equatable {
    public let schemaVersion: String      // always "temper.v1"
    public var deviceId: String
    public var exportedAt: String         // ISO-8601
    public var reason: TemperSyncReason
    public var workouts: [TemperWorkout]
    public var foodDays: [TemperFoodDay]
    public var whoopDays: [TemperWHOOPDay]
    public init(deviceId: String, exportedAt: String, reason: TemperSyncReason,
                workouts: [TemperWorkout], foodDays: [TemperFoodDay], whoopDays: [TemperWHOOPDay]) {
        self.schemaVersion = "temper.v1"
        self.deviceId = deviceId; self.exportedAt = exportedAt; self.reason = reason
        self.workouts = workouts; self.foodDays = foodDays; self.whoopDays = whoopDays
    }
}

public enum TemperIngestOutcome: Equatable, Sendable {
    case accepted(workouts: Int, foodDays: Int, whoopDays: Int)   // brain 200 {ok:true}
    case discarded(reason: String)                                // brain 200 {ok:false} — do NOT retry
}
