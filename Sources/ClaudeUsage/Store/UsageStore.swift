import AppKit
import Foundation
import Observation

/// État central de l'app : liaison du compte, polling de l'usage, erreurs.
@MainActor
@Observable
final class UsageStore {
    enum Phase: Equatable {
        case unlinked
        case linking(String)
        case linked
    }

    // MARK: État observable
    private(set) var phase: Phase = .unlinked
    private(set) var credentials: OAuthCredentials?
    private(set) var snapshot: UsageSnapshot?
    private(set) var errorMessage: String?
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?
    /// Vrai quand le champ « coller le code » doit être affiché.
    private(set) var manualLoginPending = false

    // MARK: Dépendances / internes
    private let api = UsageAPIClient()
    private let oauth = OAuthService()
    private var pollTask: Task<Void, Never>?
    private var loginTask: Task<Void, Never>?
    private var manualSession: OAuthService.Session?
    private var backoff: TimeInterval = 0
    private var started = false

    private let pollInterval: TimeInterval = 180
    private let staleAfter: TimeInterval = 15

    private enum Keys {
        static let linkedSource = "linkedSource"
        static let autoLinkDisabled = "claudeCodeAutoLinkDisabled"
    }

    var isLinked: Bool { phase == .linked }

    // MARK: - Cycle de vie

    func start() {
        guard !started else { return }
        started = true
        Task { await bootstrap() }
    }

    private func bootstrap() async {
        let defaults = UserDefaults.standard
        if let saved = AppKeychainStore.load() {
            credentials = saved
            phase = .linked
        } else {
            let remembered = defaults.string(forKey: Keys.linkedSource) == CredentialSource.claudeCode.rawValue
            let firstLaunch = !defaults.bool(forKey: Keys.autoLinkDisabled) && defaults.string(forKey: Keys.linkedSource) == nil
            if remembered || firstLaunch {
                await linkViaClaudeCode(silent: true)
            }
        }
        startPolling()
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh(force: true)
                let wait = self.backoff > 0 ? self.backoff : self.pollInterval
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    // MARK: - Liaison via Claude Code

    func linkViaClaudeCode(silent: Bool = false) async {
        if !silent { phase = .linking(tr("Reading Keychain…")) }
        errorMessage = nil
        do {
            let creds = try await Task.detached(priority: .userInitiated) {
                try ClaudeCodeKeychainReader.read()
            }.value
            finishLink(creds)
        } catch {
            if silent {
                // Ne pas redemander l'accès au Trousseau à chaque lancement : l'utilisateur choisira dans le popup.
                UserDefaults.standard.set(true, forKey: Keys.autoLinkDisabled)
                phase = .unlinked
            } else {
                phase = .unlinked
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Connexion OAuth

    func startBrowserLogin() {
        loginTask?.cancel()
        manualLoginPending = false
        errorMessage = nil
        phase = .linking(tr("Signing in from the browser…"))
        loginTask = Task { [oauth] in
            do {
                let creds = try await oauth.loginViaBrowser { url in
                    NSWorkspace.shared.open(url)
                }
                finishLink(creds)
            } catch is CancellationError {
                if case .linking = phase { phase = .unlinked }
            } catch {
                phase = .unlinked
                errorMessage = error.localizedDescription
            }
        }
    }

    func startManualLogin() {
        loginTask?.cancel()
        errorMessage = nil
        let session = oauth.makeManualSession()
        manualSession = session
        manualLoginPending = true
        phase = .unlinked
        NSWorkspace.shared.open(session.authorizeURL)
    }

    func submitManualCode(_ code: String) async {
        guard let session = manualSession else {
            errorMessage = tr("Start the manual sign-in first.")
            return
        }
        phase = .linking(tr("Exchanging the code…"))
        errorMessage = nil
        do {
            let creds = try await oauth.exchangeManualCode(code, session: session)
            manualLoginPending = false
            manualSession = nil
            finishLink(creds)
        } catch {
            phase = .unlinked
            errorMessage = error.localizedDescription
        }
    }

    func cancelLinking() {
        loginTask?.cancel()
        loginTask = nil
        manualLoginPending = false
        manualSession = nil
        errorMessage = nil
        phase = .unlinked
    }

    private func finishLink(_ creds: OAuthCredentials) {
        credentials = creds
        phase = .linked
        errorMessage = nil
        backoff = 0
        let defaults = UserDefaults.standard
        defaults.set(creds.source.rawValue, forKey: Keys.linkedSource)
        defaults.set(false, forKey: Keys.autoLinkDisabled)
        if creds.source == .app {
            AppKeychainStore.save(creds)
        }
        Task { await refresh(force: true) }
    }

    func unlink() {
        loginTask?.cancel()
        credentials = nil
        snapshot = nil
        lastRefresh = nil
        errorMessage = nil
        manualLoginPending = false
        manualSession = nil
        AppKeychainStore.delete()
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Keys.linkedSource)
        defaults.set(true, forKey: Keys.autoLinkDisabled)
        phase = .unlinked
    }

    // MARK: - Rafraîchissement de l'usage

    /// Rafraîchit si les données datent de plus de `staleAfter` secondes (ou toujours si `force`).
    func refresh(force: Bool) async {
        guard phase == .linked, credentials != nil, !isRefreshing else { return }
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < staleAfter { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            try await ensureFreshCredentials()
            guard let creds = credentials else { return }
            do {
                snapshot = try await api.fetchUsage(accessToken: creds.accessToken)
            } catch UsageAPIClient.APIError.unauthorized {
                // Un seul nouvel essai après récupération d'un jeton valide.
                try await recoverCredentials()
                guard let retried = credentials else { return }
                snapshot = try await api.fetchUsage(accessToken: retried.accessToken)
            }
            lastRefresh = Date()
            errorMessage = nil
            backoff = 0
        } catch UsageAPIClient.APIError.rateLimited(let retryAfter) {
            backoff = retryAfter ?? max(60, min(900, backoff == 0 ? 60 : backoff * 2))
            errorMessage = tr("Rate limit reached, retrying in \(Int(backoff / 60)) min.")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Rafraîchit proactivement un jeton d'app proche de l'expiration, ou relit celui de Claude Code s'il a expiré.
    private func ensureFreshCredentials() async throws {
        guard let creds = credentials else { return }
        switch creds.source {
        case .app where creds.needsRefreshSoon:
            try await recoverCredentials()
        case .claudeCode where creds.isExpired:
            try await recoverCredentials()
        default:
            break
        }
    }

    /// Obtient un jeton valide : refresh_token pour un jeton d'app, relecture du Trousseau pour Claude Code.
    private func recoverCredentials() async throws {
        guard let creds = credentials else { return }
        switch creds.source {
        case .app:
            let refreshed = try await oauth.refresh(creds)
            credentials = refreshed
            AppKeychainStore.save(refreshed)
        case .claudeCode:
            let reread = try await Task.detached(priority: .userInitiated) {
                try ClaudeCodeKeychainReader.read()
            }.value
            guard reread.accessToken != creds.accessToken else {
                throw StoreError.claudeCodeSessionExpired
            }
            credentials = reread
        }
    }

    enum StoreError: LocalizedError {
        case claudeCodeSessionExpired
        var errorDescription: String? {
            tr("Claude Code session expired: run `claude` in a terminal to renew it.")
        }
    }

    // MARK: - Présentation barre de menus

    enum IconState: Equatable {
        case unlinked
        case error
        case usage(Double)
    }

    var iconState: IconState {
        guard isLinked else { return .unlinked }
        if let snapshot { return .usage(snapshot.peakUtilization) }
        return errorMessage == nil ? .usage(0) : .error
    }

    var menuBarText: String {
        guard isLinked else { return "—" }
        guard let snapshot else { return errorMessage == nil ? "…" : "!" }
        let session = snapshot.fiveHour?.percentText ?? "–"
        let weekly = snapshot.sevenDay?.percentText ?? "–"
        return "\(session) · \(weekly)"
    }
}
