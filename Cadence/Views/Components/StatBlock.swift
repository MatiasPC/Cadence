import SwiftUI
import DesignSystem

/// A labeled numeric readout: small title, large value, optional subtitle.
/// The basic building block for every stat shown in the panel.
struct StatBlock: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    var accent: Color = PanelColor.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            Text(title)
                .dsTextStyle(.caption1, color: PanelColor.textSecondary)

            Text(value)
                .dsTextStyle(.title3, color: accent)
                .monospacedDigit()

            if let subtitle {
                Text(subtitle)
                    .dsTextStyle(.caption2, color: PanelColor.textTertiary)
            }
        }
    }
}
