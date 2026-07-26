import SwiftUI
import AppKit
import DesignSystem

/// The panel's bottom bar: a More/Less toggle for the extended view, a
/// last-updated stamp, and refresh/quit glass buttons. The "menu bar shows"
/// picker only appears in the extended view to keep the compact menu minimal.
struct PanelFooter: View {
    @Bindable var store: UsageStore
    @Binding var expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            if expanded {
                HStack {
                    Text("Menu bar shows")
                        .dsTextStyle(.caption1, color: PanelColor.textSecondary)

                    Spacer()

                    Picker("Menu bar shows", selection: $store.menuBarMetric) {
                        ForEach(MenuBarMetric.allCases) { metric in
                            Text(metric.title).tag(metric)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }

            HStack(spacing: DSSpacing.xs) {
                Button {
                    withAnimation(.snappy(duration: 0.28)) { expanded.toggle() }
                } label: {
                    Label(
                        expanded ? "Less" : "More",
                        systemImage: expanded ? "chevron.up" : "chevron.down"
                    )
                    .dsTextStyle(.caption1, color: PanelColor.textSecondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(Format.updatedAt(store.lastUpdated))
                    .dsTextStyle(.caption2, color: PanelColor.textTertiary)

                Button {
                    Task { await store.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
            }
        }
    }
}
