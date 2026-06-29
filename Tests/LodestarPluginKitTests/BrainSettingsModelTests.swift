import XCTest
import BrainKit
@testable import LodestarPluginKit

/// E2-4 — the testable logic behind BrainSettingsCard: load current config, normalize+persist on save,
/// and a connection-test state machine that targets the *edited* values without persisting them. The
/// SwiftUI card is a thin shell over this; the behaviour lives here where it can be tested.
private final class InMemoryKeychain: KeychainStore, @unchecked Sendable {
    private var store: [String: String] = [:]
    func string(forKey key: String) -> String? { store[key] }
    func set(_ value: String?, forKey key: String) {
        if let value { store[key] = value } else { store.removeValue(forKey: key) }
    }
}

@MainActor
final class BrainSettingsModelTests: XCTestCase {
    private func config(host: String? = nil, token: String? = nil, ingest: String? = nil) -> PluginConfig {
        let defaults = UserDefaults(suiteName: "brain-settings-test-\(UUID().uuidString)")!
        let cfg = PluginConfig(keychain: InMemoryKeychain(), defaults: defaults)
        cfg.setHost(host); cfg.setToken(token); cfg.setIngestToken(ingest)
        return cfg
    }

    func testInitLoadsExistingConfigValues() {
        let m = BrainSettingsModel(config: config(host: "mini", token: "tok", ingest: "ing"))
        XCTAssertEqual(m.host, "mini")
        XCTAssertEqual(m.token, "tok")
        XCTAssertEqual(m.ingestToken, "ing")
        XCTAssertEqual(m.status, .unknown)
    }

    func testInitDefaultsToEmptyStringsWhenUnset() {
        let m = BrainSettingsModel(config: config())
        XCTAssertEqual(m.host, "")
        XCTAssertEqual(m.token, "")
        XCTAssertEqual(m.ingestToken, "")
    }

    func testSaveNormalizesWhitespaceAndPersists() {
        let cfg = config()
        let m = BrainSettingsModel(config: cfg)
        m.host = "  mini  "; m.token = "tok"; m.ingestToken = "   "
        m.save()
        XCTAssertEqual(cfg.host, "mini")        // trimmed
        XCTAssertEqual(cfg.token, "tok")
        XCTAssertNil(cfg.ingestToken)           // whitespace-only → nil (cleared)
    }

    func testTestConnectionReportsOkWhenHealthy() async {
        let m = BrainSettingsModel(config: config(), healthCheck: { _ in true })
        m.host = "mini"; m.token = "tok"
        await m.testConnection()
        XCTAssertEqual(m.status, .ok)
    }

    func testTestConnectionReportsUnreachableWhenUnhealthy() async {
        let m = BrainSettingsModel(config: config(), healthCheck: { _ in false })
        m.host = "mini"; m.token = "tok"
        await m.testConnection()
        XCTAssertEqual(m.status, .unreachable)
    }

    func testTestConnectionUnconfiguredWhenMissingHostOrToken() async {
        let m = BrainSettingsModel(config: config(), healthCheck: { _ in true })
        m.host = ""; m.token = "tok"
        await m.testConnection()
        XCTAssertEqual(m.status, .unconfigured)
    }

    func testTestConnectionTargetsEditedValuesWithoutPersisting() async {
        let cfg = config()                       // nothing stored
        let m = BrainSettingsModel(config: cfg, healthCheck: { _ in true })
        m.host = "mini"; m.token = "tok"
        await m.testConnection()
        XCTAssertEqual(m.status, .ok)            // built a client from the edited (unsaved) values
        XCTAssertNil(cfg.host)                   // a connection test must NOT persist
        XCTAssertNil(cfg.token)
    }

    func testEditingAfterATestResetsStatusToUnknownOnSave() async {
        let m = BrainSettingsModel(config: config(), healthCheck: { _ in true })
        m.host = "mini"; m.token = "tok"
        await m.testConnection()
        XCTAssertEqual(m.status, .ok)
        m.save()                                 // saving new values invalidates the prior test result
        XCTAssertEqual(m.status, .unknown)
    }
}
