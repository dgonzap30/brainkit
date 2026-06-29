import XCTest
@testable import LodestarPluginKit

/// E2-3 — generic offline outbox, a faithful generalization of ReachCore's HealthOutbox. These mirror
/// HealthOutboxTests exactly (keep-first dedup, age-before-count eviction, `>=` age boundary kept,
/// enqueue returns evicted ids) so OutboxQueue<HealthSample> is a drop-in replacement in E7.
private struct Sample: Codable, Equatable, Sendable {
    let key: String
    let payload: String
}

final class PluginOutboxTests: XCTestCase {
    private func item(_ key: String, _ payload: String = "p") -> Sample { Sample(key: key, payload: payload) }
    private func t(_ s: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(s)) }

    // MARK: Pure state

    func testEnqueueDedupesByIdKeepingFirst() {
        var st = OutboxState<Sample>()
        _ = st.enqueue(item("k", "first"), id: "k", maxCount: 100, maxAge: 86_400, now: t(100))
        let evicted = st.enqueue(item("k", "second"), id: "k", maxCount: 100, maxAge: 86_400, now: t(200))
        XCTAssertEqual(st.items.count, 1)
        XCTAssertEqual(st.items.first?.item.payload, "first", "keep-first: a duplicate key must NOT replace the original")
        XCTAssertEqual(st.items.first?.enqueuedAt, t(100), "original timestamp preserved — age is not refreshed by a re-enqueue")
        XCTAssertTrue(evicted.isEmpty)
    }

    func testPeekIsFifoAndRemoveIsIdempotent() {
        var st = OutboxState<Sample>()
        _ = st.enqueue(item("a"), id: "a", maxCount: 100, maxAge: 86_400, now: t(100))
        _ = st.enqueue(item("b"), id: "b", maxCount: 100, maxAge: 86_400, now: t(200))
        XCTAssertEqual(st.peek(limit: 1).first?.id, "a")
        st.remove(id: "a"); st.remove(id: "a")                       // double-remove → no crash, no underflow
        XCTAssertEqual(st.items.count, 1)
        XCTAssertEqual(st.peek(limit: 1).first?.id, "b")
    }

    func testCountEvictionDropsOldestBeyondCap() {
        var st = OutboxState<Sample>()
        var evicted: [String] = []
        for i in 0..<5 { evicted += st.enqueue(item("e-\(i)"), id: "e-\(i)", maxCount: 3, maxAge: 86_400, now: t(i)) }
        XCTAssertEqual(st.items.map { $0.id }, ["e-2", "e-3", "e-4"])  // oldest dropped
        XCTAssertEqual(evicted.count, 2)
    }

    func testAgeEvictionDropsItemsOlderThanMaxAge() {
        var st = OutboxState<Sample>()
        _ = st.enqueue(item("old"), id: "old", maxCount: 100, maxAge: 60, now: t(0))
        let evicted = st.enqueue(item("new"), id: "new", maxCount: 100, maxAge: 60, now: t(120))  // old is 120s > 60s
        XCTAssertEqual(st.items.map { $0.id }, ["new"])
        XCTAssertEqual(evicted, ["old"])
    }

    func testCombinedAgeAndCountEvictionAgeFirst() {
        // Same scenario as HealthOutboxTests: age must run before count, else the result differs.
        var st = OutboxState<Sample>()
        _ = st.enqueue(item("e-A"), id: "e-A", maxCount: 100, maxAge: 100, now: t(420))
        _ = st.enqueue(item("e-B"), id: "e-B", maxCount: 100, maxAge: 100, now: t(450))
        _ = st.enqueue(item("e-C"), id: "e-C", maxCount: 100, maxAge: 100, now: t(50))   // stale at final cutoff
        _ = st.enqueue(item("e-D"), id: "e-D", maxCount: 2,   maxAge: 100, now: t(500))  // triggers both
        XCTAssertEqual(st.items.map { $0.id }, ["e-B", "e-D"],
                       "age evicts C(stale); count then evicts A(oldest-fresh); B+D survive")
    }

    func testAgeBoundaryExactlyAtMaxAgeIsKept() {
        var st = OutboxState<Sample>()
        _ = st.enqueue(item("boundary"), id: "boundary", maxCount: 100, maxAge: 60, now: t(0))
        // now=t(60): ageCutoff = t(0); boundary.enqueuedAt == cutoff → kept (>= not >)
        let evicted = st.enqueue(item("new"), id: "new", maxCount: 100, maxAge: 60, now: t(60))
        XCTAssertEqual(st.items.map { $0.id }, ["boundary", "new"])
        XCTAssertTrue(evicted.isEmpty, "item exactly at the age boundary must not be evicted")
    }

    // MARK: File-store class

    func testFileStorePersistsAcrossReload() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let a = OutboxQueue<Sample>(directory: dir, fileName: "sample-outbox.json", dedupeKey: { $0.key })
        a.enqueue(item("k"), now: t(100))
        let b = OutboxQueue<Sample>(directory: dir, fileName: "sample-outbox.json", dedupeKey: { $0.key })  // fresh, same dir
        XCTAssertEqual(b.peek(limit: 10).count, 1)
        XCTAssertEqual(b.peek(limit: 10).first?.id, "k")
    }

    func testQueueDerivesIdViaDedupeKeyClosureAndKeepsFirst() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let q = OutboxQueue<Sample>(directory: dir, fileName: "f.json", dedupeKey: { $0.key })
        q.enqueue(item("k", "first"), now: t(1))
        q.enqueue(item("k", "second"), now: t(2))   // same derived key → dedup keep-first
        XCTAssertEqual(q.peek(limit: 10).count, 1)
        XCTAssertEqual(q.peek(limit: 10).first?.item.payload, "first")
        q.remove(id: "k")
        XCTAssertTrue(q.peek(limit: 10).isEmpty)
    }
}
