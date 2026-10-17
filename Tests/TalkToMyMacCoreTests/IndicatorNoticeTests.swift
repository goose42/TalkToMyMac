import Foundation
import XCTest
@testable import TalkToMyMacCore

final class IndicatorNoticeTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)

    func testDefaultsToTenSeconds() {
        let notice = IndicatorNotice(title: "Hello", message: "World", style: .info, shownAt: start)
        XCTAssertEqual(notice.duration, 10)
        XCTAssertEqual(notice.expiresAt, start.addingTimeInterval(10))
    }

    func testRemainingFractionCountsDownAndClamps() {
        let notice = IndicatorNotice(title: "t", message: "m", style: .info, duration: 10, shownAt: start)
        XCTAssertEqual(notice.remainingFraction(at: start), 1)
        XCTAssertEqual(notice.remainingFraction(at: start.addingTimeInterval(2.5)), 0.75, accuracy: 1e-9)
        XCTAssertEqual(notice.remainingFraction(at: start.addingTimeInterval(10)), 0)
        XCTAssertEqual(notice.remainingFraction(at: start.addingTimeInterval(60)), 0)
        XCTAssertEqual(notice.remainingFraction(at: start.addingTimeInterval(-5)), 1)
    }

    func testEachNoticeIsDistinct() {
        let a = IndicatorNotice(title: "t", message: "m", style: .info, shownAt: start)
        let b = IndicatorNotice(title: "t", message: "m", style: .info, shownAt: start)
        XCTAssertNotEqual(a.id, b.id)
    }

    func testFormattingFailedNotice() {
        let pause = FormattingPause(provider: .groq, reason: "Invalid API Key",
                                    until: start.addingTimeInterval(3600))
        let notice = IndicatorNotice.formattingFailed(pause, shownAt: start)
        XCTAssertEqual(notice.style, .error)
        XCTAssertEqual(notice.title, "Groq formatting failed")
        XCTAssertEqual(notice.message, "Invalid API Key. Formatting is paused for 1 hour.")
        XCTAssertEqual(notice.duration, 10)
    }

    func testFormattingFailedNoticeAvoidsDoublePeriod() {
        let pause = FormattingPause(provider: .openRouter, reason: "Provider returned error.",
                                    until: start.addingTimeInterval(3600))
        XCTAssertEqual(IndicatorNotice.formattingFailed(pause, shownAt: start).message,
                       "Provider returned error. Formatting is paused for 1 hour.")
    }
}

final class FormattingPauseTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 50_000)

    func testFailedRemoteCallPausesForAnHour() {
        let outcome = FormattingOutcome(model: .openRouter(.gemma4), text: nil, failure: "Rate limited")
        let pause = FormattingPause.after(outcome, at: now)
        XCTAssertEqual(pause, FormattingPause(provider: .openRouter, reason: "Rate limited",
                                              until: now.addingTimeInterval(3600)))
        XCTAssertEqual(FormattingPause.duration, 3600)
    }

    func testSuccessfulCallDoesNotPause() {
        let outcome = FormattingOutcome(model: .groq(.gptOss20b), text: "Hi.")
        XCTAssertNil(FormattingPause.after(outcome, at: now))
    }

    func testOnDeviceFailureDoesNotPause() {
        let outcome = FormattingOutcome(model: .appleOnDevice, text: nil, failure: "Unavailable")
        XCTAssertNil(FormattingPause.after(outcome, at: now))
    }

    func testFailureWithoutReasonStillPauses() {
        let outcome = FormattingOutcome(model: .groq(.gptOss20b), text: nil)
        XCTAssertEqual(FormattingPause.after(outcome, at: now)?.reason, "The request failed")
    }

    func testActiveOnlyForItsProviderUntilExpiry() {
        let pause = FormattingPause(provider: .groq, reason: "x", until: now.addingTimeInterval(60))
        XCTAssertTrue(pause.isActive(for: .groq, at: now))
        XCTAssertFalse(pause.isActive(for: .openRouter, at: now))
        XCTAssertFalse(pause.isActive(for: .appleOnDevice, at: now))
        XCTAssertFalse(pause.isActive(for: .groq, at: now.addingTimeInterval(60)))
    }

    func testRoundTripsThroughJSON() throws {
        let pause = FormattingPause(provider: .openRouter, reason: "HTTP 429", until: now)
        let data = try JSONEncoder().encode(pause)
        XCTAssertEqual(try JSONDecoder().decode(FormattingPause.self, from: data), pause)
    }
}
