import Carbon.HIToolbox
import Foundation

/// macOS's own keyboard shortcuts (System Settings → Keyboard → Keyboard
/// Shortcuts). These don't go through `RegisterEventHotKey`, so Pika's
/// registration succeeds even when macOS will swallow the keypress first —
/// the silent failure behind SHIPPING.md §4.2, where the default
/// `ctrl+space` is also "Select the previous input source" out of the box.
enum SystemShortcuts {
    private struct Known {
        let name: String
        let keyCode: Int
        let modifiers: Int // Cocoa flags, as stored in com.apple.symbolichotkeys
    }

    /// The shortcuts a switcher hotkey is likely to collide with, with
    /// their factory settings. Used when the user has never changed them,
    /// in which case macOS stores no entry at all.
    private static let known: [Int: Known] = [
        60: Known(name: "Select the previous input source", keyCode: kVK_Space, modifiers: 0x40000),
        61: Known(name: "Select next source in Input menu", keyCode: kVK_Space, modifiers: 0xC0000),
        64: Known(name: "Show Spotlight search", keyCode: kVK_Space, modifiers: 0x100000),
        65: Known(name: "Show Finder search window", keyCode: kVK_Space, modifiers: 0x180000),
    ]

    private static let modifierMask = 0x20000 | 0x40000 | 0x80000 | 0x100000 // shift, ctrl, option, cmd

    /// The name of the enabled macOS shortcut using this key combination,
    /// or nil if there is none.
    static func conflict(keyCode: UInt32, carbonModifiers: UInt32) -> String? {
        let stored = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString) as? [String: Any]
        return conflict(keyCode: keyCode, carbonModifiers: carbonModifiers, stored: stored ?? [:])
    }

    /// `stored` is the `AppleSymbolicHotKeys` dictionary; separate for tests.
    static func conflict(keyCode: UInt32, carbonModifiers: UInt32, stored: [String: Any]) -> String? {
        let wanted = cocoaModifiers(carbonModifiers)

        for (key, value) in stored {
            guard let id = Int(key), let entry = value as? [String: Any],
                  (entry["enabled"] as? Bool) == true,
                  let params = (entry["value"] as? [String: Any])?["parameters"] as? [Int], params.count >= 3,
                  params[1] == Int(keyCode), params[2] & modifierMask == wanted
            else { continue }
            return known[id]?.name ?? "a macOS keyboard shortcut"
        }
        for (id, shortcut) in known where stored[String(id)] == nil {
            if shortcut.keyCode == Int(keyCode), shortcut.modifiers == wanted { return shortcut.name }
        }
        return nil
    }

    private static func cocoaModifiers(_ carbon: UInt32) -> Int {
        var flags = 0
        if carbon & UInt32(shiftKey) != 0 { flags |= 0x20000 }
        if carbon & UInt32(controlKey) != 0 { flags |= 0x40000 }
        if carbon & UInt32(optionKey) != 0 { flags |= 0x80000 }
        if carbon & UInt32(cmdKey) != 0 { flags |= 0x100000 }
        return flags
    }
}
