import Foundation

/// A language the user can tell Parakeet TDT 0.6B v3 to expect — the 25 European languages
/// the model supports. Choosing none ("Automatic") lets the model detect the language itself.
///
/// The hint only steers the decoder towards tokens in the language's script (Latin, Cyrillic
/// or Greek), so it fixes mixed-script output, not confusion between languages that share one.
public enum ParakeetLanguage: String, CaseIterable, Hashable, Sendable {
    case bulgarian = "bg"
    case croatian = "hr"
    case czech = "cs"
    case danish = "da"
    case dutch = "nl"
    case english = "en"
    case estonian = "et"
    case finnish = "fi"
    case french = "fr"
    case german = "de"
    case greek = "el"
    case hungarian = "hu"
    case italian = "it"
    case latvian = "lv"
    case lithuanian = "lt"
    case maltese = "mt"
    case polish = "pl"
    case portuguese = "pt"
    case romanian = "ro"
    case slovak = "sk"
    case slovenian = "sl"
    case spanish = "es"
    case swedish = "sv"
    case russian = "ru"
    case ukrainian = "uk"

    /// Reads a saved choice; nothing saved, or a value this version doesn't know, means Automatic.
    public init?(persisted rawValue: String?) {
        guard let rawValue, let language = Self(rawValue: rawValue) else { return nil }
        self = language
    }

    /// The language's name in `locale`, e.g. "German" in English or "Deutsch" in German.
    public func displayName(in locale: Locale = .current) -> String {
        locale.localizedString(forLanguageCode: rawValue) ?? rawValue
    }

    /// Every language, alphabetical by its name in `locale`, for pickers.
    public static func sortedByName(in locale: Locale = .current) -> [ParakeetLanguage] {
        allCases.sorted { $0.displayName(in: locale).localizedStandardCompare($1.displayName(in: locale)) == .orderedAscending }
    }
}
