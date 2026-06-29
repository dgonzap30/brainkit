import Foundation
import BrainKit

/// Reads/writes the mini host (UserDefaults) + the front-door + ingest tokens (Keychain) and builds a
/// `BrainClient`. Generalises ReachCore's `ReachConfig`: the storage keys are now init parameters
/// (defaulting to ReachConfig's exact constants, so Reach can adopt this with no behaviour change), and
/// every limb — Temper, future apps — gets the same host→URL parsing and bearer-snapshot makeClient.
public struct PluginConfig: Sendable {
    public static let defaultTokenKey = "front_door_token"
    public static let defaultIngestTokenKey = "ingest_token"
    public static let defaultHostKey = "mini_host"
    public static let defaultPort = 4317

    public let tokenKey: String
    public let ingestTokenKey: String
    public let hostKey: String
    public let port: Int

    private let keychain: KeychainStore
    private nonisolated(unsafe) let defaults: UserDefaults   // UserDefaults is documented thread-safe

    public init(keychain: KeychainStore,
                defaults: UserDefaults = .standard,
                tokenKey: String = defaultTokenKey,
                ingestTokenKey: String = defaultIngestTokenKey,
                hostKey: String = defaultHostKey,
                port: Int = defaultPort) {
        self.keychain = keychain
        self.defaults = defaults
        self.tokenKey = tokenKey
        self.ingestTokenKey = ingestTokenKey
        self.hostKey = hostKey
        self.port = port
    }

    public var token: String? { keychain.string(forKey: tokenKey) }
    public var host: String? { defaults.string(forKey: hostKey) }
    public var ingestToken: String? { keychain.string(forKey: ingestTokenKey) }

    public func setToken(_ token: String?) { keychain.set(token, forKey: tokenKey) }
    public func setHost(_ host: String?) { defaults.set(host, forKey: hostKey) }
    public func setIngestToken(_ token: String?) { keychain.set(token, forKey: ingestTokenKey) }

    /// Pure host → base URL: bare MagicDNS name (→ http://host:port), host:port, or a full URL.
    public func baseURL(forHost host: String?) -> URL? {
        guard let raw = host?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.contains("://") { return URL(string: raw) }
        if raw.contains(":") { return URL(string: "http://\(raw)") }
        return URL(string: "http://\(raw):\(port)")
    }

    /// Host → base URL. Accepts a bare MagicDNS name (→ http://host:port), host:port, or a full URL.
    public var baseURL: URL? { baseURL(forHost: host) }

    /// Configured = a usable base URL AND a non-empty token.
    public var isConfigured: Bool { baseURL != nil && !(token ?? "").isEmpty }

    /// Snapshot host + token once so a concurrent setter can't yield a client with a dropped bearer.
    public func makeClient() -> BrainClient? {
        let snapshotToken = token
        guard let url = baseURL(forHost: host),
              let snapshotToken, !snapshotToken.isEmpty else { return nil }
        return BrainClient(baseURL: url, token: snapshotToken)
    }
}
