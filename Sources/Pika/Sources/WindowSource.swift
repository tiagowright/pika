import AppKit
import ApplicationServices
import CoreGraphics

/// The primary window/title source. Uses the Accessibility API — never
/// `kCGWindowName`, which is empty without Screen Recording permission
/// (TECHNICAL.md §0) — supplemented by CGWindowList for z-order and
/// junk-window filtering across all Spaces. Event-driven: AXObservers + NSWorkspace
/// notifications keep the index correct without polling, plus a
/// debounced safety-net sweep since AX notifications aren't perfectly
/// reliable (TECHNICAL.md §5a).
final class WindowSource {
    static let shared = WindowSource()

    /// One retained AXUIElement + one serial queue per running app.
    /// Retaining the element is the single biggest AX latency win
    /// (TECHNICAL.md §5a): creating it fresh per query cost ~136ms for
    /// 16 apps in testing, almost all connection setup.
    private final class AppEntry {
        let pid: pid_t
        let bundleID: String
        let axApp: AXUIElement
        let queue: DispatchQueue
        var observer: AXObserver?
        init(pid: pid_t, bundleID: String) {
            self.pid = pid
            self.bundleID = bundleID
            self.axApp = AXUIElementCreateApplication(pid)
            self.queue = DispatchQueue(label: "pika.ax.\(pid)")
            AXUIElementSetMessagingTimeout(axApp, 0.15) // never let one hung app block a sweep
        }
    }

    private var apps: [pid_t: AppEntry] = [:]
    private let stateLock = NSLock()
    private let rebuildQueue = DispatchQueue(label: "pika.windowsource.rebuild")
    private var rebuildScheduled = false

    /// Last structural sweep, *before* Chrome tab merging — cached so a
    /// Chrome-tab-only refresh doesn't require a full AX resweep
    /// (TECHNICAL.md §5c).
    private var lastBaseTargets: [Target] = []

    /// Identity of the frontmost window, so the query layer can exclude
    /// it from the empty-query MRU list per UX.md's decision.
    private(set) var currentFrontmostID: TargetID?

    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(appLaunched(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(appTerminated(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(appActivated(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        // Arriving on a Space is the only moment AX will tell us about
        // that Space's windows, so it's the one event we can't afford to
        // miss — it's how a never-yet-visited Space enters the cache.
        nc.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            setup(app: app)
        }
        rebuildQueue.async { [weak self] in self?.rebuildNow() } // cache is rebuildQueue-owned
        scheduleSafetyNet()
    }

    private func scheduleSafetyNet() {
        rebuildQueue.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.rebuildNow()
            self?.scheduleSafetyNet()
        }
    }

    // MARK: - App lifecycle

    @objc private func appLaunched(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.activationPolicy == .regular else { return }
        setup(app: app)
        scheduleRebuild()
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        teardown(pid: app.processIdentifier)
        scheduleRebuild()
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier else { return }
        // Cheap recency bump now; a structural rebuild (if titles moved
        // around) will follow via the focused-window AX notification.
        if bundleID == PikaApp.bundleID { return }
        touchFrontmostWindow(pid: app.processIdentifier, bundleID: bundleID)
        if bundleID == ChromeTabSource.bundleID {
            ChromeTabSource.shared.scheduleRefresh(tier: .focusedWindow)
        }
    }

    @objc private func spaceChanged() {
        scheduleRebuild()
    }

    private func setup(app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier, bundleID != PikaApp.bundleID else { return }
        let pid = app.processIdentifier
        stateLock.lock()
        guard apps[pid] == nil else { stateLock.unlock(); return }
        let entry = AppEntry(pid: pid, bundleID: bundleID)
        apps[pid] = entry
        stateLock.unlock()

        entry.queue.async { [weak self] in
            self?.installObserver(entry)
        }
    }

    private func teardown(pid: pid_t) {
        stateLock.lock()
        let entry = apps.removeValue(forKey: pid)
        stateLock.unlock()
        if let observer = entry?.observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
    }

    private func installObserver(_ entry: AppEntry) {
        var observerRef: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            Unmanaged<WindowSource>.fromOpaque(refcon).takeUnretainedValue().scheduleRebuild()
        }
        guard AXObserverCreate(entry.pid, callback, &observerRef) == .success, let observer = observerRef else { return }
        entry.observer = observer
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXWindowCreatedNotification, kAXUIElementDestroyedNotification,
                     kAXFocusedWindowChangedNotification, kAXTitleChangedNotification,
                     kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification] {
            AXObserverAddNotification(observer, entry.axApp, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    private func touchFrontmostWindow(pid: pid_t, bundleID: String) {
        // Resolve to a concrete window id off the AX queue, then patch recency.
        stateLock.lock(); let entry = apps[pid]; stateLock.unlock()
        guard let entry else { return }
        entry.queue.async { [weak self] in
            guard let self else { return }
            var winRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(entry.axApp, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
                  let winRef else { return }
            let winElement = winRef as! AXUIElement
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(winElement, kAXTitleAttribute as CFString, &titleRef)
            let title = (titleRef as? String) ?? ""
            let cgID = axWindowID(winElement)
            let id = TargetID.window(bundleID: bundleID, cgWindowID: cgID, fallbackTitle: title)
            let now = Date().timeIntervalSince1970
            MRUStore.shared.touch(id: id, title: title, at: now)
            IndexStore.shared.bumpRecency(id, to: now)
            DispatchQueue.main.async { self.currentFrontmostID = id }
        }
    }

    // MARK: - Rebuild

    func scheduleRebuild() {
        stateLock.lock()
        if rebuildScheduled { stateLock.unlock(); return }
        rebuildScheduled = true
        stateLock.unlock()
        rebuildQueue.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.stateLock.lock(); self?.rebuildScheduled = false; self?.stateLock.unlock()
            self?.rebuildNow()
        }
    }

    /// A window Pika has seen at least once through AX, remembered
    /// across sweeps.
    ///
    /// This cache is the whole answer to Spaces. AX window enumeration
    /// is **Space-scoped**: `kAXWindows` returns only the windows on the
    /// Space you are currently looking at — and returns them with
    /// `AXError.success`, so "you're on another Space" is
    /// indistinguishable from "this app has no windows". Measured from
    /// an empty Space: all 14 running apps reported success with zero
    /// windows, which is exactly how the index ended up empty.
    ///
    /// CGWindowList has the opposite property — it lists every window on
    /// every Space, but its titles need Screen Recording permission,
    /// which TECHNICAL.md §0 deliberately avoids. So the two are split
    /// by what each is actually good for: **CG says which windows
    /// exist, AX says what they are called**, and this cache is what
    /// lets those two facts be observed at different times.
    private struct CachedWindow {
        let cgID: CGWindowID
        let pid: pid_t
        let bundleID: String
        var appName: String
        /// Cleaned but *not* disambiguated. The " · N" suffixes are
        /// applied at build time over the whole cached set, so they stay
        /// consistent even on a sweep that only observed some windows.
        var title: String
        var ax: AXUIElement
        var minimized: Bool
    }

    /// What one AX sweep saw for one app. Deliberately not a `Target`:
    /// targets are built later, from the cache, so that windows nobody
    /// could see this round still make the list.
    private struct Observation {
        let cgID: CGWindowID?
        let ax: AXUIElement
        let title: String
        let minimized: Bool
    }

    private var windowCache: [CGWindowID: CachedWindow] = [:]

    /// One structural sweep. Fans out one AX call sequence per app onto
    /// that app's own serial queue (so a hung app only stalls its own
    /// rows), gated by the 150ms messaging timeout, joined with a
    /// DispatchGroup and an overall wait cap.
    func rebuildNow() {
        stateLock.lock()
        let currentApps = Array(apps.values)
        stateLock.unlock()

        let liveIDs = liveWindowIDs()
        let group = DispatchGroup()
        let resultsLock = NSLock()
        var observed: [(entry: AppEntry, windows: [Observation])] = []

        for entry in currentApps {
            group.enter()
            entry.queue.async {
                let windows = self.observe(entry)
                resultsLock.lock(); observed.append((entry, windows)); resultsLock.unlock()
                group.leave()
            }
        }
        _ = group.wait(timeout: .now() + 2.0) // hard cap; slow apps simply miss this round

        let targets = mergeIntoCache(observed: observed, liveIDs: liveIDs, apps: currentApps)

        lastBaseTargets = targets
        publish()
        warmIconsIfNeeded(for: currentApps)
    }

    /// Re-applies the last Chrome tab merge on top of the last base
    /// sweep, without touching AX again. Called by ChromeTabSource after
    /// it refreshes (TECHNICAL.md §5c).
    func applyChromeMerge() {
        publish()
    }

    private func publish() {
        var final = lastBaseTargets
        if let merge = ChromeTabSource.shared.merge(chromeWindows: final.filter { $0.bundleID == ChromeTabSource.bundleID && $0.kind == .window }) {
            final.removeAll { merge.replacedWindowIDs.contains($0.id) }
            final.append(contentsOf: merge.tabTargets)
        }
        IndexStore.shared.replace(final)
    }

    /// Every real window on every Space, by CGWindowID — the existence
    /// half of the split described on `CachedWindow`. Not
    /// `.optionOnScreenOnly`, which would narrow this to the current
    /// Space and defeat the entire point.
    private func liveWindowIDs() -> Set<CGWindowID> {
        guard let list = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var ids = Set<CGWindowID>()
        for w in list {
            guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
                  let num = w[kCGWindowNumber as String] as? CGWindowID else { continue }
            // Zero-size junk: the on-screen option used to filter this
            // out for free, so it has to be done explicitly now.
            if let bounds = w[kCGWindowBounds as String] as? [String: Any],
               let width = bounds["Width"] as? Double, let height = bounds["Height"] as? Double,
               width < 2 || height < 2 { continue }
            ids.insert(num)
        }
        return ids
    }

    /// One app's AX windows, as raw observations. An empty result is
    /// *not* evidence the app has no windows — see `CachedWindow`.
    private func observe(_ entry: AppEntry) -> [Observation] {
        var winsRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(entry.axApp, kAXWindowsAttribute as CFString, &winsRef)
        guard err == .success, let wins = winsRef as? [AXUIElement], !wins.isEmpty else { return [] }

        let isGhostty = entry.bundleID == GhosttyTitle.bundleID
        var result: [Observation] = []

        for win in wins {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleRef)
            let rawTitle = (titleRef as? String) ?? ""
            if rawTitle.isEmpty { continue }
            var minimizedRef: CFTypeRef?
            AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute as CFString, &minimizedRef)
            let minimized = (minimizedRef as? Bool) ?? false

            // Same cap as the app element: a cached window gets probed
            // for liveness later, and that probe must not hang a sweep.
            AXUIElementSetMessagingTimeout(win, 0.15)

            let title = isGhostty ? GhosttyTitle.clean(title: rawTitle, window: win) : rawTitle
            result.append(Observation(cgID: axWindowID(win), ax: win, title: title, minimized: minimized))
        }
        return result
    }

    /// Folds this sweep's observations into the cache, evicts what no
    /// longer exists, and builds the target list from what survives.
    private func mergeIntoCache(
        observed: [(entry: AppEntry, windows: [Observation])],
        liveIDs: Set<CGWindowID>,
        apps: [AppEntry]
    ) -> [Target] {
        var appNames: [pid_t: String] = [:]
        for entry in apps {
            appNames[entry.pid] = NSRunningApplication(processIdentifier: entry.pid)?.localizedName ?? entry.bundleID
        }

        // Observed wins over cached: refresh title, minimized state and
        // the AX handle for everything we could actually see.
        var seenThisSweep = Set<CGWindowID>()
        var uncacheable: [(entry: AppEntry, obs: Observation)] = []
        for (entry, windows) in observed {
            let appName = appNames[entry.pid] ?? entry.bundleID
            for obs in windows {
                guard let cgID = obs.cgID else {
                    // No CGWindowID means nothing can vouch for this
                    // window's existence later, so it is never cached —
                    // it lives exactly as long as AX keeps reporting it.
                    uncacheable.append((entry, obs))
                    continue
                }
                seenThisSweep.insert(cgID)
                windowCache[cgID] = CachedWindow(
                    cgID: cgID, pid: entry.pid, bundleID: entry.bundleID, appName: appName,
                    title: obs.title, ax: obs.ax, minimized: obs.minimized
                )
            }
        }

        // Eviction. A window survives if CG still lists it (authoritative
        // across all Spaces) or if AX just saw it. Minimized windows are
        // the awkward case: they can drop out of the CG list entirely, so
        // they get an explicit liveness probe rather than a guess.
        let livePIDs = Set(apps.map(\.pid))
        for (cgID, cached) in windowCache {
            if !livePIDs.contains(cached.pid) { windowCache[cgID] = nil; continue }
            if seenThisSweep.contains(cgID) || liveIDs.contains(cgID) { continue }
            if cached.minimized, isStillAlive(cached.ax) { continue }
            windowCache[cgID] = nil
        }

        var rows: [(bundleID: String, appName: String, title: String, id: TargetID, pid: pid_t, ax: AXUIElement)] = []
        // Observed-first ordering keeps Ghostty's " · N" suffixes stable
        // and close to stacking order; the rest sort by id so the
        // numbering never reshuffles between sweeps.
        let ordered = windowCache.values.sorted {
            let aSeen = seenThisSweep.contains($0.cgID), bSeen = seenThisSweep.contains($1.cgID)
            return aSeen == bSeen ? $0.cgID < $1.cgID : aSeen
        }
        for cached in ordered {
            rows.append((cached.bundleID, cached.appName, cached.title,
                         TargetID.window(bundleID: cached.bundleID, cgWindowID: cached.cgID, fallbackTitle: cached.title),
                         cached.pid, cached.ax))
        }
        for (entry, obs) in uncacheable {
            rows.append((entry.bundleID, appNames[entry.pid] ?? entry.bundleID, obs.title,
                         TargetID.window(bundleID: entry.bundleID, cgWindowID: nil, fallbackTitle: obs.title),
                         entry.pid, obs.ax))
        }

        // Ghostty disambiguation needs the full sibling set, so it runs
        // here rather than per-app inside the sweep.
        var titles = rows.map(\.title)
        let ghosttyIndices = rows.indices.filter { rows[$0].bundleID == GhosttyTitle.bundleID }
        if !ghosttyIndices.isEmpty {
            let disambiguated = GhosttyTitle.disambiguate(ghosttyIndices.map { titles[$0] })
            for (slot, index) in ghosttyIndices.enumerated() { titles[index] = disambiguated[slot] }
        }

        return zip(rows, titles).map { row, title in
            let (bytes, appNameLen, mask) = TargetBuilder.makeHaystack(appName: row.appName, title: title)
            return Target(
                id: row.id, kind: .window, appName: row.appName, bundleID: row.bundleID, title: title,
                haystack: bytes, appNameLength: appNameLen, wordStartMask: mask,
                letterMask: TargetBuilder.letterMask(bytes),
                lastFocusedAt: max(MRUStore.shared.lastFocusedAt(bundleID: row.bundleID, title: title), 0),
                icon: IconCache.shared.icon(forBundleID: row.bundleID),
                stale: false,
                handle: .window(pid: row.pid, ax: row.ax)
            )
        }
    }

    /// Cheapest question AX will answer about a window element. A
    /// destroyed window reports `.invalidUIElement`; anything else
    /// (including a timeout) is treated as still alive, because an
    /// unresponsive app is not evidence its windows are gone.
    private func isStillAlive(_ window: AXUIElement) -> Bool {
        var roleRef: CFTypeRef?
        return AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &roleRef) != .invalidUIElement
    }

    private func warmIconsIfNeeded(for apps: [AppEntry]) {
        for entry in apps {
            if IconCache.shared.icon(forBundleID: entry.bundleID) != nil { continue }
            let sourceIcon = NSRunningApplication(processIdentifier: entry.pid)?.icon
            IconCache.shared.warm(bundleID: entry.bundleID, sourceIcon: sourceIcon) { image in
                IndexStore.shared.updateIcon(bundleID: entry.bundleID, icon: NSImageBox(image: image))
                PanelController.shared.refreshIfVisible()
            }
        }
    }
}

enum PikaApp {
    static let bundleID = Bundle.main.bundleIdentifier ?? "io.github.tiagowright.pika"
}
