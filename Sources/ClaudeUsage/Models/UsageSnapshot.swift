import Foundation

/// Une fenêtre de quota renvoyée par `GET /api/oauth/usage` (session 5 h, semaine, …).
struct UsageWindow: Equatable {
    /// Pourcentage utilisé, 0…100.
    let utilization: Double
    /// Date de réinitialisation de la fenêtre, si fournie.
    let resetsAt: Date?

    var fraction: Double { min(max(utilization / 100, 0), 1) }
    var percentText: String { "\(Int(utilization.rounded()))%" }
}

/// Photo de l'usage à un instant donné.
struct UsageSnapshot: Equatable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    let sevenDayOpus: UsageWindow?
    let sevenDaySonnet: UsageWindow?
    let fetchedAt: Date

    /// Valeur la plus élevée entre session et semaine, pour teinter l'icône.
    var peakUtilization: Double {
        max(fiveHour?.utilization ?? 0, sevenDay?.utilization ?? 0)
    }
}

// MARK: - Décodage tolérant de la réponse API

struct UsageResponse: Decodable {
    let fiveHour: RawWindow?
    let sevenDay: RawWindow?
    let sevenDayOpus: RawWindow?
    let sevenDaySonnet: RawWindow?

    struct RawWindow: Decodable {
        let utilization: Double?
        let resetsAt: String?
    }

    func snapshot(at date: Date = Date()) -> UsageSnapshot {
        UsageSnapshot(
            fiveHour: fiveHour?.window,
            sevenDay: sevenDay?.window,
            sevenDayOpus: sevenDayOpus?.window,
            sevenDaySonnet: sevenDaySonnet?.window,
            fetchedAt: date
        )
    }
}

private extension UsageResponse.RawWindow {
    var window: UsageWindow? {
        guard let utilization else { return nil }
        return UsageWindow(utilization: utilization, resetsAt: resetsAt.flatMap(ISO8601.parse))
    }
}

enum ISO8601 {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ string: String) -> Date? {
        withFraction.date(from: string) ?? plain.date(from: string)
    }
}
