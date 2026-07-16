import Foundation

public extension BrainClient {
    /// GET /ea/threads — list, no filters. `EaClientProtocol` requires this exact zero-arg shape
    /// (protocol requirements can't carry default argument values), so existential callers like
    /// `EaThreadStore` keep resolving here; forwards to the `q`/`limit` overload below.
    func eaThreads() async throws -> [EaThread] {
        try await eaThreads(q: nil, limit: nil)
    }

    /// GET /ea/threads?q=&limit= — list with optional search + limit (E9 exec-assistant search).
    /// Same error mapping as `pairingConfig`/`frontDoor`.
    func eaThreads(q: String? = nil, limit: Int? = nil) async throws -> [EaThread] {
        struct ListResponse: Decodable { let threads: [EaThread] }
        var comps = URLComponents(url: baseURL.appendingPathComponent("ea/threads"), resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = []
        if let q, !q.isEmpty { items.append(URLQueryItem(name: "q", value: q)) }
        if let limit { items.append(URLQueryItem(name: "limit", value: String(limit))) }
        if !items.isEmpty { comps.queryItems = items }
        var req = URLRequest(url: comps.url!)
        req.timeoutInterval = 15
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: req) } catch { throw BrainError.unreachable }
        try Self.checkEaStatus(response)
        do { return try JSONDecoder().decode(ListResponse.self, from: data).threads }
        catch { throw BrainError.decoding }
    }

    /// POST /ea/threads {title?} — create.
    func eaCreateThread(title: String?) async throws -> EaThread {
        var req = URLRequest(url: baseURL.appendingPathComponent("ea/threads"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: title.map { ["title": $0] } ?? [:])
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: req) } catch { throw BrainError.unreachable }
        try Self.checkEaStatus(response)
        do { return try JSONDecoder().decode(EaThread.self, from: data) }
        catch { throw BrainError.decoding }
    }

    /// GET /ea/threads/:id — thread detail + turns. `turns[].usage` (if present) is dropped by Codable.
    func eaThread(id: String) async throws -> (thread: EaThread, turns: [EaTurnDTO]) {
        struct ThreadResponse: Decodable { let thread: EaThread; let turns: [EaTurnDTO] }
        var req = URLRequest(url: baseURL.appendingPathComponent("ea/threads/\(id)"))
        req.timeoutInterval = 15
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: req) } catch { throw BrainError.unreachable }
        try Self.checkEaStatus(response)
        do {
            let decoded = try JSONDecoder().decode(ThreadResponse.self, from: data)
            return (decoded.thread, decoded.turns)
        } catch { throw BrainError.decoding }
    }

    /// POST /ea/threads/:id/archive — expects `{ok:true}`; callers only care whether it threw.
    func eaArchiveThread(id: String) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("ea/threads/\(id)/archive"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = Data("{}".utf8)
        let response: URLResponse
        do { (_, response) = try await session.data(for: req) } catch { throw BrainError.unreachable }
        try Self.checkEaStatus(response)
    }

    /// PATCH /ea/threads/:id {title} — rename; expects `{ok:true}`.
    func eaRenameThread(id: String, title: String) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("ea/threads/\(id)"))
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: ["title": title])
        let response: URLResponse
        do { (_, response) = try await session.data(for: req) } catch { throw BrainError.unreachable }
        try Self.checkEaStatus(response)
    }

    /// POST /ea/threads/:id/messages — SSE stream. Server quirk: a mid-stream throw ends the
    /// stream with a `{"error":...}` frame and NO `done` frame — we yield `.error` and let the
    /// loop end naturally when the stream closes (do not require a trailing `done`).
    func eaSend(threadId: String, text: String) -> AsyncThrowingStream<EaStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = URLRequest(url: baseURL.appendingPathComponent("ea/threads/\(threadId)/messages"))
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
                    req.httpBody = try JSONSerialization.data(withJSONObject: ["text": text])
                    let bytes: URLSession.AsyncBytes
                    let response: URLResponse
                    do { (bytes, response) = try await session.bytes(for: req) } catch { throw BrainError.unreachable }
                    try Self.checkEaStatus(response)
                    for try await line in bytes.lines {
                        guard let event = Self.parseEaSseLine(line) else { continue }
                        continuation.yield(event)
                        if case .done = event { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Pure — classifies one raw SSE `data: {...}` line into an `EaStreamEvent`. No network.
    static func parseEaSseLine(_ line: String) -> EaStreamEvent? {
        guard line.hasPrefix("data: ") else { return nil }
        let payload = Data(line.dropFirst(6).utf8)
        guard let frame = try? JSONDecoder().decode(EaSseFrame.self, from: payload) else { return nil }
        if let delta = frame.delta { return .delta(delta) }
        if frame.done == true { return .done(text: frame.text ?? "", error: frame.error, turnId: frame.turnId) }
        if let error = frame.error { return .error(error) }
        return nil
    }

    private static func checkEaStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw BrainError.unreachable }
        switch http.statusCode {
        case 200: return
        case 401: throw BrainError.unauthorized
        case 429: throw BrainError.rateLimited
        default: throw BrainError.server(status: http.statusCode)
        }
    }
}
