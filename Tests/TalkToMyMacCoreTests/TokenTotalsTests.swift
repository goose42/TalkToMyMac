import XCTest
@testable import TalkToMyMacCore

final class TokenTotalsTests: XCTestCase {

    func testSumsUsageAcrossDictations() {
        let totals = TokenTotals.sum([
            TokenUsage(input: 100, output: 40, reasoning: 10, cached: 0),
            TokenUsage(input: 200, output: 60, reasoning: 30, cached: 50),
        ])
        XCTAssertEqual(totals, TokenTotals(dictations: 2, input: 300, output: 100, reasoning: 40, cached: 50))
    }

    func testDictationsWithoutUsageAreNotCounted() {
        let totals = TokenTotals.sum([TokenUsage(input: 10, output: 5, reasoning: 0, cached: 0), nil])
        XCTAssertEqual(totals?.dictations, 1)
        XCTAssertEqual(totals?.input, 10)
    }

    func testNoUsageAtAllIsNil() {
        XCTAssertNil(TokenTotals.sum([nil, nil]))
        XCTAssertNil(TokenTotals.sum([]))
    }

    func testTotalAndAverages() throws {
        let totals = try XCTUnwrap(TokenTotals.sum([
            TokenUsage(input: 100, output: 40, reasoning: 0, cached: 0),
            TokenUsage(input: 201, output: 61, reasoning: 0, cached: 0),
        ]))
        XCTAssertEqual(totals.total, 402)
        XCTAssertEqual(totals.averageInput, 150.5)
        XCTAssertEqual(totals.averageOutput, 50.5)
    }
}

final class TokenPriceTests: XCTestCase {

    private let price = TokenPrice(inputPerMillion: 0.10, cachedInputPerMillion: 0.05, outputPerMillion: 0.50)

    func testCostBillsCachedInputAtCachedRate() {
        // 1M input of which 200k cached, 400k output:
        // 800k × $0.10 + 200k × $0.05 + 400k × $0.50 = $0.08 + $0.01 + $0.20
        let totals = TokenTotals(dictations: 4, input: 1_000_000, output: 400_000, reasoning: 100_000, cached: 200_000)
        XCTAssertEqual(totals.cost(at: price), 0.29, accuracy: 1e-12)
        XCTAssertEqual(totals.averageCost(at: price), 0.0725, accuracy: 1e-12)
    }

    func testReasoningIsBilledAsPartOfOutput() {
        let withReasoning = TokenTotals(dictations: 1, input: 0, output: 1_000, reasoning: 900, cached: 0)
        let without = TokenTotals(dictations: 1, input: 0, output: 1_000, reasoning: 0, cached: 0)
        XCTAssertEqual(withReasoning.cost(at: price), without.cost(at: price))
    }

    func testGroqListPriceForGptOss20b() {
        XCTAssertEqual(GroqModel.gptOss20b.listPrice,
                       TokenPrice(inputPerMillion: 0.075, cachedInputPerMillion: 0.0375, outputPerMillion: 0.30))
    }

    func testPriceRoundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(["openai/gpt-oss-20b": price])
        XCTAssertEqual(try JSONDecoder().decode([String: TokenPrice].self, from: data), ["openai/gpt-oss-20b": price])
    }
}
