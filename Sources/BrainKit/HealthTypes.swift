import Foundation

public struct HealthSleep: Codable, Sendable, Equatable {
    public var durationMin: Int?
    public var remMin: Int?
    public var deepMin: Int?
    public var coreMin: Int?
    public var awakeMin: Int?
    public var inBedMin: Int?
    public init(durationMin: Int? = nil, remMin: Int? = nil, deepMin: Int? = nil,
                coreMin: Int? = nil, awakeMin: Int? = nil, inBedMin: Int? = nil) {
        self.durationMin = durationMin; self.remMin = remMin; self.deepMin = deepMin
        self.coreMin = coreMin; self.awakeMin = awakeMin; self.inBedMin = inBedMin
    }
}

public struct HealthDaySummary: Codable, Sendable, Equatable {
    public var day: String                 // "YYYY-MM-DD", device-local wake day
    public var sleep: HealthSleep?
    public var restingHeartRate: Int?
    public var hrvMs: Double?
    public var activeEnergyKcal: Int?
    public var exerciseMin: Int?
    public var steps: Int?
    public var walkRunDistanceKm: Double?
    public var vo2Max: Double?
    public var respiratoryRate: Double?
    public var spo2: Int?
    public var bodyMassKg: Double?
    public var mindfulMin: Int?
    public init(day: String, sleep: HealthSleep? = nil, restingHeartRate: Int? = nil, hrvMs: Double? = nil,
                activeEnergyKcal: Int? = nil, exerciseMin: Int? = nil, steps: Int? = nil,
                walkRunDistanceKm: Double? = nil, vo2Max: Double? = nil, respiratoryRate: Double? = nil,
                spo2: Int? = nil, bodyMassKg: Double? = nil, mindfulMin: Int? = nil) {
        self.day = day; self.sleep = sleep; self.restingHeartRate = restingHeartRate; self.hrvMs = hrvMs
        self.activeEnergyKcal = activeEnergyKcal; self.exerciseMin = exerciseMin; self.steps = steps
        self.walkRunDistanceKm = walkRunDistanceKm; self.vo2Max = vo2Max; self.respiratoryRate = respiratoryRate
        self.spo2 = spo2; self.bodyMassKg = bodyMassKg; self.mindfulMin = mindfulMin
    }
}

public struct HealthWorkout: Codable, Sendable, Equatable {
    public var uuid: String
    public var type: String
    public var start: String
    public var end: String
    public var durationMin: Int
    public var energyKcal: Int?
    public var distanceKm: Double?
    public var avgHeartRate: Int?
    public init(uuid: String, type: String, start: String, end: String, durationMin: Int,
                energyKcal: Int? = nil, distanceKm: Double? = nil, avgHeartRate: Int? = nil) {
        self.uuid = uuid; self.type = type; self.start = start; self.end = end; self.durationMin = durationMin
        self.energyKcal = energyKcal; self.distanceKm = distanceKm; self.avgHeartRate = avgHeartRate
    }
}

public enum HealthSyncReason: String, Codable, Sendable {
    case observer, foreground, manual, backfill
}

public struct HealthIngestRequest: Codable, Sendable, Equatable {
    public let schemaVersion: String       // always "health.v1"
    public var deviceId: String
    public var exportedAt: String          // ISO-8601
    public var reason: HealthSyncReason
    public var days: [HealthDaySummary]
    public var workouts: [HealthWorkout]
    public init(deviceId: String, exportedAt: String, reason: HealthSyncReason,
                days: [HealthDaySummary], workouts: [HealthWorkout]) {
        self.schemaVersion = "health.v1"
        self.deviceId = deviceId; self.exportedAt = exportedAt; self.reason = reason
        self.days = days; self.workouts = workouts
    }
}

public enum HealthIngestOutcome: Equatable, Sendable {
    case accepted(days: Int, workouts: Int)   // brain 200 {ok:true}
    case discarded(reason: String)            // brain 200 {ok:false, rejected} — do NOT retry
}
