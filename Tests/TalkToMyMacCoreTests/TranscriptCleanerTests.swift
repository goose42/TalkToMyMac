import XCTest
@testable import TalkToMyMacCore

// Ported from BetterWispr's CoreTests.
final class TranscriptCleanerTests: XCTestCase {
    func testCleanerDropsMidSentenceFillersAndKeepsPrecedingPunctuation() {
        XCTAssertEqual(TranscriptCleaner.clean("The tests passed, uh, so merge it um now", language: "en"), "The tests passed, so merge it now")
        XCTAssertEqual(TranscriptCleaner.clean("Rename the file uh, then reload the hmm window", language: "en"), "Rename the file then reload the window")
        XCTAssertEqual(TranscriptCleaner.clean("and uh uh we can build um the export", language: "en"), "and we can build the export")
    }

    func testCleanerCapitalizesAfterSentenceInitialFiller() {
        XCTAssertEqual(TranscriptCleaner.clean("Can you check the logs? um yes, and the tests too.", language: "en"), "Can you check the logs? Yes, and the tests too.")
        XCTAssertEqual(TranscriptCleaner.clean("uh iPhone builds are slow", language: "en"), "iPhone builds are slow")
    }

    func testCleanerMovesTerminalPunctuationFromFiller() {
        XCTAssertEqual(TranscriptCleaner.clean("We are done for today uh.", language: "en"), "We are done for today.")
        XCTAssertEqual(TranscriptCleaner.clean("Is the build ready um?", language: "en"), "Is the build ready?")
    }

    func testCleanerDropsMmFillers() {
        XCTAssertEqual(TranscriptCleaner.clean("mm I think so", language: "en"), "I think so")
        XCTAssertEqual(TranscriptCleaner.clean("Mm, that works.", language: "en"), "That works.")
        XCTAssertEqual(TranscriptCleaner.clean("We could, mmm, try it", language: "en"), "We could, try it")
        XCTAssertEqual(TranscriptCleaner.clean("mm-hmm, that sounds right", language: "en"), "mm-hmm, that sounds right")
        XCTAssertEqual(TranscriptCleaner.clean("Cut it to 5 mm, mm, thanks", language: "en"), "Cut it to 5 mm, thanks")
    }

    func testCleanerDropsYouKnowOnlyWhenSetOffOnBothSides() {
        XCTAssertEqual(TranscriptCleaner.clean("It was, you know, fine.", language: "en"), "It was fine.")
        XCTAssertEqual(TranscriptCleaner.clean("You know, I think so.", language: "en"), "I think so.")
        XCTAssertEqual(TranscriptCleaner.clean("That is what I want, you know.", language: "en"), "That is what I want.")
        XCTAssertEqual(TranscriptCleaner.clean("It works. You know, it is fast.", language: "en"), "It works. It is fast.")
        XCTAssertEqual(TranscriptCleaner.clean("That is what I want, you know", language: "en"), "That is what I want")
    }

    func testCleanerKeepsYouKnowThatIsNotSetOff() {
        XCTAssertEqual(TranscriptCleaner.clean("You know the answer.", language: "en"), "You know the answer.")
        XCTAssertEqual(TranscriptCleaner.clean("Do you know, honestly?", language: "en"), "Do you know, honestly?")
        XCTAssertEqual(TranscriptCleaner.clean("If you know, tell me.", language: "en"), "If you know, tell me.")
        XCTAssertEqual(TranscriptCleaner.clean("Well, you know what I mean.", language: "en"), "Well, you know what I mean.")
        XCTAssertEqual(TranscriptCleaner.clean("It is hard, you know?", language: "en"), "It is hard, you know?")
        XCTAssertEqual(TranscriptCleaner.clean("Do you know?", language: "en"), "Do you know?")
        XCTAssertEqual(TranscriptCleaner.clean("Tuesday, I mean, Wednesday", language: "en"), "Tuesday, I mean, Wednesday")
        XCTAssertEqual(TranscriptCleaner.clean("Du weißt, you know, es ist gut.", language: "de"), "Du weißt, you know, es ist gut.")
    }

    func testCleanerResolvesSelfCorrectionsThatRepeatAWord() {
        XCTAssertEqual(TranscriptCleaner.clean("So let's say I say this sentence uh I want to go to uh Mdabad, sorry, no to Dilli. Are we processing this properly", language: "en"), "So let's say I say this sentence I want to go to Dilli. Are we processing this properly")
        XCTAssertEqual(TranscriptCleaner.clean("I want to go to Ahmedabad, sorry, no, to Delhi.", language: "en"), "I want to go to Delhi.")
        XCTAssertEqual(TranscriptCleaner.clean("Let's meet at 5, no wait, at 6", language: "en"), "Let's meet at 6")
        XCTAssertEqual(TranscriptCleaner.clean("Let's meet at 5, no, at 6 pm.", language: "en"), "Let's meet at 6 pm.")
        XCTAssertEqual(TranscriptCleaner.clean("Send it to Sam, no, send it to Alex.", language: "en"), "Send it to Alex.")
        XCTAssertEqual(TranscriptCleaner.clean("Book the window seat, I mean, the aisle seat", language: "en"), "Book the aisle seat")
        XCTAssertEqual(TranscriptCleaner.clean("I live in Ahmedabad, sorry, in Delhi.", language: "en"), "I live in Delhi.")
        XCTAssertEqual(TranscriptCleaner.clean("I live in Ahmedabad sorry in Delhi", language: "en"), "I live in Delhi")
        XCTAssertEqual(TranscriptCleaner.clean("Let's meet at 5 sorry at 6.", language: "en"), "Let's meet at 6.")
        XCTAssertEqual(TranscriptCleaner.clean("Hey, I live in Delhi uh no sorry I live in Ahmedabad.", language: "en"), "Hey, I live in Ahmedabad.")
        XCTAssertEqual(TranscriptCleaner.clean("I live in Pune, sorry, no, I live in Delhi.", language: "en"), "I live in Delhi.")
    }

    func testCleanerKeepsCorrectionLookalikes() {
        XCTAssertEqual(TranscriptCleaner.clean("I said yes to the plan, no to the budget.", language: "en"), "I said yes to the plan, no to the budget.")
        XCTAssertEqual(TranscriptCleaner.clean("I can't make it, sorry, I have a meeting.", language: "en"), "I can't make it, sorry, I have a meeting.")
        XCTAssertEqual(TranscriptCleaner.clean("Should we go, no, we should stay.", language: "en"), "Should we go, no, we should stay.")
        XCTAssertEqual(TranscriptCleaner.clean("I said no sorry I can't come.", language: "en"), "I said no sorry I can't come.")
        XCTAssertEqual(TranscriptCleaner.clean("We booked at noon and had no wait at all.", language: "en"), "We booked at noon and had no wait at all.")
        XCTAssertEqual(TranscriptCleaner.clean("Is it at 5? No, at 6.", language: "en"), "Is it at 5? No, at 6.")
        XCTAssertEqual(TranscriptCleaner.clean("We read it in the last book, no, the whole thing with the houses was different.", language: "en"), "We read it in the last book, no, the whole thing with the houses was different.")
        XCTAssertEqual(TranscriptCleaner.clean("It was the closest to like, I mean, the first one was obviously very close, but not the second.", language: "en"), "It was the closest to like, I mean, the first one was obviously very close, but not the second.")
        XCTAssertEqual(TranscriptCleaner.clean("Thanks for coming, sorry for the wait.", language: "en"), "Thanks for coming, sorry for the wait.")
        XCTAssertEqual(TranscriptCleaner.clean("Go to Ahmedabad, sorry, no, Delhi", language: "en"), "Go to Ahmedabad, sorry, no, Delhi")
        XCTAssertEqual(TranscriptCleaner.clean("Thanks for coming sorry for the wait.", language: "en"), "Thanks for coming sorry for the wait.")
        XCTAssertEqual(TranscriptCleaner.clean("We need to talk, sorry to interrupt.", language: "en"), "We need to talk, sorry to interrupt.")
        XCTAssertEqual(TranscriptCleaner.clean("I asked about it sorry about that.", language: "en"), "I asked about it sorry about that.")
        XCTAssertEqual(TranscriptCleaner.clean("I'm in the office so sorry in advance.", language: "en"), "I'm in the office so sorry in advance.")
        XCTAssertEqual(TranscriptCleaner.clean("I'll be in the office late sorry in advance.", language: "en"), "I'll be in the office late sorry in advance.")
        XCTAssertEqual(TranscriptCleaner.clean("I missed the call, sorry, the train was late.", language: "en"), "I missed the call, sorry, the train was late.")
        XCTAssertEqual(TranscriptCleaner.clean("Thanks for the help everyone sorry the call ran late.", language: "en"), "Thanks for the help everyone sorry the call ran late.")
    }

    func testCleanerRemovesRepeatedPhrases() {
        XCTAssertEqual(TranscriptCleaner.clean("Then we can we can deploy the app", language: "en"), "Then we can deploy the app")
        XCTAssertEqual(TranscriptCleaner.clean("I want to I want to fix the login bug", language: nil), "I want to fix the login bug")
        XCTAssertEqual(TranscriptCleaner.clean("and then and then we shipped it", language: "en"), "and then we shipped it")
    }

    func testCleanerKeepsFirstCopyOfStutteredWord() {
        XCTAssertEqual(TranscriptCleaner.clean("We we should test it", language: "en"), "We should test it")
        XCTAssertEqual(TranscriptCleaner.clean("I I I think so", language: "en"), "I think so")
    }

    func testCleanerKeepsDeliberateRepeats() {
        XCTAssertEqual(TranscriptCleaner.clean("Hello, hello, hello, is this on?", language: "en"), "Hello, hello, hello, is this on?")
        XCTAssertEqual(TranscriptCleaner.clean("I know that that works", language: "en"), "I know that that works")
        XCTAssertEqual(TranscriptCleaner.clean("a long long time ago", language: "en"), "a long long time ago")
        XCTAssertEqual(TranscriptCleaner.clean("call 5 5 5 now", language: "en"), "call 5 5 5 now")
        XCTAssertEqual(TranscriptCleaner.clean("dial one one two", language: "en"), "dial one one two")
        XCTAssertEqual(TranscriptCleaner.clean("in twenty twenty five, a fifty fifty split", language: "en"), "in twenty twenty five, a fifty fifty split")
        XCTAssertEqual(TranscriptCleaner.clean("uh-huh, that sounds right", language: "en"), "uh-huh, that sounds right")
        XCTAssertEqual(TranscriptCleaner.clean("drinking more and more and more", language: "en"), "drinking more and more and more")
        XCTAssertEqual(TranscriptCleaner.clean("we tried again and again and again", language: "en"), "we tried again and again and again")
    }

    func testCleanerLeavesOtherLanguagesAndEmptiesFillerOnlyText() {
        XCTAssertEqual(TranscriptCleaner.clean(" Wir treffen uns um acht Uhr ", language: "de"), "Wir treffen uns um acht Uhr")
        XCTAssertEqual(TranscriptCleaner.clean("uh, um... hmm", language: "en"), "")
        XCTAssertEqual(TranscriptCleaner.clean("Uh, um.", language: nil), "")
        XCTAssertEqual(TranscriptCleaner.clean("Wir treffen uns um acht Uhr", language: nil), "Wir treffen uns um acht Uhr")
        XCTAssertEqual(TranscriptCleaner.clean("", language: "en"), "")
    }
}
