import SwiftUI

/// Case « Lancer à l'ouverture de session », partagée par les deux écrans du popup.
/// Masquée quand l'app ne tourne pas depuis un bundle `.app`.
struct LaunchAtLoginToggle: View {
    @Environment(UsageStore.self) private var store

    var body: some View {
        if store.launchAtLogin != .unavailable {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: Binding(
                    get: { store.launchAtLogin == .enabled || store.launchAtLogin == .requiresApproval },
                    set: { store.setLaunchAtLogin($0) }
                )) {
                    Text(tr("Launch at login")).font(.caption)
                }
                .toggleStyle(.checkbox)

                if store.launchAtLogin == .requiresApproval {
                    Button(tr("Waiting for your approval in System Settings › Login Items")) {
                        LaunchAtLogin.openSystemSettings()
                    }
                    .buttonStyle(.link)
                    .font(.caption2)
                }
                if let error = store.launchAtLoginError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
