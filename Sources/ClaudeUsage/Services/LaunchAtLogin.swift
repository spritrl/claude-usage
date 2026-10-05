import Foundation
import ServiceManagement

/// Ouverture automatique à la connexion via `SMAppService.mainApp` (macOS 13+).
/// Ne fonctionne que depuis un vrai bundle `.app` : sous `swift run` l'enregistrement est impossible
/// et l'option est simplement masquée.
enum LaunchAtLogin {
    enum Status: Equatable {
        case enabled
        case disabled
        /// Enregistré, mais l'utilisateur doit encore l'autoriser dans Réglages Système › Ouverture.
        case requiresApproval
        /// Pas de bundle `.app` (ex. `swift run`) : rien à proposer.
        case unavailable
    }

    static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var status: Status {
        guard isAvailable else { return .unavailable }
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        default: return .disabled
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
