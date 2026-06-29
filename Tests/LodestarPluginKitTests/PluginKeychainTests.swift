import XCTest
@testable import LodestarPluginKit

/// E2-3 — PluginKeychain is a verbatim port of ReachCore's Keychain (KeychainStore protocol +
/// SystemKeychain), only the default service string differs. Following ReachCore's precedent we test
/// the protocol contract via an in-memory store and do NOT exercise SystemKeychain's Security I/O in CI.
final class PluginKeychainTests: XCTestCase {
    private final class InMemoryKeychain: KeychainStore, @unchecked Sendable {
        private var store: [String: String] = [:]
        func string(forKey key: String) -> String? { store[key] }
        func set(_ value: String?, forKey key: String) {
            if let value { store[key] = value } else { store.removeValue(forKey: key) }
        }
    }

    func testSetThenGetRoundTrips() {
        let kc = InMemoryKeychain()
        kc.set("v", forKey: "k")
        XCTAssertEqual(kc.string(forKey: "k"), "v")
    }

    func testSetNilRemovesTheKey() {
        let kc = InMemoryKeychain()
        kc.set("v", forKey: "k")
        kc.set(nil, forKey: "k")
        XCTAssertNil(kc.string(forKey: "k"))
    }

    func testSystemKeychainConstructsWithPluginServiceDefault() {
        // Constructing does not touch the keychain; this just pins that the default-service initializer exists.
        _ = SystemKeychain()
        _ = SystemKeychain(service: "com.lojik.lodestar.plugin")
    }
}
