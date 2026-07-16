import XCTest
import BrainKit
@testable import LodestarPluginKit

/// U1 §config-lock — per-field userOverride flags + refresh-skips-overridden.
/// Matrix: default state, set/clear persistence, refresh skip per field,
/// reset→next-refresh-restores, adopt-clears-flags.
private final class InMemoryKeychain: KeychainStore, @unchecked Sendable {
    private var store: [String: String] = [:]
    func string(forKey key: String) -> String? { store[key] }
    func set(_ value: String?, forKey key: String) {
        if let value { store[key] = value } else { store.removeValue(forKey: key) }
    }
}

final class ConfigLockTests: XCTestCase {
    private func config(host: String? = "mini", token: String? = "tok") -> PluginConfig {
        let cfg = PluginConfig(keychain: InMemoryKeychain(),
                               defaults: UserDefaults(suiteName: "config-lock-test-\(UUID().uuidString)")!)
        cfg.setHost(host); cfg.setToken(token)
        return cfg
    }

    /// A canned brain answer for refreshFromBrain's fetch seam
    /// (PairingConfig's real memberwise init — PairingTypes.swift:17).
    private func brainConfig() -> PairingConfig {
        PairingConfig(schemaVersion: 1,
                      hosts: ["brain-host", "fallback-host"],
                      newsroomBFFHost: "bff-host",
                      token: .init(value: "brain-token"),
                      ingestToken: .init(value: "brain-ingest"),
                      authenticatedWith: "front_door")
    }

    /// ProvisioningRecord has no memberwise init — build via plist data,
    /// same pattern as ProvisioningTests.record(token:at:).
    private func record(host: String = "bundle-host", token: String = "bundle-token",
                        at iso: String = "2026-07-16T12:00:00Z") -> ProvisioningRecord {
        let plist: [String: Any] = [
            "schemaVersion": 1, "brainHost": host,
            "frontDoorToken": token, "provisionedAt": iso,
        ]
        let data = try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        return ProvisioningRecord(plistData: data)!
    }

    func testFieldsDefaultToNotOverridden() {
        let cfg = config()
        for field in ProvisionedField.allCases {
            XCTAssertFalse(cfg.isOverridden(field))
        }
    }

    func testSetOverriddenPersistsPerField() {
        let cfg = config()
        cfg.setOverridden(.host, true)
        XCTAssertTrue(cfg.isOverridden(.host))
        XCTAssertFalse(cfg.isOverridden(.token))
        XCTAssertFalse(cfg.isOverridden(.ingestToken))
        cfg.setOverridden(.host, false)
        XCTAssertFalse(cfg.isOverridden(.host))
    }

    func testRefreshSkipsOverriddenHostButAppliesRest() async {
        let cfg = config()
        cfg.setOverridden(.host, true)
        cfg.setHost("my-manual-host")
        let brain = brainConfig()
        let ok = await cfg.refreshFromBrain(fetch: { _ in brain })
        XCTAssertTrue(ok)
        XCTAssertEqual(cfg.host, "my-manual-host")          // skipped
        XCTAssertEqual(cfg.token, "brain-token")            // applied
        XCTAssertEqual(cfg.ingestToken, "brain-ingest")     // applied
    }

    func testRefreshSkipsOverriddenTokenAndIngest() async {
        let cfg = config()
        cfg.setOverridden(.token, true)
        cfg.setOverridden(.ingestToken, true)
        cfg.setToken("my-token"); cfg.setIngestToken("my-ingest")
        let brain = brainConfig()
        _ = await cfg.refreshFromBrain(fetch: { _ in brain })
        XCTAssertEqual(cfg.host, "brain-host")              // applied
        XCTAssertEqual(cfg.token, "my-token")               // skipped
        XCTAssertEqual(cfg.ingestToken, "my-ingest")        // skipped
    }

    func testResetRestoresBrainValueOnNextRefresh() async {
        let cfg = config()
        cfg.setOverridden(.host, true)
        cfg.setHost("my-manual-host")
        let brain = brainConfig()
        _ = await cfg.refreshFromBrain(fetch: { _ in brain })
        XCTAssertEqual(cfg.host, "my-manual-host")
        cfg.setOverridden(.host, false)                     // reset to provisioned
        _ = await cfg.refreshFromBrain(fetch: { _ in brain })
        XCTAssertEqual(cfg.host, "brain-host")
    }

    func testAdoptBundleProvisioningClearsOverrideFlags() {
        let cfg = config(token: nil)                        // keychain empty → adopt fires
        cfg.setOverridden(.host, true)
        cfg.setOverridden(.token, true)
        XCTAssertTrue(cfg.adoptBundleProvisioning(record()))
        for field in ProvisionedField.allCases {
            XCTAssertFalse(cfg.isOverridden(field), "\(field) flag must clear on adopt (redeploy wins)")
        }
        XCTAssertEqual(cfg.host, "bundle-host")
    }

    func testSkippedAdoptLeavesFlagsAlone() {
        let cfg = config(token: nil)
        // First adopt stamps adoptedProvisionedAt and fills the keychain.
        XCTAssertTrue(cfg.adoptBundleProvisioning(record(at: "2026-07-16T12:00:00Z")))
        cfg.setOverridden(.host, true)
        // Older record + non-empty keychain → adopt skips; the flag must survive.
        XCTAssertFalse(cfg.adoptBundleProvisioning(record(host: "stale-host", at: "2026-07-01T00:00:00Z")))
        XCTAssertTrue(cfg.isOverridden(.host), "a skipped adopt must not touch flags")
        XCTAssertEqual(cfg.host, "bundle-host")
    }
}
