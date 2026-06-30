import Foundation

private struct TemperIngestResponse: Decodable {
    let ok: Bool
    let workouts: Int?
    let foodDays: Int?
    let whoopDays: Int?
    let rejected: String?
}

extension BrainClient {
    /// POST a temper.v1 batch to the brain's INGEST-gated receiver. Uses the **ingest** token (not the
    /// front-door token). 200 {ok:true} → .accepted; 200 {ok:false} → .discarded (do NOT retry); 401 →
    /// unauthorized; 5xx / transport → throw retryable.
    public func ingestTemper(_ batch: TemperIngestRequest, ingestToken: String) async throws -> TemperIngestOutcome {
        let url = baseURL.appendingPathComponent("core/personal-apps/temper/ingest")
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
        guard let decoded = try? JSONDecoder().decode(TemperIngestResponse.self, from: data) else {
            throw BrainError.decoding
        }
        if decoded.ok {
            return .accepted(workouts: decoded.workouts ?? 0, foodDays: decoded.foodDays ?? 0, whoopDays: decoded.whoopDays ?? 0)
        }
        return .discarded(reason: decoded.rejected ?? "rejected")
    }
}
