import XCTest
@testable import TalkToMyMacCore

final class InputRoutingTargetTests: XCTestCase {

    func testBuiltInOnlyAlwaysPicksTheBuiltInMicrophone() {
        XCTAssertEqual(InputRouting.targetUID(selection: .systemDefault, builtInOnly: true,
                                              builtInUID: "builtin", connected: { ["builtin", "bt"] }),
                       "builtin")
        XCTAssertEqual(InputRouting.targetUID(selection: .device(uid: "bt"), builtInOnly: true,
                                              builtInUID: "builtin", connected: { ["builtin", "bt"] }),
                       "builtin")
    }

    /// The whole point of the mode is to avoid asking CoreAudio about other devices.
    func testBuiltInOnlyDoesNotReadTheConnectedDeviceList() {
        _ = InputRouting.targetUID(selection: .device(uid: "bt"), builtInOnly: true,
                                   builtInUID: "builtin", connected: { XCTFail("read the device list"); return [] })
    }

    func testBuiltInOnlyFallsBackToSystemDefaultWhenNoBuiltInMicrophone() {
        XCTAssertNil(InputRouting.targetUID(selection: .device(uid: "bt"), builtInOnly: true,
                                            builtInUID: nil, connected: { ["bt"] }))
    }

    func testOtherwiseFollowsTheSelection() {
        XCTAssertEqual(InputRouting.targetUID(selection: .device(uid: "usb"), builtInOnly: false,
                                              builtInUID: "builtin", connected: { ["usb"] }), "usb")
        XCTAssertNil(InputRouting.targetUID(selection: .device(uid: "usb"), builtInOnly: false,
                                            builtInUID: "builtin", connected: { [] }))
        XCTAssertNil(InputRouting.targetUID(selection: .systemDefault, builtInOnly: false,
                                            builtInUID: "builtin", connected: { ["usb"] }))
    }
}
