import SwiftUI

/// Inset-grouped settings section on the OLED surface ramp. Use inside a
/// `List(.insetGrouped)` on iOS; renders as a plain `Section` with our row
/// background so all apps' settings sections look identical.
public struct SettingsSection<Content: View>: View {
    let title: String?
    let footer: String?
    let content: Content

    public init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    public var body: some View {
        Section {
            content
                .listRowBackground(LodestarColor.surface)
        } header: {
            if let title { Text(title) }
        } footer: {
            if let footer { Text(footer).font(.footnote) }
        }
    }
}
