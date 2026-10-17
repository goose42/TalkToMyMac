import XCTest
@testable import TalkToMyMacCore

final class ParakeetLanguageTests: XCTestCase {

    // No saved choice means "Automatic": no hint, so Parakeet detects the language itself.
    func testNothingSavedMeansAutomatic() {
        XCTAssertNil(ParakeetLanguage(persisted: nil))
    }

    func testUnknownSavedValueMeansAutomatic() {
        XCTAssertNil(ParakeetLanguage(persisted: "xx"))
    }

    func testSavedValueRoundTrips() {
        for language in ParakeetLanguage.allCases {
            XCTAssertEqual(ParakeetLanguage(persisted: language.rawValue), language)
        }
    }

    // Raw values are persisted in UserDefaults and matched against FluidAudio's `Language`
    // codes, so they must be the ISO 639-1 codes and never change.
    func testRawValuesAreISOCodes() {
        XCTAssertEqual(ParakeetLanguage.english.rawValue, "en")
        XCTAssertEqual(ParakeetLanguage.german.rawValue, "de")
        XCTAssertEqual(ParakeetLanguage.russian.rawValue, "ru")
        XCTAssertEqual(ParakeetLanguage.greek.rawValue, "el")
    }

    // Parakeet TDT 0.6B v3 supports exactly these 25 European languages.
    func testCoversTheModelsLanguages() {
        let codes = Set(ParakeetLanguage.allCases.map(\.rawValue))
        XCTAssertEqual(codes, ["bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de", "el", "hu", "it",
                               "lv", "lt", "mt", "pl", "pt", "ro", "sk", "sl", "es", "sv", "ru", "uk"])
    }

    func testDisplayNameIsLocalized() {
        let english = Locale(identifier: "en_US")
        XCTAssertEqual(ParakeetLanguage.german.displayName(in: english), "German")
        XCTAssertEqual(ParakeetLanguage.greek.displayName(in: english), "Greek")
        XCTAssertEqual(ParakeetLanguage.german.displayName(in: Locale(identifier: "de_DE")), "Deutsch")
    }

    func testSortedByDisplayName() {
        let names = ParakeetLanguage.sortedByName(in: Locale(identifier: "en_US")).map { $0.displayName(in: Locale(identifier: "en_US")) }
        XCTAssertEqual(names, names.sorted())
        XCTAssertEqual(names.count, ParakeetLanguage.allCases.count)
    }
}
