import Foundation

/// One record from the brain's per-app write outbox — an approved write the brain executed for a limb
/// to surface or apply. This is the Swift mirror of the brain's `connector.v1` envelope
/// (`brain/src/core/connector-types.ts`), the single source of truth for both sides. One JSON line per
/// brain-authored write, appended to `<root>/personal-app-outbox/<appId>/<target>.jsonl` and pulled by
/// apps via `GET /core/personal-apps/:appId/outbox`. The canonical golden fixture
/// `Contract/fixtures/connector.v1.json` is decoded by `ContractFixtureTests` as the Swift half of the
/// wire-contract drift gate.
///
/// The brain *produces* these (they are always well-formed), so the lossy per-element decode in
/// `BrainConnectorClient` is a corrupt-line sanitizer, not an untrusted-input boundary. Apps dedup by
/// `executionId`. `payload` is opaque and app-specific (`JSONValue`): a consumer reads the keys it
/// knows or re-decodes the payload into its own typed struct.
public struct ConnectorRecord: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let executionId: String
    public let itemId: String
    public let writePlanId: String
    public let appId: String
    public let environment: String
    public let target: String
    public let operation: String
    public let mode: String
    public let actor: String
    public let executedAt: String
    public let payload: [String: JSONValue]
    public let approval: Approval
    public let rollback: Rollback

    /// The inbox decision that authorised the write — provenance for the audit trail.
    public struct Approval: Codable, Equatable, Sendable {
        public let status: String
        public let actor: String
        public let decidedAt: String
        public let reason: String?   // free-text reason, or null for an auto-approval

        public init(status: String, actor: String, decidedAt: String, reason: String?) {
            self.status = status
            self.actor = actor
            self.decidedAt = decidedAt
            self.reason = reason
        }
    }

    /// How to undo this write — append-only outboxes are reverted by dropping the matching line.
    public struct Rollback: Codable, Equatable, Sendable {
        public let type: String
        public let outboxPath: String
        public let removeExecutionId: String

        public init(type: String, outboxPath: String, removeExecutionId: String) {
            self.type = type
            self.outboxPath = outboxPath
            self.removeExecutionId = removeExecutionId
        }
    }

    public init(
        schemaVersion: String, executionId: String, itemId: String, writePlanId: String,
        appId: String, environment: String, target: String, operation: String, mode: String,
        actor: String, executedAt: String, payload: [String: JSONValue],
        approval: Approval, rollback: Rollback
    ) {
        self.schemaVersion = schemaVersion
        self.executionId = executionId
        self.itemId = itemId
        self.writePlanId = writePlanId
        self.appId = appId
        self.environment = environment
        self.target = target
        self.operation = operation
        self.mode = mode
        self.actor = actor
        self.executedAt = executedAt
        self.payload = payload
        self.approval = approval
        self.rollback = rollback
    }
}
