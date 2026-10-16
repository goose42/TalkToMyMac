import XCTest
@testable import TalkToMyMacCore

final class ReplacementReviewTests: XCTestCase {
    private let dictionary = [DictionaryEntry(written: "OTel", type: .acronym, soundsLike: ["hotel"]),
                              DictionaryEntry(written: "REST", type: .acronym, soundsLike: ["rest"])]

    private func review(_ raw: String, _ text: String) throws -> ReplacementReview {
        try XCTUnwrap(ReplacementReview(raw: raw, text: text, dictionary: dictionary))
    }

    // MARK: Finding occurrences

    func testOffersEachReplacedOccurrenceSeparately() throws {
        let review = try review("there was an hotel conference at a hotel in paris",
                                "There was an OTel conference at a OTel in Paris.")
        XCTAssertEqual(review.occurrences.map(\.original), ["hotel", "hotel"])
        XCTAssertEqual(review.occurrences.map(\.written), ["OTel", "OTel"])
        XCTAssertEqual(review.text(reverting: []), "There was an OTel conference at a OTel in Paris.")
        XCTAssertEqual(review.text(reverting: [1]), "There was an OTel conference at a hotel in Paris.")
        XCTAssertEqual(review.text(reverting: [0, 1]), "There was an hotel conference at a hotel in Paris.")
    }

    func testSkipsTermsTheSpeechModelAlreadyGotRight() throws {
        let review = try review("OTel exports to hotel", "OTel exports to OTel.")
        XCTAssertEqual(review.occurrences.count, 1)
        XCTAssertEqual(review.text(reverting: [0]), "OTel exports to hotel.")
    }

    func testOrdersOccurrencesAcrossTermsByPosition() throws {
        let review = try review("call the rest API from the hotel", "Call the REST API from the OTel.")
        XCTAssertEqual(review.occurrences.map(\.written), ["REST", "OTel"])
        XCTAssertEqual(review.text(reverting: [0]), "Call the rest API from the OTel.")
    }

    func testKeepsTheSpokenCasing() throws {
        XCTAssertEqual(try review("Hotel tracing", "OTel tracing").text(reverting: [0]), "Hotel tracing")
    }

    /// When formatting changed how often the term appears, the order can't be trusted, so
    /// every occurrence in the text is offered.
    func testOffersEveryOccurrenceWhenCountsDisagree() throws {
        let review = try review("hotel and hotel", "OTel.")
        XCTAssertEqual(review.occurrences.count, 1)
        XCTAssertEqual(review.text(reverting: [0]), "hotel.")
    }

    func testNothingToOfferWithoutReplacementsInTheText() {
        XCTAssertNil(ReplacementReview(raw: "add tracing", text: "Add tracing.", dictionary: dictionary))
        XCTAssertNil(ReplacementReview(raw: "add hotel", text: "Add tracing.", dictionary: dictionary))
    }

    func testLeavesLongerWordsAlone() throws {
        let review = try review("hotel OTels", "OTel OTels")
        XCTAssertEqual(review.occurrences.count, 1)
        XCTAssertEqual(review.text(reverting: [0]), "hotel OTels")
    }

    // MARK: Context

    func testContextShowsUpToThreeWordsEachSide() throws {
        let review = try review("there was an hotel conference at a hotel in paris",
                                "There was an OTel conference at a OTel in Paris.")
        let first = review.context(of: 0)
        XCTAssertEqual(first.before, "There was an ")
        XCTAssertEqual(first.after, " conference at a…")
        let second = review.context(of: 1)
        XCTAssertEqual(second.before, "…conference at a ")
        XCTAssertEqual(second.after, " in Paris.")
    }

    // MARK: Editing in place

    func testEditRetypesOnlyTheChangedTail() {
        XCTAssertEqual(ReplacementReview.edit(from: "Add OTel tracing", to: "Add hotel tracing").deleteCount, 12)
        XCTAssertEqual(ReplacementReview.edit(from: "Add OTel tracing", to: "Add hotel tracing").insert, "hotel tracing")
        XCTAssertEqual(ReplacementReview.edit(from: "Use REST", to: "Use rest").deleteCount, 4)
        XCTAssertEqual(ReplacementReview.edit(from: "Use REST", to: "Use rest").insert, "rest")
        XCTAssertEqual(ReplacementReview.edit(from: "Same", to: "Same").deleteCount, 0)
        XCTAssertEqual(ReplacementReview.edit(from: "Same", to: "Same").insert, "")
    }

    func testEditCountsCharactersNotUTF16Units() {
        let edit = ReplacementReview.edit(from: "Hi 👋 OTel", to: "Hi 👋 hotel")
        XCTAssertEqual(edit.deleteCount, 4)
        XCTAssertEqual(edit.insert, "hotel")
    }
}
