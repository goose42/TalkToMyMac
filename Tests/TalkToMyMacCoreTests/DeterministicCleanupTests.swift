import XCTest
@testable import TalkToMyMacCore

final class DeterministicCleanupTests: XCTestCase {
    func testRemovesFillersRepairsAndStutters() {
        XCTAssertEqual(DeterministicCleanup.apply("um I I think we should, you know, meet at three", dictionary: []),
                       "I think we should meet at three")
        XCTAssertEqual(DeterministicCleanup.apply("I want to go to Ahmedabad, sorry, no, to Delhi.", dictionary: []),
                       "I want to go to Delhi.")
    }

    func testAppliesVoiceCommandsAndNumbersAfterCleaning() {
        XCTAssertEqual(DeterministicCleanup.apply("uh we invited two hundred people comma then new line the rest", dictionary: []),
                       "We invited 200 people, then\nThe rest")
    }

    func testLaysOutDictatedEmail() {
        XCTAssertEqual(DeterministicCleanup.apply("um write an email to Sam saying the build is done. Thanks.", dictionary: []),
                       "Hi Sam,\n\nThe build is done.\n\nThanks")
    }

    func testAppliesDictionaryCommandFixesBeforeVoiceCommands() {
        let dictionary = [DictionaryEntry(written: "question mark", type: .noun, soundsLike: ["Kocia Mark"])]
        XCTAssertEqual(DeterministicCleanup.apply("is it done Kocia Mark", dictionary: dictionary), "is it done?")
    }

    func testAppliesDictionaryTermsLast() {
        let dictionary = [DictionaryEntry(written: "OTel", type: .acronym, soundsLike: ["hotel"])]
        XCTAssertEqual(DeterministicCleanup.apply("uh add hotel tracing", dictionary: dictionary), "Add OTel tracing")
    }

    func testOnlyTrimsOtherLanguagesButStillAppliesDictionary() {
        XCTAssertEqual(DeterministicCleanup.apply(" Wir treffen uns um acht Uhr komma danke ", dictionary: []),
                       "Wir treffen uns um acht Uhr komma danke")
        let dictionary = [DictionaryEntry(written: "Kubernetes", type: .properNoun, soundsLike: ["Kuber Netties"])]
        XCTAssertEqual(DeterministicCleanup.apply("Wir deployen das auf Kuber Netties heute Abend", dictionary: dictionary),
                       "Wir deployen das auf Kubernetes heute Abend")
    }

    func testApplyDictionaryOnlySwapsTermsAndLeavesFillers() {
        let dictionary = [
            DictionaryEntry(written: "OTel", type: .acronym, soundsLike: ["hotel"]),
            DictionaryEntry(written: "question mark", type: .noun, soundsLike: ["Kocia Mark"]),
        ]
        XCTAssertEqual(DeterministicCleanup.applyDictionary("um add hotel tracing Kocia Mark", dictionary: dictionary),
                       "um add OTel tracing question mark")
    }

    func testApplyDictionaryWithEmptyDictionaryReturnsInput() {
        XCTAssertEqual(DeterministicCleanup.applyDictionary("um hello there", dictionary: []), "um hello there")
    }

    func testFillerOnlyTextBecomesEmpty() {
        XCTAssertEqual(DeterministicCleanup.apply("uh, um... hmm", dictionary: []), "")
    }

    func testShortDictationDropsPeriodAndCapital() {
        XCTAssertEqual(DeterministicCleanup.apply("um sounds good.", dictionary: []), "sounds good")
    }

    func testShortDictationKeepsDictionaryCasing() {
        let dictionary = [DictionaryEntry(written: "GitHub", type: .properNoun, soundsLike: ["github"])]
        XCTAssertEqual(DeterministicCleanup.apply("Github please.", dictionary: dictionary), "GitHub please")
    }

    func testShortDictationLeavesOtherLanguagesAlone() {
        XCTAssertEqual(DeterministicCleanup.apply("Danke schön.", dictionary: []), "Danke schön.")
    }

    // MARK: runs(on:language:) — cleanup is English-only for now

    func testRunsOnEnglishWhenEnglishIsChosen() {
        XCTAssertTrue(DeterministicCleanup.runs(on: "um send it today", language: "en"))
    }

    func testSkipsWhenAnotherLanguageIsChosen() {
        XCTAssertFalse(DeterministicCleanup.runs(on: "um send it today", language: "de"))
        XCTAssertFalse(DeterministicCleanup.runs(on: "Wir treffen uns um acht", language: "fr"))
    }

    func testDetectsTheLanguageWhenAutomatic() {
        XCTAssertTrue(DeterministicCleanup.runs(on: "I think we should meet at three tomorrow", language: nil))
        XCTAssertFalse(DeterministicCleanup.runs(on: "Wir treffen uns morgen um acht Uhr im Büro", language: nil))
    }

    func testRunsWhenTheLanguageCantBeDetected() {
        XCTAssertTrue(DeterministicCleanup.runs(on: "uh, um", language: nil))
    }
}
