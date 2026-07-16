import SwiftUI

/// Resolved presentation state for a brain-provisioned connection field.
public enum LockedFieldState: Sendable, Equatable {
    /// Brain-managed and healthy: read-only, lock glyph, provenance line.
    case locked
    /// User explicitly overrode: editable, with Reset-to-provisioned.
    case overridden
    /// Unprovisioned or unhealthy: plain editable (manual fallback path).
    case editable

    /// The spec's matrix. `overridden` wins over health (an explicit user
    /// decision must not disappear when the connection flaps); `locked`
    /// requires provisioned AND healthy; everything else is editable.
    public static func resolve(provisioned: Bool, healthy: Bool, overridden: Bool) -> LockedFieldState {
        if overridden { return .overridden }
        if provisioned && healthy { return .locked }
        return .editable
    }
}

/// A settings row for one brain-provisioned value (host, token, …).
/// Pure UI: state is resolved by the caller (`LockedFieldState.resolve`),
/// mutations flow out through `onOverride` / `onReset`, the value through
/// the binding. No PluginKit dependency by design.
public struct LockedField: View {
    let label: String
    @Binding var value: String
    let secure: Bool
    let state: LockedFieldState
    let provenance: String
    let onOverride: () -> Void
    let onReset: () -> Void

    @State private var confirmingOverride = false

    /// - Parameters:
    ///   - label: row label ("Host", "Front-door token").
    ///   - value: the field's value binding; edited only in non-locked states.
    ///   - secure: render the editable field as a SecureField (tokens).
    ///   - state: resolved lock state (see `LockedFieldState.resolve`).
    ///   - provenance: provisioning source line, e.g. "Provisioned from mini · checked 2m ago".
    ///   - onOverride: called after the user CONFIRMS the override dialog.
    ///   - onReset: called when the user taps Reset to provisioned.
    public init(label: String,
                value: Binding<String>,
                secure: Bool = false,
                state: LockedFieldState,
                provenance: String,
                onOverride: @escaping () -> Void,
                onReset: @escaping () -> Void) {
        self.label = label
        self._value = value
        self.secure = secure
        self.state = state
        self.provenance = provenance
        self.onOverride = onOverride
        self.onReset = onReset
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LodestarMetrics.spacingXS) {
            switch state {
            case .locked:
                HStack(spacing: LodestarMetrics.spacingS) {
                    Text(label)
                    Spacer()
                    Text(displayValue)
                        .font(LodestarType.mono(.footnote))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                    Button("Edit") { confirmingOverride = true }
                        .font(.footnote)
                }
                Text(provenance)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            case .overridden:
                editor
                Button("Reset to provisioned", action: onReset)
                    .font(.footnote)
            case .editable:
                editor
            }
        }
        .confirmationDialog(
            "This value is managed by the brain. Override?",
            isPresented: $confirmingOverride,
            titleVisibility: .visible
        ) {
            Button("Override", role: .destructive, action: onOverride)
            Button("Cancel", role: .cancel) {}
        }
        .accessibilityElement(children: .contain)
    }

    private var displayValue: String {
        secure ? String(repeating: "•", count: min(value.count, 8)) : value
    }

    @ViewBuilder private var editor: some View {
        HStack(spacing: LodestarMetrics.spacingS) {
            Text(label)
            Spacer()
            Group {
                if secure {
                    SecureField(label, text: $value)
                } else {
                    TextField(label, text: $value)
                        .autocorrectionDisabled()
                }
            }
            .multilineTextAlignment(.trailing)
            .font(LodestarType.mono(.footnote))
        }
    }
}
