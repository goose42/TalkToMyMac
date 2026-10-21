import XCTest
@testable import TalkToMyMacCore

final class SystemAudioPolicyTests: XCTestCase {

    private let speakers = "BuiltInSpeakerDevice"
    private let headphones = "AirPods-UID"

    func testOffLeavesEveryDeviceAlone() {
        let policy = SystemAudioPolicy(action: .off, scope: .all)
        XCTAssertEqual(policy.plan(forDeviceUID: speakers), .leaveAlone)
    }

    func testMuteOnAnyDevice() {
        let policy = SystemAudioPolicy(action: .mute, scope: .all)
        XCTAssertEqual(policy.plan(forDeviceUID: speakers), .mute)
        XCTAssertEqual(policy.plan(forDeviceUID: headphones), .mute)
    }

    func testDampenLowersToTheConfiguredLevel() {
        let policy = SystemAudioPolicy(action: .dampen, dampenLevel: 0.3, scope: .all)
        XCTAssertEqual(policy.plan(forDeviceUID: speakers), .lower(toFraction: 0.3))
    }

    func testOnlySelectedDevicesAreAffected() {
        let policy = SystemAudioPolicy(action: .mute, scope: .only([speakers]))
        XCTAssertEqual(policy.plan(forDeviceUID: speakers), .mute)
        XCTAssertEqual(policy.plan(forDeviceUID: headphones), .leaveAlone)
    }

    func testEmptySelectionAffectsNothing() {
        let policy = SystemAudioPolicy(action: .dampen, scope: .only([]))
        XCTAssertEqual(policy.plan(forDeviceUID: speakers), .leaveAlone)
    }

    func testDefaultDampenLevel() {
        XCTAssertEqual(SystemAudioPolicy(action: .dampen, scope: .all).dampenLevel, 0.2)
    }

    func testDampenLevelIsClampedToAFraction() {
        XCTAssertEqual(SystemAudioPolicy(action: .dampen, dampenLevel: 1.5, scope: .all).dampenLevel, 1)
        XCTAssertEqual(SystemAudioPolicy(action: .dampen, dampenLevel: -1, scope: .all).dampenLevel, 0)
    }

    func testDampenedVolumeScalesTheCurrentVolume() {
        XCTAssertEqual(SystemAudioPolicy.dampenedVolume(current: 0.5, level: 0.2), 0.1, accuracy: 0.0001)
    }

    func testDampenedVolumeNeverRaisesTheVolume() {
        XCTAssertEqual(SystemAudioPolicy.dampenedVolume(current: 0.5, level: 2), 0.5, accuracy: 0.0001)
        XCTAssertEqual(SystemAudioPolicy.dampenedVolume(current: 0.5, level: -1), 0, accuracy: 0.0001)
    }

    func testActionsRoundTripThroughRawValues() {
        for action in SystemAudioAction.allCases {
            XCTAssertEqual(SystemAudioAction(rawValue: action.rawValue), action)
        }
        XCTAssertEqual(SystemAudioAction.allCases.map(\.title), ["Off", "Mute", "Dampen"])
    }
}
