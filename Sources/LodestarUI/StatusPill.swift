import SwiftUI

/// Semantic state for a `StatusPill`. `stale` is deliberately monochrome —
/// stale is "aging data", not an alarm; hue stays reserved for ok/warn/error.
public enum StatusPillKind: Sendable {
    case ok, warn, error, stale

    public var color: Color {
        switch self {
        case .ok: return LodestarColor.statusOK
        case .warn: return LodestarColor.statusWarn
        case .error: return LodestarColor.statusError
        case .stale: return Color(white: 0.55)
        }
    }
}

/// Small capsule status indicator: colored dot + label.
/// Label carries the specifics ("Synced", "degraded: proxy 502", "checked 2h ago").
public struct StatusPill: View {
    let kind: StatusPillKind
    let label: String

    public init(kind: StatusPillKind, label: String) {
        self.kind = kind
        self.label = label
    }

    public var body: some View {
        HStack(spacing: LodestarMetrics.spacingXS + 2) {
            Circle()
                .fill(kind.color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, LodestarMetrics.spacingS + 2)
        .padding(.vertical, LodestarMetrics.spacingXS + 1)
        .background(LodestarColor.elevated, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}
