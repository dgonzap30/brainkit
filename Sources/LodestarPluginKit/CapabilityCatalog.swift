import Foundation

/// E9 §3 — the shared setup-checklist machinery every plugin app feeds its own capability
/// rows into. Every row is green or one tap from green.
public enum CapabilityStatus: String, Codable, Equatable, Sendable {
    case ok, actionNeeded = "action-needed", unknown
}

/// Spec §3: a capability counts as heard-from when its channel delivered within this window.
public let heardFromWindowDays = 7

public struct Capability: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String?
    public let detect: @Sendable () async -> CapabilityStatus
    public let fix: (@MainActor () -> Void)?
    public init(id: String, title: String, detail: String? = nil,
                detect: @escaping @Sendable () async -> CapabilityStatus,
                fix: (@MainActor () -> Void)? = nil) {
        self.id = id; self.title = title; self.detail = detail; self.detect = detect; self.fix = fix
    }
}

public struct CapabilityReportEntry: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let status: CapabilityStatus
    public let checkedAt: Date
    public init(id: String, title: String, status: CapabilityStatus, checkedAt: Date) {
        self.id = id; self.title = title; self.status = status; self.checkedAt = checkedAt
    }
}

/// JSON body for POST /pairing/capabilities — must stay in lockstep with the brain's
/// parseCapabilityReport (brain/src/pairing/capabilities.ts).
public func makeCapabilityReportBody(app: String, entries: [CapabilityReportEntry]) -> Data {
    struct Report: Encodable { let app: String; let capabilities: [CapabilityReportEntry] }
    let enc = JSONEncoder()
    enc.dateEncodingStrategy = .iso8601
    return (try? enc.encode(Report(app: app, capabilities: entries))) ?? Data()
}

#if canImport(SwiftUI)
import SwiftUI

/// The shared setup checklist (spec §3): every row green or one tap from green.
public struct CapabilityChecklistView: View {
    public let capabilities: [Capability]
    public let onChecked: (([CapabilityReportEntry]) -> Void)?
    @State private var statuses: [String: CapabilityStatus] = [:]

    public init(capabilities: [Capability], onChecked: (([CapabilityReportEntry]) -> Void)? = nil) {
        self.capabilities = capabilities
        self.onChecked = onChecked
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(capabilities) { cap in
                HStack(spacing: 10) {
                    statusIcon(statuses[cap.id] ?? .unknown)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(cap.title).font(.subheadline)
                        if let detail = cap.detail { Text(detail).font(.caption2).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    if statuses[cap.id] == .actionNeeded, let fix = cap.fix {
                        Button("Fix") { fix(); Task { await runChecks() } }
                            .font(.caption.bold())
                            .buttonStyle(.borderedProminent)
                            .controlSize(.mini)
                    }
                }
            }
        }
        .task { await runChecks() }
        .refreshable { await runChecks() }
    }

    @ViewBuilder private func statusIcon(_ s: CapabilityStatus) -> some View {
        switch s {
        case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .actionNeeded: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        case .unknown: Image(systemName: "minus.circle").foregroundStyle(.secondary)
        }
    }

    @MainActor private func runChecks() async {
        var entries: [CapabilityReportEntry] = []
        for cap in capabilities {
            let status = await cap.detect()
            statuses[cap.id] = status
            entries.append(.init(id: cap.id, title: cap.title, status: status, checkedAt: Date()))
        }
        onChecked?(entries)
    }
}
#endif
