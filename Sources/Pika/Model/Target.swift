import AppKit
import ApplicationServices
import CoreGraphics

/// Stable identity for a row, independent of any single AXUIElement fetch.
/// Windows key on their CGWindowID when available (see PrivateAX.swift);
/// Chrome tabs key on their URL, since tab indices reshuffle constantly.
/// This is also the key used for MRU and learned-selection persistence,
/// where CGWindowID does not survive a restart — see MRUStore.
struct TargetID: Hashable {
    let bundleID: String
    let discriminator: String

    static func window(bundleID: String, cgWindowID: CGWindowID?, fallbackTitle: String) -> TargetID {
        if let cgWindowID {
            return TargetID(bundleID: bundleID, discriminator: "w:\(cgWindowID)")
        }
        return TargetID(bundleID: bundleID, discriminator: "wt:\(fallbackTitle)")
    }

    static func tab(bundleID: String, url: String) -> TargetID {
        TargetID(bundleID: bundleID, discriminator: "tab:\(url)")
    }
}

enum TargetKind {
    case window
    case tab
}

/// What Enter actually does. Kept separate from Target so the matching
/// engine never has to touch AX/AppleScript types.
enum TargetHandle {
    case window(pid: pid_t, ax: AXUIElement)
    case tab(pid: pid_t, ax: AXUIElement, windowIndex: Int, tabIndex: Int)
}

/// One row. `haystack` is precomputed once at build time (never touched
/// per-keystroke) per TECHNICAL.md §4/§7: lowercase, ASCII-folded,
/// "appName\0title" so app-name-start and title-word-start bonuses are
/// simple offset checks into one buffer.
struct Target {
    let id: TargetID
    let kind: TargetKind
    let appName: String
    let bundleID: String
    let title: String

    let haystack: [UInt8]
    let appNameLength: Int      // bytes [0..<appNameLength) are the app name
    let wordStartMask: UInt64   // bit i set => haystack[i] starts a word (first 64 bytes)
    let letterMask: UInt32      // bit (c - 'a') set => letter c appears in haystack

    var lastFocusedAt: TimeInterval
    var icon: NSImage?
    var stale: Bool             // true if served from a cache we couldn't refresh (hung app)

    let handle: TargetHandle
}

enum TargetBuilder {
    /// Word boundaries per UX.md §6: space, -, _, /, ., —, :, plus camelCase.
    private static func isBoundary(_ b: UInt8) -> Bool {
        switch b {
        case UInt8(ascii: " "), UInt8(ascii: "-"), UInt8(ascii: "_"),
             UInt8(ascii: "/"), UInt8(ascii: "."), UInt8(ascii: ":"),
             0: // our appName\0title separator also counts as a boundary
            return true
        default:
            return false
        }
    }

    /// Folds to lowercase ASCII where possible. Non-ASCII bytes are kept
    /// as a single opaque byte (0xFF) — they still participate in gap
    /// counting but never match a query character, which is an acceptable
    /// v1 simplification (queries are typed on a US keyboard).
    private static func foldByte(_ scalar: Unicode.Scalar) -> UInt8 {
        if scalar.isASCII {
            let v = UInt8(scalar.value)
            if v >= 65 && v <= 90 { return v + 32 }
            return v
        }
        return 0xFF
    }

    private static func isUpperAsciiLetter(_ s: Unicode.Scalar) -> Bool {
        s.isASCII && s.value >= 65 && s.value <= 90
    }
    private static func isLowerAsciiLetter(_ s: Unicode.Scalar) -> Bool {
        s.isASCII && s.value >= 97 && s.value <= 122
    }

    /// Single pass over the original (unfolded) scalars of appName + "\0" +
    /// title, producing folded bytes and a word-start bitmask that
    /// recognises space/-/_/./:  boundaries *and* camelCase boundaries
    /// (a lowercase letter followed by an uppercase one).
    static func makeHaystack(appName: String, title: String) -> (bytes: [UInt8], appNameLength: Int, wordStartMask: UInt64) {
        var scalars: [Unicode.Scalar] = []
        scalars.reserveCapacity(appName.unicodeScalars.count + title.unicodeScalars.count + 1)
        scalars.append(contentsOf: appName.unicodeScalars)
        let appNameLength = scalars.count
        scalars.append(Unicode.Scalar(0))
        scalars.append(contentsOf: title.unicodeScalars)

        var bytes: [UInt8] = []
        bytes.reserveCapacity(scalars.count)
        var mask: UInt64 = 0
        var prevWasBoundaryOrStart = true
        var prevWasLower = false

        for (i, s) in scalars.enumerated() {
            let b = foldByte(s)
            bytes.append(b)
            let isStart: Bool
            if b == 0 {
                isStart = false // the separator itself is never a start; the char after it is (via prevWasBoundaryOrStart)
            } else if prevWasBoundaryOrStart {
                isStart = true
            } else if prevWasLower && isUpperAsciiLetter(s) {
                isStart = true
            } else {
                isStart = false
            }
            if isStart && i < 64 {
                mask |= (1 << UInt64(i))
            }
            prevWasBoundaryOrStart = isBoundary(b)
            prevWasLower = isLowerAsciiLetter(s)
        }
        return (bytes, appNameLength, mask)
    }

    static func letterMask(_ bytes: [UInt8]) -> UInt32 {
        var mask: UInt32 = 0
        for b in bytes where b >= UInt8(ascii: "a") && b <= UInt8(ascii: "z") {
            mask |= (1 << UInt32(b - UInt8(ascii: "a")))
        }
        return mask
    }
}
