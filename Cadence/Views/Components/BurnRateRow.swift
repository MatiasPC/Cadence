import SwiftUI
import DesignSystem

/// Two mini stats side by side — burn rate and projected total — separated
/// by a spacer and a thin divider rule.
struct BurnRateRow: View {
    let costPerHour: Double
    let projectedCost: Double

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            miniStat(title: "BURN RATE", value: "\(Format.money(costPerHour))/hr")

            Spacer()

            Rectangle()
                .fill(PanelColor.track)
                .frame(width: 1, height: 24)

            Spacer()

            miniStat(title: "PROJECTED", value: Format.money(projectedCost))
        }
    }

    private func miniStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            Text(title)
                .dsTextStyle(.caption1, color: PanelColor.textSecondary)
            Text(value)
                .dsTextStyle(.callout, color: PanelColor.textPrimary)
                .monospacedDigit()
        }
    }
}
