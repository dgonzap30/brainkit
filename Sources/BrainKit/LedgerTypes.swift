import Foundation

/// ledger.v1 wire DTOs — the canonical Swift form of the Ledger finance snapshot the iOS app pushes
/// to the brain. Lifted into the shared SDK from Ledger's LodestarBridge.swift (so E6 can delete the
/// app's duplicated structs and every future consumer inherits these), exactly as HealthTypes.swift
/// was for health.v1.
///
/// Dates are **wire strings** (ISO-8601), not `Date`: the brain's `validateLedgerPayload` requires
/// `exportedAt`/`timestamp` to be strings, and a plain `JSONEncoder` encodes `Date` as a number — so
/// modeling them as String keeps a plain encoder brain-valid with no date strategy. The Ledger app
/// maps its `Date` ↔ ISO string at its own boundary (same split HealthTypes uses).

public struct LedgerBridgeTransaction: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var dedupeKey: String
    public var timestamp: String        // ISO-8601 wire string
    public var amount: Double
    public var currency: String
    public var merchant: String
    public var cardName: String
    public var source: String
    public var pending: Bool
    public var declined: Bool

    public init(id: UUID, dedupeKey: String, timestamp: String, amount: Double, currency: String,
                merchant: String, cardName: String, source: String, pending: Bool, declined: Bool) {
        self.id = id; self.dedupeKey = dedupeKey; self.timestamp = timestamp; self.amount = amount
        self.currency = currency; self.merchant = merchant; self.cardName = cardName
        self.source = source; self.pending = pending; self.declined = declined
    }

    private enum CodingKeys: String, CodingKey {
        case id, dedupeKey, timestamp, amount, currency, merchant, cardName, source, pending, declined
    }

    /// Custom decode so `declined` defaults to false when absent (mirrors the app's
    /// `decodeIfPresent(declined) ?? false` — an older client without the field still decodes).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        dedupeKey = try c.decode(String.self, forKey: .dedupeKey)
        timestamp = try c.decode(String.self, forKey: .timestamp)
        amount = try c.decode(Double.self, forKey: .amount)
        currency = try c.decode(String.self, forKey: .currency)
        merchant = try c.decode(String.self, forKey: .merchant)
        cardName = try c.decode(String.self, forKey: .cardName)
        source = try c.decode(String.self, forKey: .source)
        pending = try c.decode(Bool.self, forKey: .pending)
        declined = try c.decodeIfPresent(Bool.self, forKey: .declined) ?? false
    }
}

public struct LedgerFinanceSnapshot: Codable, Equatable, Sendable {
    public var todayTotals: [String: Double]
    public var monthTotals: [String: Double]
    public var pendingCount: Int
    public var latestTransaction: LedgerBridgeTransaction?
    public var sourceCounts: [String: Int]

    public init(todayTotals: [String: Double], monthTotals: [String: Double], pendingCount: Int,
                latestTransaction: LedgerBridgeTransaction?, sourceCounts: [String: Int]) {
        self.todayTotals = todayTotals; self.monthTotals = monthTotals; self.pendingCount = pendingCount
        self.latestTransaction = latestTransaction; self.sourceCounts = sourceCounts
    }
}

public struct LedgerIngestPayload: Codable, Equatable, Sendable {
    public let schemaVersion: String    // always "ledger.v1"
    public var deviceId: String
    public var exportedAt: String       // ISO-8601 wire string
    public var reason: String
    public var snapshot: LedgerFinanceSnapshot
    public var transactions: [LedgerBridgeTransaction]

    public init(deviceId: String, exportedAt: String, reason: String,
                snapshot: LedgerFinanceSnapshot, transactions: [LedgerBridgeTransaction]) {
        self.schemaVersion = "ledger.v1"
        self.deviceId = deviceId; self.exportedAt = exportedAt; self.reason = reason
        self.snapshot = snapshot; self.transactions = transactions
    }
}

public enum LedgerIngestOutcome: Equatable, Sendable {
    case accepted(received: Int)   // brain 200 {ok:true, received}
    case discarded(reason: String) // brain 200 {ok:false, error} — deterministic reject, do NOT retry
}
