import Carbon.HIToolbox
import Testing
@testable import Pika

@Suite struct SystemShortcutsTests {
    let space = UInt32(kVK_Space)
    let ctrl = UInt32(controlKey)

    static func entry(enabled: Bool, keyCode: Int, modifiers: Int) -> [String: Any] {
        ["enabled": enabled, "value": ["parameters": [32, keyCode, modifiers], "type": "standard"]]
    }

    @Test func factoryDefaultsClaimCtrlSpace() {
        #expect(SystemShortcuts.conflict(keyCode: space, carbonModifiers: ctrl, stored: [:]) == "Select the previous input source")
        #expect(SystemShortcuts.conflict(keyCode: space, carbonModifiers: UInt32(cmdKey), stored: [:]) == "Show Spotlight search")
        #expect(SystemShortcuts.conflict(keyCode: space, carbonModifiers: UInt32(optionKey), stored: [:]) == nil)
    }

    @Test func disabledShortcutDoesNotConflict() {
        let stored: [String: Any] = ["60": Self.entry(enabled: false, keyCode: 49, modifiers: 0x40000)]
        #expect(SystemShortcuts.conflict(keyCode: space, carbonModifiers: ctrl, stored: stored) == nil)
    }

    @Test func remappedShortcutIsFollowed() {
        // Input sources moved to ctrl+k: ctrl+space is free, ctrl+k isn't.
        let stored: [String: Any] = ["60": Self.entry(enabled: true, keyCode: 40, modifiers: 0x40000)]
        #expect(SystemShortcuts.conflict(keyCode: space, carbonModifiers: ctrl, stored: stored) == nil)
        #expect(SystemShortcuts.conflict(keyCode: 40, carbonModifiers: ctrl, stored: stored) == "Select the previous input source")
    }

    @Test func unknownShortcutsAndExtraFlagBits() {
        // macOS sometimes stores extra bits (e.g. the numeric-pad flag) alongside the modifiers.
        let stored: [String: Any] = ["999": Self.entry(enabled: true, keyCode: 45, modifiers: 0x100000 | 0x200000)]
        #expect(SystemShortcuts.conflict(keyCode: 45, carbonModifiers: UInt32(cmdKey), stored: stored) == "a macOS keyboard shortcut")
    }
}
