import SwiftUI
import DesignSystem

/// A reusable Liquid Glass panel surface. Pads and left-aligns its content,
/// then applies a regular (optionally tinted) glass material with a large
/// rounded rect shape — the standard card look used across the usage panel.
struct GlassCard<Content: View>: View {
    var tint: Color? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.md)
        .glassEffect(glass, in: .rect(cornerRadius: DSRadius.lg))
    }

    private var glass: Glass {
        if let tint {
            return .regular.tint(tint)
        }
        return .regular
    }
}
