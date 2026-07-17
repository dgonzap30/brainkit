import Foundation

/// Wire type for GET/POST `/ea/threads` and GET `/ea/threads/:id` (E9 exec-assistant threads).
public struct EaThread: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var status: String
    public var createdAt: String
    public var updatedAt: String
    /// Last-turn excerpt for sidebar rows. Server-computed; only `GET /ea/threads` carries it.
    public var preview: String?

    public init(id: String, title: String, status: String, createdAt: String, updatedAt: String, preview: String? = nil) {
        self.id = id
        self.title = title
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.preview = preview
    }
}

/// One turn in an EA thread, as returned by `GET /ea/threads/:id`. The brain response also carries
/// a `usage` field we intentionally don't decode — Codable ignores unknown keys.
public struct EaTurnDTO: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let role: String
    public let content: String
    public let error: String?
    public let createdAt: String

    public init(id: String, role: String, content: String, error: String?, createdAt: String) {
        self.id = id
        self.role = role
        self.content = content
        self.error = error
        self.createdAt = createdAt
    }
}

/// Parsed SSE event from `POST /ea/threads/:id/messages`.
public enum EaStreamEvent: Equatable, Sendable {
    case delta(String)
    case done(text: String, error: String?, turnId: String?)
    case error(String)
}

/// Raw `data: {...}` JSON frame off the wire, before it's classified into an `EaStreamEvent`.
struct EaSseFrame: Decodable {
    let delta: String?
    let done: Bool?
    let text: String?
    let error: String?
    let turnId: String?
}

/// The capability Reach depends on — lets tests inject a mock without a network, mirroring `FrontDoorClient`.
public protocol EaClientProtocol: Sendable {
    func eaThreads() async throws -> [EaThread]
    func eaThreads(q: String?, limit: Int?) async throws -> [EaThread]
    func eaCreateThread(title: String?) async throws -> EaThread
    func eaThread(id: String) async throws -> (thread: EaThread, turns: [EaTurnDTO])
    func eaArchiveThread(id: String) async throws
    func eaRenameThread(id: String, title: String) async throws
    func eaSend(threadId: String, text: String) -> AsyncThrowingStream<EaStreamEvent, Error>
}

extension BrainClient: EaClientProtocol {}
