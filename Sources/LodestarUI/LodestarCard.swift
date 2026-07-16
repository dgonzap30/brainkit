import SwiftUI

/// Standard card: surface fill, card radius, standard inset.
public struct LodestarCard<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(LodestarMetrics.cardInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LodestarColor.surface, in: .rect(cornerRadius: LodestarMetrics.radiusCard))
    }
}
