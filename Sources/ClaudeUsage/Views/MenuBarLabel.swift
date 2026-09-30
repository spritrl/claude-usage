import SwiftUI

struct MenuBarLabel: View {
    @Environment(UsageStore.self) private var store

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: MenuBarIcon.image(for: store.iconState))
            Text(store.menuBarText)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
        }
    }
}
