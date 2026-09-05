import Foundation
import AppKit

/// The hot-path read surface: an immutable array of targets, swapped in
/// whole by background sources. Readers never see a torn state and never
/// block on a source (TECHNICAL.md §2, §4). The lock only ever guards a
/// pointer/array swap — never AX, AppleScript, or disk I/O — so it's held
/// for nanoseconds.
final class IndexStore {
    static let shared = IndexStore()

    private var lock = NSLock()
    private var _targets: [Target] = []

    /// Grab-and-go: callers take this once at the start of a query and
    /// do all matching against the local copy (arrays are COW, so this
    /// is a cheap retain, not a deep copy).
    var targets: [Target] {
        lock.lock(); defer { lock.unlock() }
        return _targets
    }

    /// Full structural replace — called by WindowSource/ChromeTabSource
    /// after they've done their (possibly slow) work off the main thread.
    func replace(_ newTargets: [Target]) {
        lock.lock(); _targets = newTargets; lock.unlock()
    }

    /// Cheap recency-only patch so a focus change reflects instantly
    /// without waiting for (or triggering) a structural AX rebuild.
    func bumpRecency(_ id: TargetID, to time: TimeInterval) {
        lock.lock()
        if let i = _targets.firstIndex(where: { $0.id == id }) {
            _targets[i].lastFocusedAt = time
        }
        lock.unlock()
    }

    /// Merge tab-level rows for one app in, replacing any window-level
    /// row(s) for that app's tabbed windows. Used by ChromeTabSource's
    /// tiered fill (T0 windows -> T1 focused window's tabs -> T2 rest).
    func mergeTabs(bundleID: String, replacing windowIDsToRemove: Set<TargetID>, with tabs: [Target]) {
        lock.lock()
        _targets.removeAll { windowIDsToRemove.contains($0.id) }
        // Replace-by-id: drop any stale tab rows for the same ids before re-adding.
        let newIDs = Set(tabs.map { $0.id })
        _targets.removeAll { newIDs.contains($0.id) }
        _targets.append(contentsOf: tabs)
        lock.unlock()
    }

    func updateIcon(bundleID: String, icon: NSImageBox) {
        lock.lock()
        for i in _targets.indices where _targets[i].bundleID == bundleID {
            _targets[i].icon = icon.image
        }
        lock.unlock()
    }
}

/// Sendable-friendly wrapper so IconCache can hand an NSImage across a
/// GCD boundary without fighting Swift 5 mode's looser (but still
/// present) concurrency warnings.
struct NSImageBox { let image: NSImage? }
