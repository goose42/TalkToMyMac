import XCTest
@testable import TalkToMyMacCore

final class PaginationTests: XCTestCase {

    func testPageCountRoundsUp() {
        XCTAssertEqual(Pagination(pageSize: 10, totalCount: 23).pageCount, 3)
        XCTAssertEqual(Pagination(pageSize: 10, totalCount: 20).pageCount, 2)
    }

    func testNoRowsIsStillOnePage() {
        XCTAssertEqual(Pagination(pageSize: 10, totalCount: 0).pageCount, 1)
    }

    func testOffsetOfAPage() {
        let pages = Pagination(pageSize: 10, totalCount: 23)
        XCTAssertEqual(pages.offset(of: 0), 0)
        XCTAssertEqual(pages.offset(of: 2), 20)
    }

    // Rows can be purged while a later page is showing, so pages are clamped to what exists.
    func testClampsPagesToTheRowsThatExist() {
        let pages = Pagination(pageSize: 10, totalCount: 23)
        XCTAssertEqual(pages.clamped(5), 2)
        XCTAssertEqual(pages.clamped(-1), 0)
        XCTAssertEqual(Pagination(pageSize: 10, totalCount: 0).clamped(3), 0)
    }

    func testPreviousAndNext() {
        let pages = Pagination(pageSize: 10, totalCount: 23)
        XCTAssertFalse(pages.hasPrevious(0))
        XCTAssertTrue(pages.hasNext(0))
        XCTAssertTrue(pages.hasPrevious(2))
        XCTAssertFalse(pages.hasNext(2))
    }

    func testRangeLabel() {
        let pages = Pagination(pageSize: 10, totalCount: 23)
        XCTAssertEqual(pages.rangeLabel(of: 0), "1–10 of 23")
        XCTAssertEqual(pages.rangeLabel(of: 2), "21–23 of 23")
        XCTAssertEqual(Pagination(pageSize: 10, totalCount: 0).rangeLabel(of: 0), "0 of 0")
    }
}
