import SwiftUI

struct PopoverView: View {
    @Environment(UsageStore.self) private var store

    var body: some View {
        Group {
            if store.isLinked {
                UsageView()
            } else {
                LinkAccountView()
            }
        }
        .frame(width: 300)
        .onAppear {
            store.refreshLaunchAtLoginStatus()
            Task { await store.refresh(force: false) }
        }
    }
}
