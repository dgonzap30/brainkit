import XCTest
import BrainKit
@testable import LodestarPluginKit

private final class InMemoryKeychain: KeychainStore, @unchecked Sendable {
    private var store: [String: String] = [:]
    func string(forKey key: String) -> String? { store[key] }
    func set(_ value: String?, forKey key: String) {
        if let value { store[key] = value } else { store.removeValue(forKey: key) }
    }
}

final class ProvisioningTests: XCTestCase {
    private func freshConfig() -> PluginConfig {
        PluginConfig(keychain: InMemoryKeychain(),
                     defaults: UserDefaults(suiteName: "prov-test-\(UUID().uuidString)")!)
    }
    private func record(token: String = "tok-a", at iso: String = "2026-07-09T20:00:00Z") -> ProvisioningRecord {
        let plist: [String: Any] = [
            "schemaVersion": 1, "brainHost": "http://lojik-mini:4317",
            "brainHostFallback": "http://100.71.24.86:4317",
            "newsroomBFFHost": "https://lojik-mini.tail8c0ea0.ts.net",
            "frontDoorToken": token, "ingestToken": "ing-a", "provisionedAt": iso,
        ]
        let data = try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        return ProvisioningRecord(plistData: data)!
    }

    func testDecodeFullRecord() {
        let r = record()
        XCTAssertEqual(r.brainHost, "http://lojik-mini:4317")
        XCTAssertEqual(r.frontDoorToken, "tok-a")
        XCTAssertEqual(r.ingestToken, "ing-a")
        XCTAssertEqual(r.provisionedAt, ISO8601DateFormatter().date(from: "2026-07-09T20:00:00Z"))
    }
    func testDecodeRejectsMissingRequiredFields() {
        let bad: [String: Any] = ["schemaVersion": 1, "brainHost": "http://x:1"]
        let data = try! PropertyListSerialization.data(fromPropertyList: bad, format: .xml, options: 0)
        XCTAssertNil(ProvisioningRecord(plistData: data))
    }
    func testFreshInstallAdopts() {
        let cfg = freshConfig()
        XCTAssertTrue(cfg.adoptBundleProvisioning(record()))
        XCTAssertEqual(cfg.host, "http://lojik-mini:4317")
        XCTAssertEqual(cfg.token, "tok-a")
        XCTAssertEqual(cfg.ingestToken, "ing-a")
        XCTAssertEqual(cfg.fallbackHost, "http://100.71.24.86:4317")
        XCTAssertEqual(cfg.newsroomBFFHost, "https://lojik-mini.tail8c0ea0.ts.net")
    }
    func testOlderOrSameBundleDoesNotClobberManualEdits() {
        let cfg = freshConfig()
        XCTAssertTrue(cfg.adoptBundleProvisioning(record(token: "tok-a")))
        cfg.setToken("manually-pasted")
        XCTAssertFalse(cfg.adoptBundleProvisioning(record(token: "tok-a")))       // same stamp
        XCTAssertEqual(cfg.token, "manually-pasted")
    }
    func testNewerBundleReAdopts() {
        let cfg = freshConfig()
        _ = cfg.adoptBundleProvisioning(record(token: "tok-a", at: "2026-07-09T20:00:00Z"))
        XCTAssertTrue(cfg.adoptBundleProvisioning(record(token: "tok-b", at: "2026-07-10T09:00:00Z")))
        XCTAssertEqual(cfg.token, "tok-b")
    }
    func testKeychainWipeReAdoptsSilently() {
        let cfg = freshConfig()
        _ = cfg.adoptBundleProvisioning(record())
        cfg.setToken(nil)                                                          // reinstall / wiped keychain
        XCTAssertTrue(cfg.adoptBundleProvisioning(record()))                       // same stamp, empty token
        XCTAssertEqual(cfg.token, "tok-a")
    }
    func testNilRecordIsANoop() {
        XCTAssertFalse(freshConfig().adoptBundleProvisioning(nil))
    }
}
