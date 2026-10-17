import XCTest
@testable import TalkToMyMacCore

final class SettingsPaneTests: XCTestCase {

    func testSidebarOrder() {
        XCTAssertEqual(SettingsPane.allCases, [
            .general, .dictionary, .formatting, .models, .transcriptions, .instrumentation, .storage,
        ])
    }

    func testTitles() {
        XCTAssertEqual(SettingsPane.allCases.map(\.title), [
            "General", "Dictionary", "Formatting", "Models", "Transcriptions", "Instrumentation", "Storage",
        ])
    }

    func testTitlesAndSymbolsAreUnique() {
        XCTAssertEqual(Set(SettingsPane.allCases.map(\.title)).count, SettingsPane.allCases.count)
        XCTAssertEqual(Set(SettingsPane.allCases.map(\.symbol)).count, SettingsPane.allCases.count)
    }

    func testIdentifiedByRawValue() {
        XCTAssertEqual(SettingsPane.dictionary.id, "dictionary")
    }
}
