import Foundation

private struct RundownIngestResponse: Decodable {
    let ok: Bool
    let takes: Int?
    let scripts: Int?
    let rejected: String?
}

extension BrainClient {
    /// POST a rundown.v1 batch to the brain's INGEST-gated receiver. Uses the **ingest** token (not the
    /// front-door token). 200 {ok:true} → .accepted; 200 {ok:false} → .discarded (do NOT retry); 401 →
    /// unauthorized; 5xx / transport → throw retryable.
    public func ingestRundown(_ batch: RundownIngestRequest, ingestToken: String) async throws -> RundownIngestOutcome {
        let url = baseURL.appendingPathComponent("core/personal-apps/rundown/ingest")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(ingestToken)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 30
        req.httpBody = try JSONEncoder().encode(batch)

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
        guard let decoded = try? JSONDecoder().decode(RundownIngestResponse.self, from: data) else {
            throw BrainError.decoding
        }
        if decoded.ok {
            return .accepted(takes: decoded.takes ?? 0, scripts: decoded.scripts ?? 0)
        }
        return .discarded(reason: decoded.rejected ?? "rejected")
    }
}
