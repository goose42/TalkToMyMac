import XCTest
@testable import TalkToMyMacCore

final class IndicatorClickTests: XCTestCase {

    private func action(secondary: Bool = false, notice: Bool = false, review: Bool = false,
                        beforePaste: Bool = false) -> IndicatorClick {
        IndicatorClick.action(isSecondary: secondary, hasNotice: notice, hasReview: review,
                              isBeforePaste: beforePaste)
    }

    func testSecondaryClickAlwaysOpensMenu() {
        for notice in [true, false] {
            for review in [true, false] {
                for beforePaste in [true, false] {
                    XCTAssertEqual(action(secondary: true, notice: notice, review: review,
                                          beforePaste: beforePaste), .openMenu)
                }
            }
        }
    }

    func testPrimaryClickOnPlainDotOpensMenu() {
        XCTAssertEqual(action(), .openMenu)
    }

    func testPrimaryClickDismissesNotice() {
        XCTAssertEqual(action(notice: true), .dismissNotice)
        XCTAssertEqual(action(notice: true, review: true), .dismissNotice)
    }

    func testPrimaryClickTogglesPickerForReview() {
        XCTAssertEqual(action(review: true), .togglePicker)
    }

    func testPrimaryClickDoesNothingWhileWaitingToPaste() {
        XCTAssertEqual(action(review: true, beforePaste: true), .none)
    }
}
