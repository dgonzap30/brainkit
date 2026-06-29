import Foundation

/// Pulls a limb's approved write-outbox from the brain — the shared-SDK form of LockIn's
/// `LodestarInboxReader` device transport, usable by every limb on a real device (HTTP over
/// Tailscale). The Simulator shared-file transport stays app-side; this is the network half.
///
/// Two contracts, deliberately split (refining LodestarInboxReader, which swallowed everything):
///  - **Body decode is lossy** — `{ records: [...] }` is decoded per-element; a malformed record is
///    dropped and an undecodable 200 body yields `[]`. A single bad line never aborts the pull.
///  - **Transport/auth/server failures throw typed `BrainError`** — so the caller can branch
///    (re-auth on `.unauthorized`, retry on `.unreachable`/`.server`), rather than silently seeing
///    an empty outbox and mistaking "auth broke" for "nothing to do".
public struct BrainConnectorClient: Sendable {
    public let baseURL: URL
    public let token: String?
    internal let session: URLSession

    public init(baseURL: URL, token: String?, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    /// `GET /core/personal-apps/{appId}/outbox` → the app's pending approved `connector.v1` writes.
    /// Returns only well-formed records (malformed elements dropped, undecodable body → `[]`); throws
    /// `BrainError` on transport/auth/server failure. appId-generic — the brain serves every app with a
    /// registered executor adapter (E3-3) and 404s an unknown app (surfaced here as `.server(status:404)`).
    /// The caller dedups by `executionId` and persists applied ids so re-polling never re-applies.
    public func pollOutbox(appId: String) async throws -> [ConnectorRecord] {
        var req = URLRequest(url: baseURL.appendingPathComponent("core/personal-apps/\(appId)/outbox"))
        req.httpMethod = "GET"
        req.timeoutInterval = 10
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: req) }
        catch { throw BrainError.unreachable }

        guard let http = response as? HTTPURLResponse else { throw BrainError.unreachable }
        switch http.statusCode {
        case 200: break
        case 401: throw BrainError.unauthorized
        case 429: throw BrainError.rateLimited
        default:  throw BrainError.server(status: http.statusCode)
        }
        return Self.decodeEnvelope(data)
    }

    /// Lossy decode of the brain's `{ "records": [ … ] }` response: a malformed element is dropped,
    /// a non-envelope / garbage body → `[]`. Mirrors `LodestarInboxReader.decodeOutboxResponse` so
    /// every limb's pull behaves identically. `internal` so tests can exercise it directly.
    static func decodeEnvelope(_ data: Data) -> [ConnectorRecord] {
        guard let env = try? JSONDecoder().decode(Envelope.self, from: data) else { return [] }
        return env.records.compactMap(\.value)
    }

    /// Per-element decode failure captured as `nil` instead of throwing, so one bad record never
    /// aborts decoding the whole array (matches the per-line robustness of the file transport).
    private struct FailableRecord: Decodable {
        let value: ConnectorRecord?
        init(from decoder: Decoder) throws { value = try? ConnectorRecord(from: decoder) }
    }
    private struct Envelope: Decodable { let records: [FailableRecord] }
}
