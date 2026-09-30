import AppKit
import SwiftUI

@main
struct ClaudeUsageApp: App {
    @State private var store: UsageStore

    init() {
        // Pas d'icône dans le Dock, même lancé hors bundle (`swift run`).
        NSApplication.shared.setActivationPolicy(.accessory)
        let store = UsageStore()
        store.start()
        _store = State(initialValue: store)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(store)
        } label: {
            MenuBarLabel()
                .environment(store)
        }
        .menuBarExtraStyle(.window)
    }
}
