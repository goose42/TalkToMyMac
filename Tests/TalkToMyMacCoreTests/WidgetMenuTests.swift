import XCTest
@testable import TalkToMyMacCore

final class WidgetMenuTests: XCTestCase {

    func testItemsAreInOrder() {
        let items = WidgetMenu.items(isRecording: false, hasLastTranscript: true)
        XCTAssertEqual(items.map(\.action), [.copyLastTranscript, .toggleRecording, .hideForAnHour])
    }

    func testRecordingItemSaysStartWhenIdle() {
        let item = WidgetMenu.items(isRecording: false, hasLastTranscript: true)[1]
        XCTAssertEqual(item.title, "Start Recording")
        XCTAssertEqual(item.symbol, "record.circle")
    }

    func testRecordingItemSaysStopWhileRecording() {
        let item = WidgetMenu.items(isRecording: true, hasLastTranscript: true)[1]
        XCTAssertEqual(item.title, "Stop Recording")
        XCTAssertEqual(item.symbol, "stop.circle")
    }

    func testCopyTitle() {
        XCTAssertEqual(WidgetMenu.items(isRecording: false, hasLastTranscript: true)[0].title,
                       "Copy Last Dictation")
    }

    func testCopyDisabledWithoutTranscript() {
        XCTAssertFalse(WidgetMenu.items(isRecording: false, hasLastTranscript: false)[0].isEnabled)
        XCTAssertTrue(WidgetMenu.items(isRecording: false, hasLastTranscript: true)[0].isEnabled)
    }

    func testHideAndRecordingAlwaysEnabled() {
        for recording in [true, false] {
            let items = WidgetMenu.items(isRecording: recording, hasLastTranscript: false)
            XCTAssertTrue(items[1].isEnabled)
            XCTAssertTrue(items[2].isEnabled)
            XCTAssertEqual(items[2].title, "Hide for 1 Hour")
        }
    }
}
