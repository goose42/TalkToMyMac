import Foundation
import Synchronization
import XCTest
@testable import TalkToMyMacCore

final class AudioWorkQueueTests: XCTestCase {

    func testAsyncReturnsBeforeSlowWorkFinishes() async {
        let queue = AudioWorkQueue(label: "test")
        let finished = Mutex(false)
        let started = ContinuousClock.now
        queue.async {
            Thread.sleep(forTimeInterval: 0.3)
            finished.withLock { $0 = true }
        }
        XCTAssertLessThan(ContinuousClock.now - started, .milliseconds(100))
        XCTAssertFalse(finished.withLock { $0 })
        await queue.drain()
        XCTAssertTrue(finished.withLock { $0 })
    }

    func testRunsWorkInSubmissionOrder() async {
        let queue = AudioWorkQueue(label: "test")
        let order = Mutex<[Int]>([])
        for i in 0..<20 {
            queue.async {
                if i == 0 { Thread.sleep(forTimeInterval: 0.05) }
                order.withLock { $0.append(i) }
            }
        }
        await queue.drain()
        XCTAssertEqual(order.withLock { $0 }, Array(0..<20))
    }

    func testSyncWaitsForEarlierWorkAndReturnsValue() {
        let queue = AudioWorkQueue(label: "test")
        let ran = Mutex(false)
        queue.async {
            Thread.sleep(forTimeInterval: 0.1)
            ran.withLock { $0 = true }
        }
        let sawEarlierWork = queue.sync { ran.withLock { $0 } }
        XCTAssertTrue(sawEarlierWork)
    }
}
