#if canImport(SwiftUI)
import SwiftUI

/// E9 §4 — the ONE shared brain-connection state every plugin app renders for AI features.
/// Callers map transport failures (URLError, no response) to .offline themselves and pass
/// real HTTP statuses to classify. Upstream AI errors (429/5xx from Anthropic) are NOT
/// connection states — they pass through typed and status-preserving.
public enum BrainAIState: Equatable, Sendable {
    case ok, notProvisioned, offline, reconnectNeeded

    public static func classify(httpStatus: Int?) -> BrainAIState {
        guard let httpStatus else { return .offline }
        return httpStatus == 401 ? .reconnectNeeded : .ok
    }

    public var userMessage: String {
        switch self {
        case .ok: return ""
        case .notProvisioned: return "Not provisioned — rerun deploy-phone."
        case .offline: return "Brain offline — check Tailscale and the mini."
        case .reconnectNeeded: return "Reconnect needed — the token rotated past its grace window. Redeploy (or paste the new token in Settings)."
        }
    }
}

/// Minimal shared banner. Apps place it above their AI surface when state != .ok.
public struct BrainAIStateBanner: View {
    public let state: BrainAIState
    public init(state: BrainAIState) { self.state = state }
    public var body: some View {
        if state != .ok {
            Label(state.userMessage, systemImage: "brain.head.profile")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
#endif
