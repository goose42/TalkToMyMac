import Synchronization
import XCTest
@testable import TalkToMyMacCore

final class InvalidatingCacheTests: XCTestCase {

    func testComputesOnceUntilInvalidated() {
        let computations = Mutex(0)
        let cache = InvalidatingCache<Int> { computations.withLock { $0 += 1; return $0 } }
        XCTAssertEqual(cache.value, 1)
        XCTAssertEqual(cache.value, 1)
        XCTAssertEqual(computations.withLock { $0 }, 1)
    }

    func testRecomputesAfterInvalidate() {
        let computations = Mutex(0)
        let cache = InvalidatingCache<Int> { computations.withLock { $0 += 1; return $0 } }
        _ = cache.value
        cache.invalidate()
        XCTAssertEqual(cache.value, 2)
        XCTAssertEqual(cache.value, 2)
    }

    func testInvalidateBeforeFirstReadIsHarmless() {
        let cache = InvalidatingCache<String> { "x" }
        cache.invalidate()
        XCTAssertEqual(cache.value, "x")
    }
}
