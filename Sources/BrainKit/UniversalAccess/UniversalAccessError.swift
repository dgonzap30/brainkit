import Foundation

public enum UniversalAccessError: Error, Equatable, Sendable {
    case invalidRequest
    case notPaired
    case originMismatch
    case bodyTooLarge
    case responseTooLarge
    case credentialUnavailable
    case tlsPinMismatch
    case transport
    case decoding
    case clockSkew(requestId: String?, serverTime: String)
    case revoked(requestId: String?)
    case unauthenticated(requestId: String?)
    case rateLimited(requestId: String?)
    case server(
        category: UniversalAccessErrorCategory,
        status: Int,
        requestId: String?,
        retryable: Bool
    )

    public var isRetryable: Bool {
        switch self {
        case .transport, .rateLimited, .clockSkew:
            return true
        case .server(_, _, _, let retryable):
            return retryable
        default:
            return false
        }
    }
}

extension UniversalAccessError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "The universal access request is invalid."
        case .notPaired:
            return "This device is not paired."
        case .originMismatch:
            return "The server does not match the paired origin."
        case .bodyTooLarge:
            return "The request is too large."
        case .responseTooLarge:
            return "The server response is too large."
        case .credentialUnavailable:
            return "The device credential is unavailable."
        case .tlsPinMismatch:
            return "The server identity does not match the paired server."
        case .transport:
            return "The paired server could not be reached."
        case .decoding:
            return "The server response is invalid."
        case .clockSkew:
            return "The device clock is outside the paired server's signing window."
        case .revoked:
            return "This device has been revoked. Pair it again to continue."
        case .unauthenticated:
            return "The device credential was not accepted."
        case .rateLimited:
            return "The server is temporarily rate limiting requests."
        case .server(let category, let status, _, _):
            return "The server rejected the request (\(category.rawValue), HTTP \(status))."
        }
    }
}

extension UniversalAccessError: CustomStringConvertible {
    public var description: String { errorDescription ?? "Universal access failed." }
}
