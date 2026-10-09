import XCTest
@testable import TalkToMyMacCore

final class WordTotalsTests: XCTestCase {

    func testSumsWordsInAndOutAcrossDictations() {
        let totals = WordTotals.sum([(input: 10, output: 12), (input: 30, output: 28)])
        XCTAssertEqual(totals, WordTotals(dictations: 2, input: 40, output: 40))
    }

    func testNoDictationsIsZero() {
        XCTAssertEqual(WordTotals.sum([]), WordTotals(dictations: 0, input: 0, output: 0))
    }
}
