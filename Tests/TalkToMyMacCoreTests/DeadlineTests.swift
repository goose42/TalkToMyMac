import Foundation
import XCTest
@testable import TalkToMyMacCore

final class DeadlineTests: XCTestCase {

    func testReturnsResultWhenOperationFinishesInTime() async {
        let result = await withDeadline(.seconds(1)) { "done" }
        XCTAssertEqual(result, "done")
    }

    func testReturnsNilWhenOperationOverruns() async {
        let result = await withDeadline(.milliseconds(50)) { () -> String in
            try? await Task.sleep(for: .seconds(5))
            return "late"
        }
        XCTAssertNil(result)
    }

    // The on-device model may not stop when cancelled; the deadline must not wait for it.
    func testDoesNotWaitForOperationThatIgnoresCancellation() async {
        let clock = ContinuousClock()
        let start = clock.now
        let result = await withDeadline(.milliseconds(50)) { () -> Int in
            let end = ContinuousClock.now + .seconds(2)
            while ContinuousClock.now < end { await Task.yield() }
            return 1
        }
        XCTAssertNil(result)
        XCTAssertLessThan(clock.now - start, .seconds(1))
    }

    func testCancelsOperationOnTimeout() async throws {
        let cancelled = expectation(description: "operation cancelled")
        _ = await withDeadline(.milliseconds(50)) { () -> Void in
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                cancelled.fulfill()
            }
        }
        await fulfillment(of: [cancelled], timeout: 1)
    }

    func testFormattingTimeoutIsFourSeconds() {
        XCTAssertEqual(FormattingDeadline.timeout, .seconds(4))
    }

    func testTimedOutNotice() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let notice = IndicatorNotice.formattingTimedOut(.groq, shownAt: start)
        XCTAssertEqual(notice.style, .error)
        XCTAssertEqual(notice.title, "LLM formatting failed")
        XCTAssertEqual(notice.message, "Groq didn't respond within 4 seconds. Pasted without formatting.")
        XCTAssertEqual(notice.duration, 10)
        XCTAssertEqual(IndicatorNotice.formattingTimedOut(.appleOnDevice, shownAt: start).message,
                       "Apple Intelligence (on-device) didn't respond within 4 seconds. Pasted without formatting.")
    }
}
