import Foundation

/// A minimal, lossless JSON value — the Codable stand-in for an opaque, app-specific `[String: Any]`.
/// Used for `ConnectorRecord.payload`, whose shape is decided by the target app (LockIn task text,
/// Ledger transaction fields, …) and carries no discriminator the SDK can switch on. A consuming app
/// reads the fields it knows (`payload["amount"]`, `payload["text"]`) or re-decodes the payload into
/// its own typed struct; BrainKit stays payload-agnostic.
///
/// Decode order is bool → number → string → object → array → null, which the strict Swift-6 Foundation
/// decoder disambiguates correctly (a JSON number is not decoded as Bool). Equatable so the contract
/// drift gate can assert a lossless re-encode round-trip.
public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported JSON value")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .null: try c.encodeNil()
        }
    }
}
