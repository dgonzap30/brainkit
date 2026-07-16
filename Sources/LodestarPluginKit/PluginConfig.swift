import Foundation
import BrainKit

/// A brain-provisioned connection field that the user can explicitly take over
/// (config-lock, U1). Raw values are stable storage-key suffixes.
public enum ProvisionedField: String, CaseIterable, Sendable {
    case host, token, ingestToken
}

/// Reads/writes the mini host (UserDefaults) + the front-door + ingest tokens (Keychain) and builds a
/// `BrainClient`. Generalises ReachCore's `ReachConfig`: the storage keys are now init parameters
/// (defaulting to ReachConfig's exact constants, so Reach can adopt this with no behaviour change), and
/// every limb — Temper, future apps — gets the same host→URL parsing and bearer-snapshot makeClient.
public struct PluginConfig: Sendable {
    public static let defaultTokenKey = "front_door_token"
    public static let defaultIngestTokenKey = "ingest_token"
    public static let defaultHostKey = "mini_host"
    public static let defaultPort = 4317
    public static let defaultFallbackHostKey = "brain_host_fallback"
    public static let defaultBFFHostKey = "newsroom_bff_host"
    public static let defaultAdoptedAtKey = "provisioning_adopted_at"

    public let tokenKey: String
    public let ingestTokenKey: String
    public let hostKey: String
    public let port: Int
    public let fallbackHostKey: String
    public let bffHostKey: String
    public let adoptedAtKey: String

    private let keychain: KeychainStore
    private nonisolated(unsafe) let defaults: UserDefaults   // UserDefaults is documented thread-safe

    public init(keychain: KeychainStore,
                defaults: UserDefaults = .standard,
                tokenKey: String = defaultTokenKey,
                ingestTokenKey: String = defaultIngestTokenKey,
                hostKey: String = defaultHostKey,
                port: Int = defaultPort,
                fallbackHostKey: String = defaultFallbackHostKey,
                bffHostKey: String = defaultBFFHostKey,
                adoptedAtKey: String = defaultAdoptedAtKey) {
        self.keychain = keychain
        self.defaults = defaults
        self.tokenKey = tokenKey
        self.ingestTokenKey = ingestTokenKey
        self.hostKey = hostKey
        self.port = port
        self.fallbackHostKey = fallbackHostKey
        self.bffHostKey = bffHostKey
        self.adoptedAtKey = adoptedAtKey
    }

    public var token: String? { keychain.string(forKey: tokenKey) }
    public var host: String? { defaults.string(forKey: hostKey) }
    public var ingestToken: String? { keychain.string(forKey: ingestTokenKey) }
    public var fallbackHost: String? { defaults.string(forKey: fallbackHostKey) }
    public var newsroomBFFHost: String? { defaults.string(forKey: bffHostKey) }
    public var adoptedProvisionedAt: Date? { defaults.object(forKey: adoptedAtKey) as? Date }

    /// UserDefaults key for a field's userOverride flag — derived from the field's
    /// configured storage key so parameterized configs (Temper, tests) never collide.
    private func overrideKey(_ field: ProvisionedField) -> String {
        let base: String
        switch field {
        case .host: base = hostKey
        case .token: base = tokenKey
        case .ingestToken: base = ingestTokenKey
        }
        return "\(base)_user_override"
    }

    /// True when the user explicitly took this field over ("Override?" confirm).
    /// Overridden fields are skipped by refreshFromBrain until reset.
    /// Device-local UserDefaults-tier state — the VALUE's storage (Keychain for
    /// tokens) is unchanged; only the flag lives here.
    public func isOverridden(_ field: ProvisionedField) -> Bool {
        defaults.bool(forKey: overrideKey(field))
    }

    /// Set (confirmed override) or clear (reset to provisioned) a field's flag.
    /// Clearing does not restore the brain value itself — the next refresh does.
    public func setOverridden(_ field: ProvisionedField, _ overridden: Bool) {
        if overridden { defaults.set(true, forKey: overrideKey(field)) }
        else { defaults.removeObject(forKey: overrideKey(field)) }
    }

    public func setToken(_ token: String?) { keychain.set(token, forKey: tokenKey) }
    public func setHost(_ host: String?) { defaults.set(host, forKey: hostKey) }
    public func setIngestToken(_ token: String?) { keychain.set(token, forKey: ingestTokenKey) }

    /// E9 §1b — first-launch adoption. Adopt when the Keychain has no token (fresh install,
    /// reinstall, wiped keychain) OR the bundle record is newer than the last adopted one
    /// (a redeploy deliberately wins over manual edits — mechanism A). Bundle values are
    /// bootstrap-only after first brain contact (refreshFromBrain never touches the stamp).
    @discardableResult
    public func adoptBundleProvisioning(_ record: ProvisioningRecord?) -> Bool {
        guard let record else { return false }
        let keychainEmpty = (token ?? "").isEmpty
        let newer = adoptedProvisionedAt.map { record.provisionedAt > $0 } ?? true
        guard keychainEmpty || newer else { return false }
        setHost(record.brainHost)
        setToken(record.frontDoorToken)
        if let ingest = record.ingestToken { setIngestToken(ingest) }
        if let fallback = record.brainHostFallback { defaults.set(fallback, forKey: fallbackHostKey) }
        else { defaults.removeObject(forKey: fallbackHostKey) }
        if let bff = record.newsroomBFFHost { defaults.set(bff, forKey: bffHostKey) }
        else { defaults.removeObject(forKey: bffHostKey) }
        defaults.set(record.provisionedAt, forKey: adoptedAtKey)
        // Mechanism A: a redeploy deliberately wins over manual edits — a successful
        // adopt therefore also clears userOverride flags, otherwise the freshly
        // adopted values would be shadowed from the very next refresh onward.
        for field in ProvisionedField.allCases { setOverridden(field, false) }
        return true
    }

    /// E9 §1c — config authority inversion. Piggybacked on each app's existing sync cadence.
    /// Applies hosts/BFF/tokens from the brain; deliberately never touches adoptedProvisionedAt
    /// (bundle values are bootstrap-only after first contact). Empty values never clobber.
    /// U1 config-lock: fields whose userOverride flag is set are skipped — never clobbered.
    @discardableResult
    public func refreshFromBrain(
        fetch: @Sendable (BrainClient) async throws -> PairingConfig = { try await $0.pairingConfig() }
    ) async -> Bool {
        guard let client = makeClient() else { return false }
        guard let cfg = try? await fetch(client) else { return false }
        if let primary = cfg.hosts.first, !primary.isEmpty, !isOverridden(.host) { setHost(primary) }
        if cfg.hosts.count > 1, !cfg.hosts[1].isEmpty { defaults.set(cfg.hosts[1], forKey: fallbackHostKey) }
        if let bff = cfg.newsroomBFFHost, !bff.isEmpty { defaults.set(bff, forKey: bffHostKey) }
        if !cfg.token.value.isEmpty, !isOverridden(.token) { setToken(cfg.token.value) }
        if let ing = cfg.ingestToken?.value, !ing.isEmpty, !isOverridden(.ingestToken) { setIngestToken(ing) }
        return true
    }

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

    /// E9 §2 — authed request to the brain AI proxy. nil ⇔ not provisioned (no usable
    /// host+token anywhere): callers surface BrainAIState.notProvisioned, never a raw error.
    public func aiMessagesRequest(body: Data, app: String, task: String, timeout: TimeInterval = 60) -> URLRequest? {
        authedPOST(path: "v1/ai/messages", body: body, timeout: timeout).map { req in
            var r = req
            r.setValue(app, forHTTPHeaderField: "x-lodestar-app")
            r.setValue(task, forHTTPHeaderField: "x-lodestar-task")
            return r
        }
    }

    /// E9 §3 — capability checklist report (fire-and-forget on each sync).
    public func capabilitiesReportRequest(body: Data, timeout: TimeInterval = 15) -> URLRequest? {
        authedPOST(path: "pairing/capabilities", body: body, timeout: timeout)
    }

    private func authedPOST(path: String, body: Data, timeout: TimeInterval) -> URLRequest? {
        let snapshotToken = token
        guard let base = baseURL, let snapshotToken, !snapshotToken.isEmpty else { return nil }
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("Bearer \(snapshotToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        return req
    }
}
