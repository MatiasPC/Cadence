import SwiftUI
import DesignSystem

/// Adaptive colors for the glass panel.
///
/// Velvet UI's static `DSColors` accessors are locked to the *light* palette, so
/// their text tokens (e.g. `textPrimary` = near-black) are invisible on the dark,
/// translucent menu-bar popover. For text sitting on Liquid Glass we use
/// SwiftUI's semantic label colors, which adapt to the glass's effective
/// appearance in both light and dark mode — Apple's guidance for glass surfaces.
/// The accent stays the DS brand color, which is legible in either mode.
enum PanelColor {
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color.secondary.opacity(0.6)
    /// Unfilled progress-bar track.
    static let track = Color.secondary.opacity(0.22)
    /// Filled progress / brand accent — a smooth violet.
    static let accent = Color(hex: "8B5CF6")
    /// Gradient fill for the main session/week progress bars.
    static let accentGradient = LinearGradient(
        colors: [Color(hex: "A78BFA"), Color(hex: "7C3AED")],
        startPoint: .leading,
        endPoint: .trailing
    )
}
