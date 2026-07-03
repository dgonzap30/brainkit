import Foundation

public struct RundownTake: Codable, Sendable, Equatable {
    public var id: String
    public var scriptId: String?          // nil = freeform take, no script
    public var fileName: String
    public var recordedAt: String         // ISO-8601
    public var durationSec: Double
    public var picked: Bool
    public var truncated: Bool?
    public init(id: String, scriptId: String? = nil, fileName: String, recordedAt: String,
                durationSec: Double, picked: Bool, truncated: Bool? = nil) {
        self.id = id; self.scriptId = scriptId; self.fileName = fileName
        self.recordedAt = recordedAt; self.durationSec = durationSec
        self.picked = picked; self.truncated = truncated
    }
}

public struct RundownScript: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var status: String
    public var durationSec: Double?
    public var pillar: String?
    public init(id: String, title: String, status: String, durationSec: Double? = nil, pillar: String? = nil) {
        self.id = id; self.title = title; self.status = status
        self.durationSec = durationSec; self.pillar = pillar
    }
}

public struct RundownIngestRequest: Codable, Sendable, Equatable {
    public let schemaVersion: String      // always "rundown.v1"
    public var deviceId: String
    public var exportedAt: String         // ISO-8601
    public var reason: String
    public var takes: [RundownTake]
    public var scripts: [RundownScript]
    public init(deviceId: String, exportedAt: String, reason: String,
                takes: [RundownTake], scripts: [RundownScript]) {
        self.schemaVersion = "rundown.v1"
        self.deviceId = deviceId; self.exportedAt = exportedAt; self.reason = reason
        self.takes = takes; self.scripts = scripts
    }
}

public enum RundownIngestOutcome: Equatable, Sendable {
    case accepted(takes: Int, scripts: Int)   // brain 200 {ok:true}
    case discarded(reason: String)            // brain 200 {ok:false} — do NOT retry
}
