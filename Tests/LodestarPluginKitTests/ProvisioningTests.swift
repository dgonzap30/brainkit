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
    func testAdoptBundleProvisioningWithNilIngestTokenPreservesExistingKeychainToken() {
        // Asymmetry vs. host clearing (below) is intended: adoptBundleProvisioning only ever
        // *adds* an ingest token, never removes one, because a redeploy's plist may simply omit
        // it while a previously-adopted ingest token remains valid.
        let cfg = freshConfig()
        _ = cfg.adoptBundleProvisioning(record())
        XCTAssertEqual(cfg.ingestToken, "ing-a")
        let plist: [String: Any] = [
            "schemaVersion": 1, "brainHost": "http://lojik-mini:4317",
            "frontDoorToken": "tok-b", "provisionedAt": "2026-07-10T09:00:00Z",
        ]
        let data = try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let noIngestRecord = ProvisioningRecord(plistData: data)!
        XCTAssertTrue(cfg.adoptBundleProvisioning(noIngestRecord))
        XCTAssertEqual(cfg.token, "tok-b")
        XCTAssertEqual(cfg.ingestToken, "ing-a") // preserved, not cleared
    }

    func testRefreshFromBrainAppliesAuthorityWithoutTouchingBundleStamp() async {
        let cfg = freshConfig()
        _ = cfg.adoptBundleProvisioning(record())
        let stamp = cfg.adoptedProvisionedAt
        let served = PairingConfig(schemaVersion: 1, hosts: ["http://new-primary:4317", "http://new-fallback:4317"],
                                   newsroomBFFHost: "https://new-bff", token: .init(value: "rotated"),
                                   ingestToken: .init(value: "ing-rotated"), authenticatedWith: "previous")
        let ok = await cfg.refreshFromBrain(fetch: { _ in served })
        XCTAssertTrue(ok)
        XCTAssertEqual(cfg.host, "http://new-primary:4317")
        XCTAssertEqual(cfg.fallbackHost, "http://new-fallback:4317")
        XCTAssertEqual(cfg.newsroomBFFHost, "https://new-bff")
        XCTAssertEqual(cfg.token, "rotated")
        XCTAssertEqual(cfg.ingestToken, "ing-rotated")
        XCTAssertEqual(cfg.adoptedProvisionedAt, stamp) // authority refresh ≠ bundle generation
    }
    func testRefreshFromBrainFailureChangesNothing() async {
        let cfg = freshConfig()
        _ = cfg.adoptBundleProvisioning(record())
        let ok = await cfg.refreshFromBrain(fetch: { _ in throw BrainError.unreachable })
        XCTAssertFalse(ok)
        XCTAssertEqual(cfg.token, "tok-a")
    }
    func testRefreshNotConfiguredReturnsFalse() async {
        let ok = await freshConfig().refreshFromBrain(fetch: { _ in XCTFail("must not fetch"); throw BrainError.unreachable })
        XCTAssertFalse(ok)
    }
    func testRefreshNeverClobbersWithEmptyToken() async {
        let cfg = freshConfig()
        _ = cfg.adoptBundleProvisioning(record())
        let served = PairingConfig(schemaVersion: 1, hosts: [], newsroomBFFHost: nil,
                                   token: .init(value: ""), ingestToken: nil, authenticatedWith: "current")
        _ = await cfg.refreshFromBrain(fetch: { _ in served })
        XCTAssertEqual(cfg.token, "tok-a")
        XCTAssertEqual(cfg.host, "http://lojik-mini:4317") // empty hosts list leaves host alone
    }
}
