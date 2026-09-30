import Foundation

/// Raccourci de localisation : les clés sont les textes anglais, les traductions vivent dans
/// `Localization/Localizable.xcstrings` (chargé depuis `Bundle.module`, pas `Bundle.main`).
@inline(__always)
func tr(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}
