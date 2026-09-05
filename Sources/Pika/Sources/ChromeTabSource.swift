import AppKit
import os

private let log = Logger(subsystem: "dev.pika", category: "chrome")

/// Chrome tab titles, as a background-only refinement layer over the
/// window-level rows WindowSource already produces.
///
/// Measured cost (TECHNICAL.md §0/§5c): the *naive* nested-loop
/// AppleScript formulation costs ~830ms; the bulk `of every window` form
/// used here costs ~70ms in-process. Still 4x the keystroke budget, so
/// this never runs on the hot path — it refreshes in the background and
/// merges into the index via WindowSource.applyChromeMerge().
///
/// Tiered fill (decided in conversation): on cold start, Chrome shows as
/// plain window rows (T0, from WindowSource) until tabs are available.
/// The focused window's tabs (T1) load first, then the rest (T2), so the
/// tabs you're most likely to want become searchable soonest.
final class ChromeTabSource {
    static let shared = ChromeTabSource()
    static let bundleID = "com.google.Chrome"

    enum Tier { case focusedWindow, allWindows }

    private struct RawWindow {
        let chromeWindowID: Int
        let tabTitles: [String]
        let tabURLs: [String]
        let activeTabIndex: Int // 1-based, per AppleScript convention
    }

    private let queue = DispatchQueue(label: "pika.chrome")
    private var rawByWindowID: [Int: RawWindow] = [:]
    private let lock = NSLock()

    private lazy var focusedWindowScript = NSAppleScript(source: """
        tell application "Google Chrome"
            if (count of windows) = 0 then return {{}, {}, {}, {}}
            set w to window 1
            return {{id of w}, {title of every tab of w}, {URL of every tab of w}, {active tab index of w}}
        end tell
        """)

    private lazy var allWindowsScript = NSAppleScript(source: """
        tell application "Google Chrome"
            if (count of windows) = 0 then return {{}, {}, {}, {}}
            return {id of every window, title of tabs of every window, URL of tabs of every window, active tab index of every window}
        end tell
        """)

    private var pendingWork: [Tier: DispatchWorkItem] = [:]
    private var retryDelay: [Tier: TimeInterval] = [:]

    /// Debounced trigger so a burst of "Chrome activated" +
    /// "Chrome window title changed" notifications collapses into one
    /// AppleScript round-trip.
    func scheduleRefresh(tier: Tier, delay: TimeInterval = 0.05) {
        pendingWork[tier]?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.refresh(tier: tier) }
        pendingWork[tier] = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func refresh(tier: Tier) {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first != nil else { return }
        let script = (tier == .focusedWindow) ? focusedWindowScript : allWindowsScript
        guard let script else { return }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        guard errorInfo == nil else {
            log.error("refresh(\(String(describing: tier), privacy: .public)) AppleScript error: \(String(describing: errorInfo), privacy: .public)")
            // The *first* Apple Event Pika ever sends to Chrome always
            // triggers the one-time Automation permission prompt, and
            // that triggering call itself fails while the dialog is up
            // — so a single attempt with no retry can never succeed on
            // a fresh install. Back off and try again; this also covers
            // "Chrome was just launched and is still starting up".
            retryDelay[tier] = min((retryDelay[tier] ?? 1.5) * 1.6, 20)
            scheduleRefresh(tier: tier, delay: retryDelay[tier]!)
            return
        }
        retryDelay[tier] = nil

        guard result.numberOfItems == 4,
              let ids = intList(result.atIndex(1)) else {
            log.error("refresh(\(String(describing: tier), privacy: .public)) unexpected result shape: numberOfItems=\(result.numberOfItems) desc=\(result.description, privacy: .public)")
            return
        }
        let titles = nestedStringList(result.atIndex(2))
        let urls = nestedStringList(result.atIndex(3))
        let activeIdx = intList(result.atIndex(4)) ?? []

        guard ids.count == titles.count, ids.count == urls.count, ids.count == activeIdx.count else {
            log.error("refresh(\(String(describing: tier), privacy: .public)) count mismatch: ids=\(ids.count) titles=\(titles.count) urls=\(urls.count) activeIdx=\(activeIdx.count)")
            return
        }

        lock.lock()
        for i in 0..<ids.count {
            rawByWindowID[ids[i]] = RawWindow(chromeWindowID: ids[i], tabTitles: titles[i], tabURLs: urls[i], activeTabIndex: activeIdx[i])
        }
        lock.unlock()

        if tier == .allWindows {
            scheduleRefresh(tier: .allWindows, delay: 5.0) // idle-timer re-poll while Chrome is around
        }
        WindowSource.shared.applyChromeMerge()
    }

    struct MergeResult {
        let tabTargets: [Target]
        let replacedWindowIDs: Set<TargetID>
    }

    /// Pure/cheap: joins cached AppleScript tab data against the Chrome
    /// window-level Targets from *this* structural sweep (so tab targets
    /// always bind to fresh, valid AXUIElements — never a stale
    /// reference from a previous sweep). Join key is title equality:
    /// Chrome sets a window's title to its active tab's title, verified
    /// empirically before writing this.
    func merge(chromeWindows: [Target]) -> MergeResult? {
        lock.lock(); let raw = rawByWindowID; lock.unlock()
        guard !raw.isEmpty else { return nil }

        // Chrome's AX/OS-level window title always carries a trailing
        // " - Google Chrome" (confirmed by logging real values — the
        // exact-match join this used to do was only ever verified
        // AppleScript-title-to-AppleScript-title, never against the real
        // AX title, which is what WindowSource actually indexes with).
        // Strip it before joining.
        let chromeSuffix = " - Google Chrome"
        func normalized(_ title: String) -> String {
            title.hasSuffix(chromeSuffix) ? String(title.dropLast(chromeSuffix.count)) : title
        }

        var titleToWindow: [String: Target] = [:]
        for w in chromeWindows { titleToWindow[normalized(w.title)] = w }

        var tabTargets: [Target] = []
        var replaced: Set<TargetID> = []

        for (_, rw) in raw {
            let activeTitle = rw.tabTitles.indices.contains(rw.activeTabIndex - 1) ? rw.tabTitles[rw.activeTabIndex - 1] : nil
            guard let activeTitle else { continue }
            // Exact match first; fall back to a prefix match for the
            // cases Chrome tacks on extra badge text after the real
            // title (e.g. "<title> - High memory usage - 1.9 GB -
            // Google Chrome" for a memory-saver-flagged tab) — the real
            // title is always a strict prefix of the decorated one.
            let windowTarget = titleToWindow[activeTitle]
                ?? chromeWindows.first { normalized($0.title).hasPrefix(activeTitle) }
            guard let windowTarget else {
                log.error("merge: no AX window title-matched '\(activeTitle, privacy: .public)' for chrome window id \(rw.chromeWindowID)")
                continue
            }
            guard case let .window(pid, ax) = windowTarget.handle else { continue }

            replaced.insert(windowTarget.id)
            for (tabIndex, title) in rw.tabTitles.enumerated() {
                guard tabIndex < rw.tabURLs.count, !title.isEmpty else { continue }
                let url = rw.tabURLs[tabIndex]
                let id = TargetID.tab(bundleID: Self.bundleID, url: url)
                let (bytes, appNameLen, mask) = TargetBuilder.makeHaystack(appName: windowTarget.appName, title: title)
                tabTargets.append(Target(
                    id: id, kind: .tab, appName: windowTarget.appName, bundleID: Self.bundleID, title: title,
                    haystack: bytes, appNameLength: appNameLen, wordStartMask: mask,
                    letterMask: TargetBuilder.letterMask(bytes),
                    lastFocusedAt: MRUStore.shared.lastFocusedAt(bundleID: Self.bundleID, title: title),
                    icon: windowTarget.icon,
                    stale: false,
                    handle: .tab(pid: pid, ax: ax, windowIndex: rw.chromeWindowID, tabIndex: tabIndex + 1)
                ))
            }
        }
        return MergeResult(tabTargets: tabTargets, replacedWindowIDs: replaced)
    }

    // MARK: - AppleEvent descriptor parsing

    private func intList(_ d: NSAppleEventDescriptor?) -> [Int]? {
        guard let d else { return [] }
        let n = d.numberOfItems
        guard n > 0 else { return [] }
        var out: [Int] = []
        out.reserveCapacity(n)
        for i in 1...n {
            if let v = d.atIndex(i)?.int32Value { out.append(Int(v)) }
        }
        return out
    }

    private func nestedStringList(_ d: NSAppleEventDescriptor?) -> [[String]] {
        guard let d else { return [] }
        let n = d.numberOfItems
        guard n > 0 else { return [] }
        var out: [[String]] = []
        out.reserveCapacity(n)
        for i in 1...n {
            guard let sub = d.atIndex(i) else { out.append([]); continue }
            let subCount = sub.numberOfItems
            if subCount > 0 {
                var inner: [String] = []
                inner.reserveCapacity(subCount)
                for j in 1...subCount {
                    if let s = sub.atIndex(j)?.stringValue { inner.append(s) }
                }
                out.append(inner)
            } else if let s = sub.stringValue {
                out.append([s])
            } else {
                out.append([])
            }
        }
        return out
    }
}
