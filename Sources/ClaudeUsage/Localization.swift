import Foundation

/// Raccourci de localisation : les clés sont les textes anglais, les traductions vivent dans
/// `Localization/<lang>.lproj/Localizable.strings` (chargées depuis `Bundle.module`, pas `Bundle.main`).
@inline(__always)
func tr(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: Localization.bundle)
}

enum Localization {
    /// Langue forcée pour ce processus (captures d'écran). `nil` = langue de l'utilisateur.
    static var forcedLanguage: String? {
        didSet { bundle = resolveBundle() }
    }

    private(set) static var bundle: Bundle = resolveBundle()

    /// Locale à utiliser pour les formateurs Foundation (durées), cohérente avec la langue forcée.
    static var locale: Locale {
        forcedLanguage.map { Locale(identifier: $0) } ?? .current
    }

    private static func resolveBundle() -> Bundle {
        guard let language = forcedLanguage,
              let path = Bundle.module.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .module
        }
        return bundle
    }
}
