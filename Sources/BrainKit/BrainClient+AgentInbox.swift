import Foundation

/// One reviewable item from the brain's agent inbox (`GET /core/agent/inbox`) — the
/// UI-facing subset of the brain's AgentInboxItem. Unknown/extra fields are ignored;
/// all approval-integrity machinery (allowlist, fingerprint pinning, TOCTOU) stays
/// server-side — clients only list and post decisions.
public struct AgentInboxItemDTO: Codable, Identifiable, Equatable, Sendable {
    public struct WritePlan: Codable, Equatable, Sendable {
        public let id: String
        public let appId: String
        public let environment: String
        public let target: String
        public let operation: String
        public let mode: String
        public let rows: Int
        /// Arbitrary write-plan payload (e.g. the fields being inserted/upserted). Best-effort
        /// decoded — a malformed or absent payload never drops the plan or its item, it just
        /// falls back to empty.
        public let payload: [String: JSONValue]

        public init(id: String, appId: String, environment: String, target: String,
                    operation: String, mode: String, rows: Int, payload: [String: JSONValue] = [:]) {
            self.id = id
            self.appId = appId
            self.environment = environment
            self.target = target
            self.operation = operation
            self.mode = mode
            self.rows = rows
            self.payload = payload
        }

        private enum CodingKeys: String, CodingKey {
            case id, appId, environment, target, operation, mode, rows, payload
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            appId = try container.decode(String.self, forKey: .appId)
            environment = try container.decode(String.self, forKey: .environment)
            target = try container.decode(String.self, forKey: .target)
            operation = try container.decode(String.self, forKey: .operation)
            mode = try container.decode(String.self, forKey: .mode)
            rows = try container.decode(Int.self, forKey: .rows)
            payload = (try? container.decodeIfPresent([String: JSONValue].self, forKey: .payload)) ?? [:]
        }
    }

    public let id: String
    public let kind: String
    public let text: String
    public let status: String
    public let confidence: Double
    public let observedAt: String
    public let writePlan: WritePlan?
    /// Present when this item is a re-proposal of an earlier one (steer flow): the id of the
    /// item it revises, the user's steer note, and how the revision was produced.
    public let revisesId: String?
    public let steerNote: String?
    public let revisionMode: String?

    public init(id: String, kind: String, text: String, status: String,
                confidence: Double, observedAt: String, writePlan: WritePlan?,
                revisesId: String? = nil, steerNote: String? = nil, revisionMode: String? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.status = status
        self.confidence = confidence
        self.observedAt = observedAt
        self.writePlan = writePlan
        self.revisesId = revisesId
        self.steerNote = steerNote
        self.revisionMode = revisionMode
    }
}

/// Result of a decide/execute call. The brain returns this shape with HTTP 200 (ok),
/// 400, or 404 — the client decodes all three so callers branch on `ok`/`code`,
/// mirroring the route's own result contract.
public struct AgentInboxActionResult: Codable, Equatable, Sendable {
    public let ok: Bool
    public let code: String?
    public let message: String?

    public init(ok: Bool, code: String?, message: String?) {
        self.ok = ok
        self.code = code
        self.message = message
    }
}

public extension BrainClient {
    /// GET /core/agent/inbox?status=&limit= — reviewable items. Authorized by the
    /// server's tailnet default-deny gate with the same front-door bearer as /ea.
    func agentInbox(status: String? = nil, limit: Int? = nil) async throws -> [AgentInboxItemDTO] {
        var comps = URLComponents(url: baseURL.appendingPathComponent("core/agent/inbox"), resolvingAgainstBaseURL: false)!
        var query: [URLQueryItem] = []
        if let status { query.append(URLQueryItem(name: "status", value: status)) }
        if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.timeoutInterval = 15
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: req) } catch { throw BrainError.unreachable }
        try Self.checkInboxStatus(response, allowResultStatuses: false)
        return Self.decodeAgentInboxList(data)
    }

    /// POST /core/agent/inbox/decide — dry-run approval/dismissal (never executes).
    func decideAgentInboxItem(id: String, decision: String, actor: String, reason: String? = nil) async throws -> AgentInboxActionResult {
        var body: [String: Any] = ["itemId": id, "decision": decision, "actor": actor]
        if let reason { body["reason"] = reason }
        return try await postInboxAction(path: "core/agent/inbox/decide", body: body)
    }

    /// POST /core/agent/inbox/execute — policy-checked execution of an approved item
    /// (fingerprint/TOCTOU gates run server-side; a refused execute comes back ok:false).
    func executeAgentInboxItem(id: String, actor: String) async throws -> AgentInboxActionResult {
        try await postInboxAction(path: "core/agent/inbox/execute", body: ["itemId": id, "actor": actor])
    }

    /// Lossy list decode: a malformed element is dropped, a non-envelope body → [] —
    /// same per-element robustness contract as BrainConnectorClient.decodeEnvelope.
    /// `internal` so tests exercise it directly via `@testable import`.
    internal static func decodeAgentInboxList(_ data: Data) -> [AgentInboxItemDTO] {
        struct FailableItem: Decodable {
            let value: AgentInboxItemDTO?
            init(from decoder: Decoder) throws { value = try? AgentInboxItemDTO(from: decoder) }
        }
        struct Envelope: Decodable { let items: [FailableItem] }
        guard let env = try? JSONDecoder().decode(Envelope.self, from: data) else { return [] }
        return env.items.compactMap(\.value)
    }

    private func postInboxAction(path: String, body: [String: Any]) async throws -> AgentInboxActionResult {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: req) } catch { throw BrainError.unreachable }
        try Self.checkInboxStatus(response, allowResultStatuses: true)
        do { return try JSONDecoder().decode(AgentInboxActionResult.self, from: data) }
        catch { throw BrainError.decoding }
    }

    /// decide/execute return their result body with 200/400/404 — those decode; everything
    /// else maps to the standard BrainError set.
    private static func checkInboxStatus(_ response: URLResponse, allowResultStatuses: Bool) throws {
        guard let http = response as? HTTPURLResponse else { throw BrainError.unreachable }
        switch http.statusCode {
        case 200: return
        case 400 where allowResultStatuses, 404 where allowResultStatuses, 422 where allowResultStatuses: return
        case 401: throw BrainError.unauthorized
        case 429: throw BrainError.rateLimited
        default: throw BrainError.server(status: http.statusCode)
        }
    }
}
