#if canImport(SwiftUI)
import SwiftUI
import BrainKit

/// Drop-in settings card any limb embeds to point itself at the Lodestar brain: host + front-door
/// token + ingest token, a one-tap connection probe with a status dot, and Save. A thin shell over
/// `BrainSettingsModel` — all behaviour (load, normalize, persist, probe) lives there and is tested.
///
/// ```swift
/// BrainSettingsCard(config: PluginConfig(keychain: SystemKeychain()))
/// ```
public struct BrainSettingsCard: View {
    @State private var model: BrainSettingsModel
    private let title: String

    public init(config: PluginConfig, title: String = "Lodestar Brain") {
        _model = State(initialValue: BrainSettingsModel(config: config))
        self.title = title
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                statusBadge
            }
            labeledField("Host", text: $model.host, secure: false)
            labeledField("Front-door token", text: $model.token, secure: true)
            labeledField("Ingest token", text: $model.ingestToken, secure: true)
            HStack {
                Button("Test") { Task { await model.testConnection() } }
                    .disabled(model.status == .checking)
                Spacer()
                Button("Save") { model.save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(statusLabel).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        switch model.status {
        case .unknown: .gray
        case .unconfigured: .orange
        case .checking: .blue
        case .ok: .green
        case .unreachable: .red
        }
    }

    private var statusLabel: String {
        switch model.status {
        case .unknown: "Not tested"
        case .unconfigured: "Incomplete"
        case .checking: "Checking…"
        case .ok: "Connected"
        case .unreachable: "Unreachable"
        }
    }

    private func labeledField(_ label: String, text: Binding<String>, secure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Group {
                if secure { SecureField(label, text: text) } else { TextField(label, text: text) }
            }
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled(true)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
        }
    }
}
#endif
