import SwiftUI
import DesignSystem

/// The hero meter for a usage window. The **percentage** and the **gradient
/// progress bar** are the focus; the dollar amount is demoted to a small
/// secondary line beneath, alongside the reset countdown.
struct UsageMeter: View {
    let title: String
    let progress: Double
    /// Small secondary detail, e.g. "$6.92 · 6.4M tokens".
    var secondary: String? = nil
    var resetsAt: Date? = nil

    private var clamped: Double { min(max(progress, 0), 1) }
    private var percent: Int { Int((clamped * 100).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(title)
                .dsTextStyle(.caption1, color: PanelColor.textSecondary)

            Text("\(percent)%")
                .dsTextStyle(.title2, color: PanelColor.textPrimary)
                .monospacedDigit()

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(PanelColor.track)
                    Capsule()
                        .fill(PanelColor.accentGradient)
                        .frame(width: geometry.size.width * clamped)
                }
            }
            .frame(height: 10)

            if secondary != nil || resetsAt != nil {
                HStack {
                    if let secondary {
                        Text(secondary)
                            .dsTextStyle(.caption1, color: PanelColor.textSecondary)
                            .monospacedDigit()
                    }
                    Spacer()
                    if let resetsAt {
                        Text("Resets in \(Format.countdown(to: resetsAt))")
                            .dsTextStyle(.caption1, color: PanelColor.textTertiary)
                    }
                }
            }
        }
    }
}
