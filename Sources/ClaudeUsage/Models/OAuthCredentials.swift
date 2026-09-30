import Foundation

/// D'où vient le jeton : lu dans le Trousseau de Claude Code, ou obtenu par l'app elle-même.
enum CredentialSource: String, Codable {
    case claudeCode
    case app

    var label: String {
        switch self {
        case .claudeCode: return tr("Claude Code")
        case .app: return tr("Claude sign-in")
        }
    }
}

struct OAuthCredentials: Codable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    var scopes: [String]
    var subscriptionType: String?
    var email: String?
    var source: CredentialSource

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }

    /// Vrai si le jeton expire dans moins de 5 minutes.
    var needsRefreshSoon: Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSinceNow < 300
    }

    var subscriptionLabel: String? {
        guard let subscriptionType, !subscriptionType.isEmpty else { return nil }
        return subscriptionType.prefix(1).uppercased() + subscriptionType.dropFirst()
    }
}
