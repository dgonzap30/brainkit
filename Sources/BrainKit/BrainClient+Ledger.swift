import Foundation

private struct LedgerIngestResponse: Decodable {
    let ok: Bool
    let received: Int?
    let error: String?
}

extension BrainClient {
    /// POST a ledger.v1 finance snapshot to the brain's INGEST-gated receiver. Uses the **ingest**
    /// token (not the front-door token), mirroring `ingestHealth`. 200 {ok:true} → .accepted; 200
    /// {ok:false} → .discarded (do NOT retry — deterministic reject); 401 → unauthorized; 5xx /
    /// transport → throw retryable so the app's outbox re-queues.
    public func ingestLedger(_ batch: LedgerIngestPayload, ingestToken: String) async throws -> LedgerIngestOutcome {
        let url = baseURL.appendingPathComponent("core/personal-apps/ledger/ingest")
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
        default:  throw BrainError.server(status: http.statusCode)   // includes 503 → client retries
        }
        guard let decoded = try? JSONDecoder().decode(LedgerIngestResponse.self, from: data) else {
            throw BrainError.decoding
        }
        if decoded.ok { return .accepted(received: decoded.received ?? 0) }
        return .discarded(reason: decoded.error ?? "rejected")
    }
}
