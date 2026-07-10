import Foundation

public extension BrainClient {
    /// GET /pairing/config — the E9 config authority. Same error mapping as frontDoor.
    func pairingConfig() async throws -> PairingConfig {
        var req = URLRequest(url: baseURL.appendingPathComponent("pairing/config"))
        req.timeoutInterval = 15
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let data: Data
        let resp: URLResponse
        do { (data, resp) = try await session.data(for: req) } catch { throw BrainError.unreachable }
        guard let http = resp as? HTTPURLResponse else { throw BrainError.unreachable }
        switch http.statusCode {
        case 200: break
        case 401: throw BrainError.unauthorized
        case 429: throw BrainError.rateLimited
        default: throw BrainError.server(status: http.statusCode)
        }
        do { return try JSONDecoder().decode(PairingConfig.self, from: data) } catch { throw BrainError.decoding }
    }
}
