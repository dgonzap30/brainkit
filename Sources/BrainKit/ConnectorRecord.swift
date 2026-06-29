import Foundation

/// One record from the brain's per-app write outbox — an approved write the brain executed for a
/// limb to surface or apply. Mirrors the JSONL shape `personal-app-executor` writes today
/// (`{ executionId, executedAt?, payload: { text } }`), generalized into the shared SDK from
/// LockIn's hand-rolled `LodestarInboxReader.LodestarOutboxRecord`.
///
/// Decoding is **lossy by contract**: a malformed element is dropped by the client
/// (`BrainConnectorClient.decodeEnvelope`), never thrown — the same robustness the on-device
/// readers rely on so one bad line can't wedge the whole outbox pull.
///
/// `payload` is a struct with a single `text` field, not a tagged enum, because that is the only
/// shape on the wire today and the wire carries no discriminator. Adding payload variants is a
/// coordinated, additive wire-version bump (the brain must emit a `kind`/`type` tag first) — not a
/// unilateral SDK change. When that second kind ships, `Payload` becomes the typed enum.
public struct ConnectorRecord: Decodable, Equatable, Sendable {
    public let executionId: String
    public let executedAt: String?
    public let payload: Payload

    public struct Payload: Decodable, Equatable, Sendable {
        public let text: String
        public init(text: String) { self.text = text }
    }

    public init(executionId: String, executedAt: String?, payload: Payload) {
        self.executionId = executionId
        self.executedAt = executedAt
        self.payload = payload
    }
}
