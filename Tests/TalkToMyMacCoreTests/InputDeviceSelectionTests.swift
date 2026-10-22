import XCTest
@testable import TalkToMyMacCore

final class InputDeviceSelectionTests: XCTestCase {

    private let builtIn = "BuiltInMicrophoneDevice"
    private let airPods = "AirPods-UID"

    func testSystemDefaultRecordsFromWhateverTheSystemUses() {
        XCTAssertNil(InputDeviceSelection.systemDefault.deviceUID(connected: [builtIn, airPods]))
    }

    func testChosenDeviceIsUsedWhenConnected() {
        let selection = InputDeviceSelection.device(uid: builtIn)
        XCTAssertEqual(selection.deviceUID(connected: [airPods, builtIn]), builtIn)
    }

    func testFallsBackToSystemDefaultWhenChosenDeviceIsDisconnected() {
        let selection = InputDeviceSelection.device(uid: "USB-Mic-UID")
        XCTAssertNil(selection.deviceUID(connected: [builtIn, airPods]))
    }

    func testPersistsAsAnOptionalUID() {
        XCTAssertNil(InputDeviceSelection.systemDefault.persistedUID)
        XCTAssertEqual(InputDeviceSelection.device(uid: builtIn).persistedUID, builtIn)
    }

    func testRestoresFromPersistedUID() {
        XCTAssertEqual(InputDeviceSelection(persistedUID: nil), .systemDefault)
        XCTAssertEqual(InputDeviceSelection(persistedUID: ""), .systemDefault)
        XCTAssertEqual(InputDeviceSelection(persistedUID: builtIn), .device(uid: builtIn))
    }
}
