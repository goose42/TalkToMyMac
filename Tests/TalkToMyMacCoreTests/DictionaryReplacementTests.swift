import XCTest
@testable import TalkToMyMacCore

final class DictionaryReplacementTests: XCTestCase {
    private func entry(_ written: String, _ soundsLike: [String], type: DictionaryEntry.EntryType = .properNoun) -> DictionaryEntry {
        DictionaryEntry(written: written, type: type, soundsLike: soundsLike)
    }

    func testReplacesSoundsLikeWithWrittenForm() {
        let entries = [entry("OTel", ["hotel", "oh tell"])]
        XCTAssertEqual(DictionaryReplacement.apply(entries, to: "Add Hotel tracing with oh tell"), "Add OTel tracing with OTel")
    }

    func testUsesWholeWordsAndNeverCascades() {
        let entries = [entry("BetterWispr", ["better whisper"]),
                       entry("wrong", ["BetterWispr"]),
                       entry("Café", ["café"]),
                       entry("$1\\dog", ["cat"])]
        XCTAssertEqual(DictionaryReplacement.apply(entries, to: "better whisper at café, not cafés. cat scatter"),
                       "BetterWispr at Café, not cafés. $1\\dog scatter")
        XCTAssertEqual(DictionaryReplacement.apply([entry("wrong", ["ह"])], to: "हिंदी"), "हिंदी")
    }

    func testPrefersLongestPhrase() {
        let entries = [entry("Kube", ["cube"]), entry("Kubernetes", ["cube a net ease", "cube"])]
        XCTAssertEqual(DictionaryReplacement.apply(entries, to: "deploy to cube a net ease"), "deploy to Kubernetes")
    }

    func testIgnoresEmptySoundsLike() {
        XCTAssertEqual(DictionaryReplacement.apply([entry("Groq", ["", "  "])], to: "use groq here"), "use groq here")
    }

    func testCaseOnlySoundsLikeFixesCasing() {
        XCTAssertEqual(DictionaryReplacement.apply([entry("Groq", ["groq"])], to: "use GROQ here"), "use Groq here")
    }

    func testWithoutEntriesLeavesTextUnchanged() {
        XCTAssertEqual(DictionaryReplacement.apply([], to: "hello world"), "hello world")
    }

    func testCommandEntriesAreSeparatedFromTerms() {
        let entries = [entry("question mark", ["Kocia Mark"], type: .noun),
                       entry("hyphen", ["Hai fun"], type: .noun),
                       entry("comma", ["Coma"], type: .noun),
                       entry("at the rate", ["at the Red"], type: .noun),
                       entry("Jurassic Period", ["jurassic pyramid"])]
        let dictated = [
            "Kocia Mark.": "?",
            "Hai fun.": "-",
            "Hi, Coma, how are you doing?": "Hi, how are you doing?",
            "Hey, at the Red Harsh Gupta.": "Hey, @Harsh Gupta.",
            "I love the jurassic pyramid": "I love the jurassic pyramid",
        ]
        for (heard, written) in dictated {
            XCTAssertEqual(VoiceCommands.apply(DictionaryReplacement.commands(entries, in: heard)), written)
        }
        XCTAssertEqual(DictionaryReplacement.apply(entries, to: "the jurassic pyramid, Coma"), "the Jurassic Period, Coma")
    }

    func testRecognisesSpokenCommands() {
        XCTAssertFalse(VoiceCommands.isSpokenCommand(""))
        XCTAssertFalse(VoiceCommands.isSpokenCommand("42"))
        XCTAssertFalse(VoiceCommands.isSpokenCommand("BetterWispr"))
        XCTAssertTrue(VoiceCommands.isSpokenCommand("new line"))
        XCTAssertTrue(VoiceCommands.isSpokenCommand("hash forty two"))
    }
}
