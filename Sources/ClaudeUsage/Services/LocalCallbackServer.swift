import Foundation
import Network

/// Mini serveur HTTP sur 127.0.0.1 (port aléatoire) qui attend la redirection OAuth
/// `GET /callback?code=…&state=…`, répond une page « vous pouvez fermer cet onglet » et s'arrête.
final class LocalCallbackServer: @unchecked Sendable {
    enum ServerError: LocalizedError {
        case startFailed(String)
        case timeout
        case stateMismatch
        case denied(String)

        var errorDescription: String? {
            switch self {
            case .startFailed(let m): return tr("Could not start the local server: \(m)")
            case .timeout: return tr("Timed out: no response from the browser.")
            case .stateMismatch: return tr("Invalid OAuth response (unexpected state).")
            case .denied(let m): return tr("Sign-in refused: \(m)")
            }
        }
    }

    private let queue = DispatchQueue(label: "com.chris.claude-usage.callback")
    private var listener: NWListener?
    private var codeContinuation: CheckedContinuation<String, Error>?
    private var expectedState = ""
    private var cancelled = false

    /// Démarre l'écoute et renvoie le port attribué.
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            queue.async {
                do {
                    let params = NWParameters.tcp
                    params.requiredInterfaceType = .loopback
                    let listener = try NWListener(using: params)
                    var resumed = false
                    listener.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            guard !resumed, let port = listener.port?.rawValue else { return }
                            resumed = true
                            continuation.resume(returning: port)
                        case .failed(let error):
                            if !resumed {
                                resumed = true
                                continuation.resume(throwing: ServerError.startFailed(error.localizedDescription))
                            }
                        default:
                            break
                        }
                    }
                    listener.newConnectionHandler = { [weak self] connection in
                        self?.handle(connection)
                    }
                    self.listener = listener
                    listener.start(queue: self.queue)
                } catch {
                    continuation.resume(throwing: ServerError.startFailed(error.localizedDescription))
                }
            }
        }
    }

    /// Attend le code d'autorisation correspondant au `state` attendu.
    /// Résolu par le callback HTTP, par le délai, ou par l'annulation de la tâche appelante.
    func waitForCode(expectedState: String, timeout: TimeInterval) async throws -> String {
        let timeoutWork = DispatchWorkItem { [weak self] in
            self?.finish(.failure(ServerError.timeout))
        }
        queue.asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
        defer { timeoutWork.cancel() }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                self.queue.async {
                    if self.cancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    self.expectedState = expectedState
                    self.codeContinuation = continuation
                }
            }
        } onCancel: {
            queue.async {
                self.cancelled = true
                self.finish(.failure(CancellationError()))
            }
        }
    }

    func stop() {
        queue.async {
            self.listener?.cancel()
            self.listener = nil
            self.finish(.failure(CancellationError()))
        }
    }

    // MARK: - HTTP

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else { return }
            let request = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            let (status, body) = self.process(request)
            let response = """
            HTTP/1.1 \(status)\r
            Content-Type: text/html; charset=utf-8\r
            Content-Length: \(body.utf8.count)\r
            Connection: close\r
            \r
            \(body)
            """
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    /// Analyse la ligne de requête et résout la continuation si le callback est valide.
    private func process(_ request: String) -> (String, String) {
        guard let firstLine = request.split(separator: "\r\n", maxSplits: 1).first,
              let target = firstLine.split(separator: " ").dropFirst().first,
              let url = URLComponents(string: "http://localhost\(target)"),
              url.path == "/callback" else {
            return ("404 Not Found", Self.page(title: tr("Not found"), message: tr("This address is not in use.")))
        }
        let items = url.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if let error = value("error") {
            let description = value("error_description") ?? error
            finish(.failure(ServerError.denied(description)))
            return ("200 OK", Self.page(title: tr("Sign-in refused"), message: description))
        }
        guard let code = value("code"), !code.isEmpty else {
            return ("400 Bad Request", Self.page(title: tr("Missing code"), message: tr("No authorization code received.")))
        }
        guard value("state") == expectedState else {
            finish(.failure(ServerError.stateMismatch))
            return ("400 Bad Request", Self.page(title: tr("Invalid response"), message: tr("The state parameter does not match.")))
        }
        finish(.success(code))
        return ("200 OK", Self.page(title: tr("Account linked ✓"), message: tr("You can close this tab and go back to Claude Usage.")))
    }

    private func finish(_ result: Result<String, Error>) {
        guard let continuation = codeContinuation else { return }
        codeContinuation = nil
        continuation.resume(with: result)
    }

    private static func page(title: String, message: String) -> String {
        """
        <!doctype html><html lang="\(Locale.current.language.languageCode?.identifier ?? "en")"><head><meta charset="utf-8"><title>\(title)</title>
        <style>body{font-family:-apple-system,system-ui,sans-serif;background:#f5f4f0;color:#1d1d1f;display:flex;align-items:center;justify-content:center;height:100vh;margin:0}
        main{text-align:center;max-width:26rem;padding:2rem}h1{font-size:1.5rem;margin:0 0 .5rem}p{color:#555;margin:0}</style></head>
        <body><main><h1>\(title)</h1><p>\(message)</p></main></body></html>
        """
    }
}
