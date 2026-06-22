import Foundation

/// Cause-bearing error so the UI can branch (re-auth on .unauthorized, retry on .unreachable, etc.).
public enum BrainError: Error, Equatable, Sendable {
    case unreachable
    case unauthorized
    case rateLimited
    case server(status: Int)
    case decoding
}
