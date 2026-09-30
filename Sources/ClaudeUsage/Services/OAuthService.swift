import CryptoKit
import Foundation

/// Flux OAuth 2.0 + PKCE de Claude (le même que celui utilisé par Claude Code).
struct OAuthService {
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let authorizeEndpoint = URL(string: "https://claude.ai/oauth/authorize")!
    static let tokenEndpoint = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    static let manualRedirectURI = "https://console.anthropic.com/oauth/code/callback"
    static let scopes = "org:create_api_key user:profile user:inference"

    enum OAuthError: LocalizedError {
        case invalidCode
        case stateMismatch
        case tokenExchange(Int, String)
        case network(Error)
        case noRefreshToken

        var errorDescription: String? {
            switch self {
            case .invalidCode: return tr("The pasted code is empty or malformed.")
            case .stateMismatch: return tr("The code does not match this sign-in attempt. Start the sign-in again.")
            case .tokenExchange(let status, let body):
                return tr("Code exchange failed (\(status))\(body.isEmpty ? "" : ": \(body)")")
            case .network(let error): return tr("Network unavailable: \(error.localizedDescription)")
            case .noRefreshToken: return tr("No refresh token available, please sign in again.")
            }
        }
    }

    /// Une tentative de connexion en cours : verifier PKCE + state + redirect_uri.
    struct Session {
        let verifier: String
        let state: String
        let redirectURI: String
        let authorizeURL: URL
    }

    // MARK: - Sessions

    func makeSession(redirectURI: String) -> Session {
        let verifier = Self.randomURLSafe(bytes: 32)
        let state = Self.randomURLSafe(bytes: 32)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))

        var components = URLComponents(url: Self.authorizeEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        return Session(verifier: verifier, state: state, redirectURI: redirectURI, authorizeURL: components.url!)
    }

    func makeManualSession() -> Session {
        makeSession(redirectURI: Self.manualRedirectURI)
    }

    // MARK: - Connexion via navigateur + callback localhost

    func loginViaBrowser(openURL: @escaping (URL) -> Void, timeout: TimeInterval = 300) async throws -> OAuthCredentials {
        let server = LocalCallbackServer()
        let port = try await server.start()
        defer { server.stop() }

        let session = makeSession(redirectURI: "http://localhost:\(port)/callback")
        openURL(session.authorizeURL)
        let code = try await server.waitForCode(expectedState: session.state, timeout: timeout)
        return try await exchange(code: code, session: session)
    }

    // MARK: - Connexion manuelle (code collé « code#state »)

    func exchangeManualCode(_ raw: String, session: Session) async throws -> OAuthCredentials {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OAuthError.invalidCode }
        let parts = trimmed.split(separator: "#", maxSplits: 1).map(String.init)
        let code = parts[0]
        if parts.count == 2, parts[1] != session.state { throw OAuthError.stateMismatch }
        guard !code.isEmpty else { throw OAuthError.invalidCode }
        return try await exchange(code: code, session: session)
    }

    // MARK: - Échange et rafraîchissement

    func exchange(code: String, session: Session) async throws -> OAuthCredentials {
        let body: [String: Any] = [
            "grant_type": "authorization_code",
            "code": code,
            "state": session.state,
            "client_id": Self.clientID,
            "redirect_uri": session.redirectURI,
            "code_verifier": session.verifier,
        ]
        let token = try await post(body)
        return token.credentials(previous: nil)
    }

    func refresh(_ credentials: OAuthCredentials) async throws -> OAuthCredentials {
        guard let refreshToken = credentials.refreshToken, !refreshToken.isEmpty else {
            throw OAuthError.noRefreshToken
        }
        let body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID,
        ]
        let token = try await post(body)
        return token.credentials(previous: credentials)
    }

    // MARK: - HTTP

    private struct TokenResponse: Decodable {
        struct Account: Decodable {
            let emailAddress: String?
        }
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Double?
        let scope: String?
        let account: Account?

        func credentials(previous: OAuthCredentials?) -> OAuthCredentials {
            OAuthCredentials(
                accessToken: accessToken,
                refreshToken: refreshToken ?? previous?.refreshToken,
                expiresAt: expiresIn.map { Date(timeIntervalSinceNow: $0) },
                scopes: scope?.split(separator: " ").map(String.init) ?? previous?.scopes ?? [],
                subscriptionType: previous?.subscriptionType,
                email: account?.emailAddress ?? previous?.email,
                source: .app
            )
        }
    }

    private func post(_ body: [String: Any]) async throws -> TokenResponse {
        var request = URLRequest(url: Self.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ClaudeUsage/1.0 (macOS menu bar)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw OAuthError.network(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw OAuthError.tokenExchange(status, String(decoding: data.prefix(300), as: UTF8.self))
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(TokenResponse.self, from: data)
    }

    // MARK: - Helpers

    private static func randomURLSafe(bytes count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
