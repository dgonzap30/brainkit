import Foundation
import BrainKit

/// Result of a connection probe, surfaced as a status dot in BrainSettingsCard.
public enum BrainConnectionStatus: Equatable, Sendable {
    case unknown        // not tested since the last edit
    case unconfigured   // host and/or token missing — nothing to test
    case checking       // probe in flight
    case ok             // brain answered /health 200
    case unreachable    // probe failed (offline, wrong host/token, brain down)
}

/// The testable logic behind `BrainSettingsCard`. Loads the current `PluginConfig`, normalizes and
/// persists edits on `save()`, and probes the brain on `testConnection()` against the *edited* values
/// (so the user tests what they typed) without persisting them — only `save()` writes. The SwiftUI card
/// is a thin shell binding to `host`/`token`/`ingestToken` and rendering `status`.
@MainActor
@Observable
public final class BrainSettingsModel {
    public var host: String
    public var token: String
    public var ingestToken: String
    public private(set) var status: BrainConnectionStatus = .unknown

    @ObservationIgnored private let config: PluginConfig
    @ObservationIgnored private let healthCheck: (BrainClient) async -> Bool

    /// `healthCheck` is injectable so tests probe without a network; it defaults to a real `/health`.
    public init(config: PluginConfig, healthCheck: @escaping (BrainClient) async -> Bool = { await $0.health() }) {
        self.config = config
        self.healthCheck = healthCheck
        host = config.host ?? ""
        token = config.token ?? ""
        ingestToken = config.ingestToken ?? ""
    }

    /// Persist the normalized fields (whitespace trimmed; empty → cleared) and invalidate any prior
    /// test result — the saved values may differ from what was last probed.
    public func save() {
        config.setHost(normalized(host))
        config.setToken(normalized(token))
        config.setIngestToken(normalized(ingestToken))
        status = .unknown
    }

    /// Probe the brain using the currently-edited host + front-door token, without saving them.
    public func testConnection() async {
        guard let host = normalized(host), let url = config.baseURL(forHost: host),
              let token = normalized(token) else { status = .unconfigured; return }
        status = .checking
        status = await healthCheck(BrainClient(baseURL: url, token: token)) ? .ok : .unreachable
    }

    private func normalized(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
