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

final class BrainAIStateTests: XCTestCase {
    private func config(host: String? = "lojik-mini", token: String? = "tok") -> PluginConfig {
        let cfg = PluginConfig(keychain: InMemoryKeychain(),
                               defaults: UserDefaults(suiteName: "ai-req-\(UUID().uuidString)")!)
        cfg.setHost(host); cfg.setToken(token)
        return cfg
    }
    func testAIRequestShape() throws {
        let req = try XCTUnwrap(config().aiMessagesRequest(body: Data("{}".utf8), app: "ledger", task: "parse"))
        XCTAssertEqual(req.url?.absoluteString, "http://lojik-mini:4317/v1/ai/messages")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-lodestar-app"), "ledger")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-lodestar-task"), "parse")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }
    func testAIRequestNilWhenUnprovisioned() {
        XCTAssertNil(config(token: nil).aiMessagesRequest(body: Data(), app: "ledger", task: "t"))
        XCTAssertNil(config(host: nil).aiMessagesRequest(body: Data(), app: "ledger", task: "t"))
    }
    func testCapabilitiesRequestPath() throws {
        let req = try XCTUnwrap(config().capabilitiesReportRequest(body: Data("{}".utf8)))
        XCTAssertEqual(req.url?.absoluteString, "http://lojik-mini:4317/pairing/capabilities")
    }
    func testClassify() {
        XCTAssertEqual(BrainAIState.classify(httpStatus: nil), .offline)
        XCTAssertEqual(BrainAIState.classify(httpStatus: 401), .reconnectNeeded)
        XCTAssertEqual(BrainAIState.classify(httpStatus: 200), .ok)
        XCTAssertEqual(BrainAIState.classify(httpStatus: 503), .ok) // 503 is a typed upstream error, not a connection state
    }
}
