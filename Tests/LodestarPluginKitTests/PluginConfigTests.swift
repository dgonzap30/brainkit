import XCTest
import BrainKit
@testable import LodestarPluginKit

/// E2-3 — PluginConfig generalizes ReachCore's ReachConfig: same host→baseURL logic and makeClient
/// snapshot behaviour, but with the storage keys parameterised (defaults equal to ReachConfig's
/// constants, so Reach adopts it with zero behaviour change). We assert the concrete expected output
/// rather than importing ReachConfig — BrainKit must not depend on ReachCore (ReachCore→BrainKit already).
private final class InMemoryKeychain: KeychainStore, @unchecked Sendable {
    private var store: [String: String] = [:]
    func string(forKey key: String) -> String? { store[key] }
    func set(_ value: String?, forKey key: String) {
        if let value { store[key] = value } else { store.removeValue(forKey: key) }
    }
}

final class PluginConfigTests: XCTestCase {
    private func config(host: String? = nil, token: String? = nil, ingest: String? = nil) -> PluginConfig {
        let defaults = UserDefaults(suiteName: "plugin-config-test-\(UUID().uuidString)")!
        let cfg = PluginConfig(keychain: InMemoryKeychain(), defaults: defaults)
        cfg.setHost(host); cfg.setToken(token); cfg.setIngestToken(ingest)
        return cfg
    }

    func testDefaultKeysMatchReachConfigConstants() {
        XCTAssertEqual(PluginConfig.defaultTokenKey, "front_door_token")
        XCTAssertEqual(PluginConfig.defaultIngestTokenKey, "ingest_token")
        XCTAssertEqual(PluginConfig.defaultHostKey, "mini_host")
        XCTAssertEqual(PluginConfig.defaultPort, 4317)
    }

    func testBareHostBecomesHttpOnDefaultPort() {
        XCTAssertEqual(config(host: "mini").baseURL, URL(string: "http://mini:4317"))
    }
    func testHostWithPortIsHttp() {
        XCTAssertEqual(config(host: "mini:8080").baseURL, URL(string: "http://mini:8080"))
    }
    func testFullURLIsPassedThrough() {
        XCTAssertEqual(config(host: "https://brain.example.com").baseURL, URL(string: "https://brain.example.com"))
    }
    func testEmptyOrWhitespaceHostIsNil() {
        XCTAssertNil(config(host: "   ").baseURL)
        XCTAssertNil(config().baseURL)
    }

    func testMakeClientUsesBaseURLAndToken() {
        let client = config(host: "mini", token: "tok").makeClient()
        XCTAssertEqual(client?.baseURL, URL(string: "http://mini:4317"))
        XCTAssertEqual(client?.token, "tok")
    }
    func testMakeClientNilWithoutToken() { XCTAssertNil(config(host: "mini").makeClient()) }
    func testMakeClientNilWithoutHost() { XCTAssertNil(config(token: "tok").makeClient()) }

    func testIsConfiguredRequiresBaseURLAndToken() {
        XCTAssertTrue(config(host: "mini", token: "tok").isConfigured)
        XCTAssertFalse(config(host: "mini").isConfigured)
        XCTAssertFalse(config(token: "tok").isConfigured)
    }

    func testIngestTokenStoredUnderConfiguredKey() {
        XCTAssertEqual(config(ingest: "ing").ingestToken, "ing")
    }

    func testCustomKeysAreHonoured() {
        let defaults = UserDefaults(suiteName: "plugin-config-custom-\(UUID().uuidString)")!
        let cfg = PluginConfig(keychain: InMemoryKeychain(), defaults: defaults,
                               tokenKey: "temper_token", ingestTokenKey: "temper_ingest", hostKey: "temper_host")
        cfg.setToken("t"); cfg.setHost("mini")
        XCTAssertEqual(defaults.string(forKey: "temper_host"), "mini")
        XCTAssertEqual(cfg.token, "t")
    }
}
