import Foundation
import Security

/// Lit le jeton OAuth que Claude Code stocke dans le Trousseau macOS
/// (item « generic password », service `Claude Code-credentials`).
/// L'app ne modifie jamais cet item.
enum ClaudeCodeKeychainReader {
    static let service = "Claude Code-credentials"

    enum ReaderError: LocalizedError {
        case notFound
        case accessDenied
        case notLoggedIn
        case malformed
        case tool(String)

        var errorDescription: String? {
            switch self {
            case .notFound:
                return "Aucun identifiant Claude Code trouvé dans le Trousseau. Lance `claude` et connecte-toi d'abord."
            case .accessDenied:
                return "Accès au Trousseau refusé. Réessaie et choisis « Toujours autoriser »."
            case .notLoggedIn:
                return "Claude Code n'est pas connecté à un compte Claude (pas de jeton OAuth)."
            case .malformed:
                return "L'entrée Trousseau de Claude Code est illisible."
            case .tool(let message):
                return "Lecture du Trousseau impossible : \(message)"
            }
        }
    }

    /// Lecture bloquante : à appeler hors du thread principal.
    static func read() throws -> OAuthCredentials {
        let data: Data
        do {
            data = try readViaSecurityTool()
        } catch ReaderError.notFound {
            throw ReaderError.notFound
        } catch {
            // Repli sur l'API Security si l'outil `security` échoue.
            data = try readViaSecItem()
        }
        return try parse(data)
    }

    // MARK: - Outil `security`

    private static func readViaSecurityTool() throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if message.contains("could not be found") { throw ReaderError.notFound }
            if message.contains("User interaction is not allowed") || message.contains("canceled") {
                throw ReaderError.accessDenied
            }
            throw ReaderError.tool(message.isEmpty ? "code \(process.terminationStatus)" : message)
        }

        var text = String(decoding: stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        // `security -w` renvoie de l'hexadécimal si la valeur n'est pas du texte simple.
        if !text.hasPrefix("{"), let decoded = Data(hexString: text) {
            text = String(decoding: decoded, as: UTF8.self)
        }
        return Data(text.utf8)
    }

    // MARK: - API Security

    private static func readViaSecItem() throws -> Data {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw ReaderError.malformed }
            return data
        case errSecItemNotFound:
            throw ReaderError.notFound
        case errSecAuthFailed, errSecUserCanceled, errSecInteractionNotAllowed:
            throw ReaderError.accessDenied
        default:
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            throw ReaderError.tool(message)
        }
    }

    // MARK: - Parsing

    private struct Blob: Decodable {
        struct OAuth: Decodable {
            let accessToken: String
            let refreshToken: String?
            let expiresAt: Double?
            let scopes: [String]?
            let subscriptionType: String?
        }
        let claudeAiOauth: OAuth?
    }

    private static func parse(_ data: Data) throws -> OAuthCredentials {
        let blob: Blob
        do {
            blob = try JSONDecoder().decode(Blob.self, from: data)
        } catch {
            throw ReaderError.malformed
        }
        guard let oauth = blob.claudeAiOauth, !oauth.accessToken.isEmpty else {
            throw ReaderError.notLoggedIn
        }
        return OAuthCredentials(
            accessToken: oauth.accessToken,
            refreshToken: oauth.refreshToken,
            expiresAt: oauth.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) },
            scopes: oauth.scopes ?? [],
            subscriptionType: oauth.subscriptionType,
            email: nil,
            source: .claudeCode
        )
    }
}

extension Data {
    init?(hexString: String) {
        let chars = Array(hexString.utf8)
        guard chars.count % 2 == 0, !chars.isEmpty else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(chars.count / 2)
        var index = 0
        while index < chars.count {
            guard let byte = UInt8(String(decoding: chars[index..<index + 2], as: UTF8.self), radix: 16) else { return nil }
            bytes.append(byte)
            index += 2
        }
        self.init(bytes)
    }
}
