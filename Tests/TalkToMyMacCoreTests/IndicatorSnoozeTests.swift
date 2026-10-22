import XCTest
@testable import TalkToMyMacCore

final class IndicatorSnoozeTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000)

    func testNotSnoozedByDefault() {
        let snooze = IndicatorSnooze()
        XCTAssertFalse(snooze.isSnoozed(at: now))
        XCTAssertNil(snooze.remaining(at: now))
    }

    func testHideDurationIsOneHour() {
        XCTAssertEqual(IndicatorSnooze.hideDuration, 3600)
    }

    func testSnoozedUntilDurationElapses() {
        var snooze = IndicatorSnooze()
        snooze.snooze(for: 3600, now: now)
        XCTAssertTrue(snooze.isSnoozed(at: now))
        XCTAssertTrue(snooze.isSnoozed(at: now.addingTimeInterval(3599)))
        XCTAssertFalse(snooze.isSnoozed(at: now.addingTimeInterval(3600)))
        XCTAssertFalse(snooze.isSnoozed(at: now.addingTimeInterval(4000)))
    }

    func testWakeClearsSnooze() {
        var snooze = IndicatorSnooze()
        snooze.snooze(for: 3600, now: now)
        snooze.wake()
        XCTAssertFalse(snooze.isSnoozed(at: now))
        XCTAssertNil(snooze.remaining(at: now))
    }

    func testSnoozingAgainReplacesEndTime() {
        var snooze = IndicatorSnooze()
        snooze.snooze(for: 3600, now: now)
        snooze.snooze(for: 60, now: now)
        XCTAssertFalse(snooze.isSnoozed(at: now.addingTimeInterval(61)))
    }

    func testRemaining() {
        var snooze = IndicatorSnooze()
        snooze.snooze(for: 3600, now: now)
        XCTAssertEqual(snooze.remaining(at: now.addingTimeInterval(600)), 3000)
        XCTAssertNil(snooze.remaining(at: now.addingTimeInterval(3600)))
    }
}
