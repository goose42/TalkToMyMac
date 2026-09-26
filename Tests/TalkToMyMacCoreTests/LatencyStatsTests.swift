import XCTest
@testable import TalkToMyMacCore

final class LatencyStatsTests: XCTestCase {

    // MARK: perUnit

    func testPerUnitMeanIsTotalTimeOverTotalUnits() {
        // 100 ms for 10 words + 900 ms for 90 words = 1000 ms / 100 words.
        let summary = LatencyStats.perUnit([(time: 100, units: 10), (time: 900, units: 90)])
        XCTAssertEqual(summary?.mean, 10)
        XCTAssertEqual(summary?.sampleCount, 2)
    }

    func testPerUnitMeanIsNotBiasedByShortSamples() {
        // A 1-word dictation with high fixed overhead (300 ms/word) alongside a 99-word one
        // at 10 ms/word. An unweighted mean of rates would say 155 ms/word; weighted by
        // words it's (300 + 990) / 100 = 12.9.
        let summary = LatencyStats.perUnit([(time: 300, units: 1), (time: 990, units: 99)])
        XCTAssertEqual(summary!.mean, 12.9, accuracy: 1e-9)
    }

    func testPerUnitP99IsWeightedByUnits() {
        // The slow sample is only 1% of all words, so the 99th percentile of words is
        // still processed at the fast rate.
        let summary = LatencyStats.perUnit([(time: 300, units: 1), (time: 990, units: 99)])
        XCTAssertEqual(summary?.p99, 10)
    }

    func testPerUnitP99PicksUpSlowSamplesAboveOnePercent() {
        let summary = LatencyStats.perUnit([(time: 600, units: 2), (time: 980, units: 98)])
        XCTAssertEqual(summary?.p99, 300)
    }

    func testPerUnitSkipsZeroUnitSamples() {
        let summary = LatencyStats.perUnit([(time: 500, units: 0), (time: 100, units: 10)])
        XCTAssertEqual(summary?.sampleCount, 1)
        XCTAssertEqual(summary?.mean, 10)
    }

    func testPerUnitEmptyReturnsNil() {
        XCTAssertNil(LatencyStats.perUnit([]))
        XCTAssertNil(LatencyStats.perUnit([(time: 100, units: 0)]))
    }

    // MARK: perSample

    func testPerSampleMeanAndP99() {
        let times = (1...100).map(Double.init)
        let summary = LatencyStats.perSample(times)
        XCTAssertEqual(summary?.mean, 50.5)
        XCTAssertEqual(summary?.p99, 99)
        XCTAssertEqual(summary?.sampleCount, 100)
    }

    func testPerSampleP99WithFewSamplesIsTheMax() {
        XCTAssertEqual(LatencyStats.perSample([5, 1, 3])?.p99, 5)
    }

    func testPerSampleEmptyReturnsNil() {
        XCTAssertNil(LatencyStats.perSample([]))
    }
}
