import Foundation

/// The capability the view model depends on — lets tests inject a mock without a network.
public protocol FrontDoorClient: Sendable {
    func frontDoor(text: String, mode: FrontDoorMode) async throws -> FrontDoorResponse
    func frontDoor(text: String, mode: FrontDoorMode, history: [HistoryTurn]) async throws -> FrontDoorResponse
}

public extension FrontDoorClient {
    /// Back-compat default: conformers that only implement the 2-arg form ignore history.
    func frontDoor(text: String, mode: FrontDoorMode, history: [HistoryTurn]) async throws -> FrontDoorResponse {
        try await frontDoor(text: text, mode: mode)
    }
}

/// Talks to the Lodestar brain over a configurable base URL with an optional bearer token.
/// macOS app (later): baseURL=http://127.0.0.1:4317, token=nil. Reach: mini MagicDNS + FRONT_DOOR_TOKEN.
public struct BrainClient: FrontDoorClient {
    public let baseURL: URL
    public let token: String?
    internal let session: URLSession

    public init(baseURL: URL, token: String?, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    /// Reachability for the status dot — never throws.
    public func health() async -> Bool {
        var req = URLRequest(url: baseURL.appendingPathComponent("health"))
        req.timeoutInterval = 8
        authorize(&req)
        guard let (_, resp) = try? await session.data(for: req) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    public func frontDoor(text: String, mode: FrontDoorMode) async throws -> FrontDoorResponse {
        try await frontDoor(text: text, mode: mode, history: [])
    }

    public func frontDoor(text: String, mode: FrontDoorMode, history: [HistoryTurn]) async throws -> FrontDoorResponse {
        var req = URLRequest(url: baseURL.appendingPathComponent("front-door"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        authorize(&req)
        req.httpBody = try JSONEncoder().encode(
            FrontDoorRequest(text: text, mode: mode, history: history.isEmpty ? nil : history))

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await session.data(for: req)
        } catch {
            throw BrainError.unreachable
        }
        guard let http = resp as? HTTPURLResponse else { throw BrainError.unreachable }
        switch http.statusCode {
        case 200: break
        case 401: throw BrainError.unauthorized
        case 429: throw BrainError.rateLimited
        default: throw BrainError.server(status: http.statusCode)
        }
        do {
            return try JSONDecoder().decode(FrontDoorResponse.self, from: data)
        } catch {
            throw BrainError.decoding
        }
    }

    private func authorize(_ req: inout URLRequest) {
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    }
}
