import XCTest
@testable import TalkToMyMacCore

final class GlobalShortcutTests: XCTestCase {

    private func shortcut(_ keyCode: UInt32, _ mods: GlobalShortcut.Modifiers, _ label: String = "X") -> GlobalShortcut {
        GlobalShortcut(keyCode: keyCode, modifiers: mods, keyLabel: label)
    }

    func testDisplayStringUsesStandardModifierOrder() {
        let s = shortcut(49, [.command, .shift, .option, .control], "Space")
        XCTAssertEqual(s.displayString, "⌃⌥⇧⌘Space")
    }

    func testModifierBitsMatchCarbon() {
        // cmdKey, shiftKey, optionKey, controlKey from Carbon's Events.h
        XCTAssertEqual(GlobalShortcut.Modifiers.command.rawValue, 0x0100)
        XCTAssertEqual(GlobalShortcut.Modifiers.shift.rawValue, 0x0200)
        XCTAssertEqual(GlobalShortcut.Modifiers.option.rawValue, 0x0800)
        XCTAssertEqual(GlobalShortcut.Modifiers.control.rawValue, 0x1000)
    }

    func testDefaultsAreFnAndFnSpace() {
        XCTAssertNil(GlobalShortcut.defaultHold.validate(against: .defaultToggle, forHold: true))
        XCTAssertNil(GlobalShortcut.defaultToggle.validate(against: .defaultHold, forHold: false))
        XCTAssertEqual(GlobalShortcut.defaultHold.displayString, "Fn")
        XCTAssertEqual(GlobalShortcut.defaultToggle.displayString, "Fn+Space")
        XCTAssertTrue(GlobalShortcut.defaultHold.usesFunctionKey)
        XCTAssertTrue(GlobalShortcut.defaultToggle.usesFunctionKey)
    }

    func testFnAloneRejectedForToggle() {
        XCTAssertEqual(GlobalShortcut.defaultHold.validate(against: nil, forHold: false), .functionAloneOnlyForHold)
    }

    func testFnModifierNeverReachesCarbon() {
        let s = shortcut(49, [.function, .shift])
        XCTAssertEqual(s.modifiers.carbonOnly, [.shift])
    }

    func testCarbonShortcutDoesNotUseFunctionKey() {
        XCTAssertFalse(shortcut(49, [.control, .shift]).usesFunctionKey)
    }

    func testFnComboDisplay() {
        XCTAssertEqual(shortcut(49, [.function, .command], "Space").displayString, "Fn+⌘Space")
    }

    func testEscapeIsReserved() {
        XCTAssertEqual(shortcut(GlobalShortcut.escapeKeyCode, [.command]).validate(against: nil), .escapeReserved)
    }

    func testBareLetterIsRejected() {
        XCTAssertEqual(shortcut(0, []).validate(against: nil), .needsModifier) // kVK_ANSI_A
    }

    func testBareFunctionKeyIsAllowed() {
        XCTAssertNil(shortcut(96, [], "F5").validate(against: nil))
    }

    func testDuplicateIgnoresLabel() {
        let a = shortcut(49, [.option], "Space")
        let b = shortcut(49, [.option], "space")
        XCTAssertEqual(a.validate(against: b), .duplicate)
    }

    func testSameKeyDifferentModifiersIsNotDuplicate() {
        XCTAssertNil(shortcut(49, [.option]).validate(against: shortcut(49, [.control])))
    }

    func testCodableRoundTrip() throws {
        let original = shortcut(2, [.control, .option], "D")
        let decoded = try JSONDecoder().decode(GlobalShortcut.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }
}
