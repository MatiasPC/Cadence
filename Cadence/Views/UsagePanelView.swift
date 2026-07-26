import SwiftUI
import DesignSystem

/// The dropdown panel shown when the menu-bar item is opened.
///
/// Compact by default: the current session (neutral/gray) and the week, each as
/// a single colored progress bar. The More toggle expands to reveal burn rate,
/// projected cost, all-time spend, and the model split.
struct UsagePanelView: View {
    @Environment(UsageStore.self) private var store
    @State private var expanded = false

    var body: some View {
        GlassEffectContainer(spacing: DSSpacing.sm) {
            VStack(spacing: DSSpacing.sm) {
                header
                content
                PanelFooter(store: store, expanded: $expanded)
            }
            .padding(DSSpacing.md)
        }
        .frame(width: 300)
        .task {
            await store.refresh()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Claude usage").ds(.caption1, color: PanelColor.textSecondary)

            Spacer()

            if store.status == .loading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Body state

    @ViewBuilder
    private var content: some View {
        if store.status == .failed && store.snapshot.block == nil && store.snapshot.todayCost == 0 {
            errorState
        } else if store.snapshot.block == nil && store.snapshot.todayCost == 0 && store.status != .loaded {
            loadingState
        } else {
            fullContent
        }
    }

    private var errorState: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(PanelColor.textSecondary)
                    Text(store.errorMessage ?? "No usage data")
                        .dsTextStyle(.callout, color: PanelColor.textPrimary)
                }

                Text("Install with: npm install -g ccusage")
                    .dsTextStyle(.caption2, color: PanelColor.textTertiary)

                Button("Retry") {
                    Task { await store.refresh() }
                }
                .buttonStyle(.glassProminent)
            }
        }
    }

    private var loadingState: some View {
        GlassCard {
            HStack(spacing: DSSpacing.sm) {
                ProgressView()
                Text("Reading usage…")
                    .dsTextStyle(.callout, color: PanelColor.textSecondary)
            }
        }
    }

    private var fullContent: some View {
        VStack(spacing: DSSpacing.sm) {
            sessionCard
            weekCard
        }
    }

    // MARK: - Session

    private var sessionCard: some View {
        GlassCard {
            let block = store.snapshot.block
            if block != nil || store.hasRealLimits {
                UsageMeter(
                    title: "CURRENT SESSION",
                    progress: store.sessionProgress,
                    secondary: block.map { "\(Format.money($0.cost)) · \(Format.tokens($0.tokens)) tokens" },
                    resetsAt: store.sessionResetsAt
                )
                if expanded, let block {
                    BurnRateRow(costPerHour: block.costPerHour, projectedCost: block.projectedCost)
                }
            } else {
                StatBlock(
                    title: "CURRENT SESSION",
                    value: "Idle",
                    subtitle: "No active 5-hour block"
                )
            }
        }
    }

    // MARK: - Week

    private var weekCard: some View {
        GlassCard {
            UsageMeter(
                title: "THIS WEEK",
                progress: store.weekLimitProgress,
                secondary: Format.money(store.snapshot.weekCost),
                resetsAt: store.weekResetsAt
            )

            if expanded {
                Divider().overlay(PanelColor.track)

                if let opus = store.opusWeekProgress {
                    miniRow("OPUS · THIS WEEK", "\(Int((opus * 100).rounded()))%")
                }
                miniRow("ALL TIME", Format.money(store.snapshot.allTimeCost, compact: true))

                if !store.snapshot.modelShares.isEmpty {
                    Text("TODAY BY MODEL")
                        .dsTextStyle(.caption1, color: PanelColor.textSecondary)
                    ModelSplitBar(shares: store.snapshot.modelShares)
                }
            }
        }
    }

    /// A compact label + value row for secondary details in the expanded view.
    private func miniRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .dsTextStyle(.caption1, color: PanelColor.textSecondary)
            Spacer()
            Text(value)
                .dsTextStyle(.caption1, color: PanelColor.textSecondary)
                .monospacedDigit()
        }
    }
}
