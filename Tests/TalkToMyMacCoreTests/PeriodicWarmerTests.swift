import Foundation
import Synchronization
import XCTest
@testable import TalkToMyMacCore

final class PeriodicWarmerTests: XCTestCase {

    private final class Counter: Sendable {
        private let count = Mutex(0)
        func increment() { count.withLock { $0 += 1 } }
        var value: Int { count.withLock { $0 } }
    }

    private func waitUntil(_ condition: () -> Bool, timeout: Duration = .seconds(2)) async {
        let end = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < end {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func testRunsActionImmediatelyOnStart() async {
        let counter = Counter()
        let warmer = PeriodicWarmer(interval: .seconds(60)) { counter.increment() }
        warmer.start()
        await waitUntil { counter.value >= 1 }
        XCTAssertEqual(counter.value, 1)
        warmer.stop()
    }

    func testRepeatsActionEveryInterval() async {
        let counter = Counter()
        let warmer = PeriodicWarmer(interval: .milliseconds(50)) { counter.increment() }
        warmer.start()
        await waitUntil { counter.value >= 3 }
        XCTAssertGreaterThanOrEqual(counter.value, 3)
        warmer.stop()
    }

    func testStopEndsTheLoop() async throws {
        let counter = Counter()
        let warmer = PeriodicWarmer(interval: .milliseconds(30)) { counter.increment() }
        warmer.start()
        await waitUntil { counter.value >= 1 }
        warmer.stop()
        let afterStop = counter.value
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertLessThanOrEqual(counter.value, afterStop + 1)
    }

    func testSecondStartDoesNotStartAnotherLoop() async throws {
        let counter = Counter()
        let warmer = PeriodicWarmer(interval: .seconds(60)) { counter.increment() }
        warmer.start()
        warmer.start()
        await waitUntil { counter.value >= 1 }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(counter.value, 1)
        warmer.stop()
    }

    // A recording left in review mustn't keep the model busy indefinitely.
    func testStopsOnItsOwnAfterMaxDuration() async throws {
        let counter = Counter()
        let warmer = PeriodicWarmer(interval: .milliseconds(20), maxDuration: .milliseconds(70)) {
            counter.increment()
        }
        warmer.start()
        try await Task.sleep(for: .milliseconds(200))
        let settled = counter.value
        XCTAssertGreaterThanOrEqual(settled, 2)
        XCTAssertLessThanOrEqual(settled, 5)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(counter.value, settled)
        warmer.stop()
    }

    func testDefaultMaxDurationIsTwoMinutes() {
        XCTAssertEqual(PeriodicWarmer.defaultMaxDuration, .seconds(120))
    }

    func testStopIsSafeToCallTwiceAndBeforeStart() {
        let warmer = PeriodicWarmer(interval: .seconds(1)) {}
        warmer.stop()
        warmer.start()
        warmer.stop()
        warmer.stop()
    }
}
