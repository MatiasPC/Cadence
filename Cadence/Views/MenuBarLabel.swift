import SwiftUI
import DesignSystem

/// The tiny label rendered directly in the system menu bar. Must stay
/// minimal and inherit the menu bar's own foreground styling.
struct MenuBarLabel: View {
    let store: UsageStore

    var body: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: "gauge.with.dots.needle.33percent")
            Text(store.menuBarText)
                .monospacedDigit()
        }
        .font(.system(size: 13, weight: .medium))
    }
}
