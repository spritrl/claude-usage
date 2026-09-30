import AppKit
import SwiftUI

@main
struct ClaudeUsageApp: App {
    @State private var store: UsageStore

    init() {
        // Pas d'icône dans le Dock, même lancé hors bundle (`swift run`).
        NSApplication.shared.setActivationPolicy(.accessory)
        if let index = CommandLine.arguments.firstIndex(of: "--screenshots"),
           CommandLine.arguments.indices.contains(index + 1) {
            let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            do {
                try Screenshots.render(to: directory)
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("screenshots: \(error)\n".utf8))
                exit(1)
            }
        }
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
