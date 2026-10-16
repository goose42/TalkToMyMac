import XCTest
@testable import TalkToMyMacCore

final class FuzzyMatchTests: XCTestCase {

    private func score(_ query: String, _ candidate: String) -> Int? {
        FuzzyMatch.score(query, in: candidate)
    }

    /// Asserts each candidate scores strictly higher than the next for `query`.
    private func assertRanked(_ query: String, _ candidates: [String],
                              file: StaticString = #filePath, line: UInt = #line) {
        let scores = candidates.map { score(query, $0) }
        for (candidate, score) in zip(candidates, scores) {
            XCTAssertNotNil(score, "\"\(query)\" should match \"\(candidate)\"", file: file, line: line)
        }
        for i in candidates.indices.dropLast() {
            guard let higher = scores[i], let lower = scores[i + 1] else { continue }
            XCTAssertGreaterThan(higher, lower, "\"\(candidates[i])\" should outrank \"\(candidates[i + 1])\"",
                                 file: file, line: line)
        }
    }

    // MARK: Matching

    func testEmptyQueryMatchesAnythingWithZeroScore() {
        XCTAssertEqual(score("", "OTel"), 0)
        XCTAssertEqual(score("   ", "OTel"), 0)
        XCTAssertEqual(score("", ""), 0)
    }

    func testSubsequenceMatches() {
        XCTAssertNotNil(score("otl", "OTel"))
        XCTAssertNotNil(score("kbn", "Kubernetes"))
    }

    func testOutOfOrderCharactersDontMatch() {
        XCTAssertNil(score("lto", "OTel"))
        XCTAssertNil(score("x", "OTel"))
    }

    func testQueryLongerThanCandidateDoesntMatch() {
        XCTAssertNil(score("otelx", "OTel"))
        XCTAssertNil(score("a", ""))
    }

    func testMatchingIgnoresCase() {
        XCTAssertNotNil(score("OTEL", "otel"))
        XCTAssertNotNil(score("otel", "OTel"))
    }

    func testMatchingIgnoresDiacritics() {
        XCTAssertNotNil(score("cafe", "Café"))
        XCTAssertNotNil(score("café", "Cafe"))
    }

    func testWhitespaceInQueryIsIgnored() {
        XCTAssertNotNil(score("o tel", "OTel"))
    }

    // MARK: Ranking

    func testExactMatchOutranksEverything() {
        assertRanked("pg", ["pg", "pgvector"])
        assertRanked("otel", ["OTel", "OTel Collector"])
    }

    func testPrefixOutranksWordBoundaryOutranksScattered() {
        assertRanked("pg", ["pgvector", "PostGres", "upgrade"])
    }

    func testCamelCaseHumpCountsAsWordBoundary() {
        assertRanked("gr", ["PostGres", "PostagRes"])
    }

    func testSeparatorsCountAsWordBoundaries() {
        for separator in [" ", "-", "_", ".", "/"] {
            assertRanked("c", ["x\(separator)c", "xxc"])
        }
    }

    func testConsecutiveOutranksGapped() {
        assertRanked("kub", ["kubectl", "k-u-b"])
        assertRanked("ten", ["tensor", "t-x-e-x-n"])
    }

    func testFewerSkippedLeadingCharactersRankHigher() {
        assertRanked("tel", ["xtel", "xxxxtel"])
    }
}
