import Foundation

/// Wire type for GET /pairing/config (E9 §1c). `authenticatedWith` == "previous" means the
/// caller authed with a rotated-out token and MUST persist `token.value`.
public struct PairingConfig: Decodable, Equatable, Sendable {
    public struct TokenBox: Decodable, Equatable, Sendable {
        public let value: String
        public init(value: String) { self.value = value }
    }
    public let schemaVersion: Int
    public let hosts: [String]
    public let newsroomBFFHost: String?
    public let token: TokenBox
    public let ingestToken: TokenBox?
    public let authenticatedWith: String

    public init(schemaVersion: Int, hosts: [String], newsroomBFFHost: String?,
                token: TokenBox, ingestToken: TokenBox?, authenticatedWith: String) {
        self.schemaVersion = schemaVersion; self.hosts = hosts; self.newsroomBFFHost = newsroomBFFHost
        self.token = token; self.ingestToken = ingestToken; self.authenticatedWith = authenticatedWith
    }
}
