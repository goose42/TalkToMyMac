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

    func testFillerOnlyTextBecomesEmpty() {
        XCTAssertEqual(DeterministicCleanup.apply("uh, um... hmm", dictionary: []), "")
    }
}
