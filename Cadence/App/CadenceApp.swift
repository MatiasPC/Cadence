import SwiftUI

@main
struct CadenceApp: App {
    @State private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            UsagePanelView()
                .environment(store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
