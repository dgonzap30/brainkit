import Foundation

/// front-door classification mode. `.auto` lets the brain classify capture-vs-ask.
public enum FrontDoorMode: String, Codable, Sendable {
    case auto, ask, capture
}

/// `POST /front-door` request body.
public struct FrontDoorRequest: Encodable, Sendable, Equatable {
    public let text: String
    public let mode: FrontDoorMode
    public init(text: String, mode: FrontDoorMode) {
        self.text = text
        self.mode = mode
    }
}

/// `POST /front-door` response. Shape is fixed (brain/src/server.ts:335-346): both the
/// ask and capture branches return all ten keys; only `kind` is reliably non-null.
public struct FrontDoorResponse: Decodable, Sendable, Equatable {
    public let kind: String
    public let action: String?
    public let answer: String?
    public let confidence: Double?
    public let surface: String?
    public let destination: String?
    public let formatted: String?
    public let reviewId: String?
    public let reason: String?
    public let cost: Double?

    public init(kind: String, action: String? = nil, answer: String? = nil, confidence: Double? = nil,
                surface: String? = nil, destination: String? = nil, formatted: String? = nil,
                reviewId: String? = nil, reason: String? = nil, cost: Double? = nil) {
        self.kind = kind; self.action = action; self.answer = answer; self.confidence = confidence
        self.surface = surface; self.destination = destination; self.formatted = formatted
        self.reviewId = reviewId; self.reason = reason; self.cost = cost
    }
}
