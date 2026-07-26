import SwiftUI
import DesignSystem

/// A single stacked proportion bar showing today's spend split by model
/// family, with a compact color-coded legend underneath.
struct ModelSplitBar: View {
    let shares: [ModelShare]

    private var totalCost: Double {
        shares.reduce(0) { $0 + $1.cost }
    }

    var body: some View {
        if shares.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                GeometryReader { geometry in
                    HStack(spacing: 2) {
                        ForEach(shares) { share in
                            color(for: share.family)
                                .frame(width: segmentWidth(for: share, totalWidth: geometry.size.width))
                        }
                    }
                }
                .frame(height: 10)
                .clipShape(Capsule())

                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    ForEach(shares) { share in
                        HStack(spacing: DSSpacing.xxs) {
                            Circle()
                                .fill(color(for: share.family))
                                .frame(width: 6, height: 6)
                            Text(share.family.rawValue)
                                .dsTextStyle(.caption2, color: PanelColor.textSecondary)
                            Spacer()
                            Text(Format.money(share.cost))
                                .dsTextStyle(.caption2, color: PanelColor.textPrimary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    private func segmentWidth(for share: ModelShare, totalWidth: CGFloat) -> CGFloat {
        guard totalCost > 0 else { return 0 }
        return totalWidth * CGFloat(share.cost / totalCost)
    }

    /// Per-model colors — kept distinct from the violet session/week bars.
    private func color(for family: ModelFamily) -> Color {
        switch family {
        case .opus:   return Color(hex: "F59E0B")   // amber
        case .sonnet: return Color(hex: "38BDF8")   // sky blue
        case .haiku:  return Color(hex: "34D399")   // emerald
        case .other:  return PanelColor.textTertiary
        }
    }
}
