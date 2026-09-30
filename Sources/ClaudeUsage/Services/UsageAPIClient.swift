import Foundation

/// Client pour `GET https://api.anthropic.com/api/oauth/usage` (endpoint non officiel,
/// le même que la commande `/usage` de Claude Code).
struct UsageAPIClient {
    enum APIError: LocalizedError {
        case unauthorized
        case rateLimited(retryAfter: TimeInterval?)
        case http(Int, String)
        case decoding(Error)
        case network(Error)

        var errorDescription: String? {
            switch self {
            case .unauthorized:
                return "Session Claude expirée ou invalide."
            case .rateLimited:
                return "Trop de requêtes vers l'API, nouvel essai plus tard."
            case .http(let code, let body):
                return "Erreur API (\(code))\(body.isEmpty ? "" : " : \(body)")"
            case .decoding:
                return "Réponse API inattendue."
            case .network(let error):
                return "Réseau indisponible : \(error.localizedDescription)"
            }
        }
    }

    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    func fetchUsage(accessToken: String) async throws -> UsageSnapshot {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ClaudeUsage/1.0 (macOS menu bar)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(0, "réponse non HTTP")
        }

        switch http.statusCode {
        case 200..<300:
            break
        case 401, 403:
            throw APIError.unauthorized
        case 429:
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw APIError.rateLimited(retryAfter: retry)
        default:
            let body = String(decoding: data.prefix(200), as: UTF8.self)
            throw APIError.http(http.statusCode, body)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(UsageResponse.self, from: data).snapshot()
        } catch {
            throw APIError.decoding(error)
        }
    }
}
