import Foundation

/// Generic offline outbox — a faithful generalization of ReachCore's HealthOutbox so every limb
/// (Temper, future apps) gets the same durable, bounded pending-push queue instead of hand-rolling one.
/// `OutboxState` is the pure, Codable, testable queue logic; `OutboxQueue` is the atomic-JSON file store
/// wrapping it. Semantics are identical to HealthOutbox, parameterised only by the element type:
///   • dedup is **keep-first** — a re-enqueued duplicate id is ignored, the original (and its enqueue
///     timestamp) is preserved, so age-out reflects when the item was *first* queued;
///   • eviction runs **age before count**;
///   • the age boundary is inclusive (`enqueuedAt >= cutoff` is kept);
///   • `enqueue` returns the ids it evicted, for logging.
///
/// The dedup key is supplied by the caller (a per-enqueue `id:` on the pure state, or a `dedupeKey:`
/// closure on the queue) rather than a protocol on `Item`, keeping `Item`'s constraints to
/// `Codable & Equatable & Sendable` and leaving key derivation where the domain knowledge lives.

public struct OutboxItem<Item: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public let id: String
    public let item: Item
    public let enqueuedAt: Date

    public init(id: String, item: Item, enqueuedAt: Date) {
        self.id = id; self.item = item; self.enqueuedAt = enqueuedAt
    }
}

/// Pure queue logic — dedup by id, FIFO, bounded by count + age. No disk. Tested independently.
public struct OutboxState<Item: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public private(set) var items: [OutboxItem<Item>] = []
    public init(items: [OutboxItem<Item>] = []) { self.items = items }

    /// Insert (dedup by id, keep-first), then evict items older than maxAge and any beyond maxCount
    /// (oldest first). Returns the ids evicted (for logging).
    @discardableResult
    public mutating func enqueue(_ item: Item, id: String, maxCount: Int, maxAge: TimeInterval, now: Date) -> [String] {
        if !items.contains(where: { $0.id == id }) {
            items.append(OutboxItem(id: id, item: item, enqueuedAt: now))
        }
        var evicted: [String] = []
        let ageCutoff = now.addingTimeInterval(-maxAge)
        let (fresh, stale) = items.stablePartition { $0.enqueuedAt >= ageCutoff }
        evicted += stale.map { $0.id }
        items = fresh
        if items.count > maxCount {
            let overflow = items.count - maxCount
            evicted += items.prefix(overflow).map { $0.id }
            items.removeFirst(overflow)
        }
        return evicted
    }

    public func peek(limit: Int) -> [OutboxItem<Item>] { Array(items.prefix(limit)) }

    public mutating func remove(id: String) { items.removeAll { $0.id == id } }   // idempotent
}

private extension Array {
    /// Returns (kept, dropped) preserving order; `keep` true → kept.
    func stablePartition(_ keep: (Element) -> Bool) -> ([Element], [Element]) {
        var a: [Element] = [], b: [Element] = []
        for e in self { if keep(e) { a.append(e) } else { b.append(e) } }
        return (a, b)
    }
}

/// Atomic-JSON file store mirroring HealthOutbox. Defaults bounded at 200 items / 14 days. The
/// `dedupeKey` closure derives an item's stable id (e.g. `{ "\($0.deviceId):\($0.exportedAt)" }`).
public final class OutboxQueue<Item: Codable & Equatable & Sendable>: @unchecked Sendable {
    private let fileURL: URL
    private let maxCount: Int
    private let maxAge: TimeInterval
    private let dedupeKey: (Item) -> String
    private let lock = NSLock()
    private var state = OutboxState<Item>()

    private static var encoder: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
    private static var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }

    public init(directory: URL? = nil,
                fileName: String = "outbox.json",
                maxCount: Int = 200,
                maxAge: TimeInterval = 14 * 86_400,
                dedupeKey: @escaping (Item) -> String) {
        let dir = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LodestarPlugin", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent(fileName)
        self.maxCount = maxCount; self.maxAge = maxAge; self.dedupeKey = dedupeKey
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? Self.decoder.decode(OutboxState<Item>.self, from: data) { state = loaded }
    }

    @discardableResult
    public func enqueue(_ item: Item, now: Date = Date()) -> [String] {
        lock.lock(); defer { lock.unlock() }
        let evicted = state.enqueue(item, id: dedupeKey(item), maxCount: maxCount, maxAge: maxAge, now: now)
        save()
        return evicted
    }

    public func peek(limit: Int) -> [OutboxItem<Item>] { lock.lock(); defer { lock.unlock() }; return state.peek(limit: limit) }
    public func remove(id: String) { lock.lock(); defer { lock.unlock() }; state.remove(id: id); save() }

    private func save() { if let data = try? Self.encoder.encode(state) { try? data.write(to: fileURL, options: .atomic) } }
}
