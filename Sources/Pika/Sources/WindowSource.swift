import AppKit
import ApplicationServices
import CoreGraphics

/// The primary window/title source. Uses the Accessibility API — never
/// `kCGWindowName`, which is empty without Screen Recording permission
/// (TECHNICAL.md §0) — supplemented by CGWindowList for z-order and
/// on-screen filtering. Event-driven: AXObservers + NSWorkspace
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

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            setup(app: app)
        }
        rebuildNow()
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

    /// One structural sweep. Fans out one AX call sequence per app onto
    /// that app's own serial queue (so a hung app only stalls its own
    /// rows), gated by the 150ms messaging timeout, joined with a
    /// DispatchGroup and an overall wait cap.
    func rebuildNow() {
        stateLock.lock()
        let currentApps = Array(apps.values)
        stateLock.unlock()

        let onScreenIDs = onScreenWindowIDs()
        let group = DispatchGroup()
        let resultsLock = NSLock()
        var allTargets: [Target] = []

        for entry in currentApps {
            group.enter()
            entry.queue.async {
                let targets = self.windows(for: entry, onScreenIDs: onScreenIDs)
                resultsLock.lock(); allTargets.append(contentsOf: targets); resultsLock.unlock()
                group.leave()
            }
        }
        _ = group.wait(timeout: .now() + 2.0) // hard cap; slow apps simply miss this round

        lastBaseTargets = allTargets
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

    private func onScreenWindowIDs() -> Set<CGWindowID> {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var ids = Set<CGWindowID>()
        for w in list {
            guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
                  let num = w[kCGWindowNumber as String] as? CGWindowID else { continue }
            ids.insert(num)
        }
        return ids
    }

    private func windows(for entry: AppEntry, onScreenIDs: Set<CGWindowID>) -> [Target] {
        var winsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(entry.axApp, kAXWindowsAttribute as CFString, &winsRef) == .success,
              let wins = winsRef as? [AXUIElement], !wins.isEmpty else { return [] }

        let appName = NSRunningApplication(processIdentifier: entry.pid)?.localizedName ?? entry.bundleID
        let isGhostty = entry.bundleID == GhosttyTitle.bundleID

        var rawTitles: [String] = []
        var windows: [(ax: AXUIElement, title: String, cgID: CGWindowID?)] = []

        for win in wins {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleRef)
            let rawTitle = (titleRef as? String) ?? ""
            var minimizedRef: CFTypeRef?
            AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute as CFString, &minimizedRef)
            let minimized = (minimizedRef as? Bool) ?? false
            let cgID = axWindowID(win)
            // Keep minimized windows (they're still "open"); drop windows
            // CGWindowList can't see at all and that AX also can't ID —
            // usually helper/panel windows, not real targets.
            if !minimized, let cgID, !onScreenIDs.contains(cgID) { continue }
            if rawTitle.isEmpty { continue }

            let title = isGhostty ? GhosttyTitle.clean(title: rawTitle, window: win) : rawTitle
            rawTitles.append(title)
            windows.append((win, title, cgID))
        }

        let finalTitles = isGhostty ? GhosttyTitle.disambiguate(rawTitles) : rawTitles

        return zip(windows, finalTitles).map { pair, title in
            let (win, _, cgID) = pair
            let id = TargetID.window(bundleID: entry.bundleID, cgWindowID: cgID, fallbackTitle: title)
            let (bytes, appNameLen, mask) = TargetBuilder.makeHaystack(appName: appName, title: title)
            let recency = max(
                MRUStore.shared.lastFocusedAt(bundleID: entry.bundleID, title: title),
                0
            )
            return Target(
                id: id, kind: .window, appName: appName, bundleID: entry.bundleID, title: title,
                haystack: bytes, appNameLength: appNameLen, wordStartMask: mask,
                letterMask: TargetBuilder.letterMask(bytes),
                lastFocusedAt: recency,
                icon: IconCache.shared.icon(forBundleID: entry.bundleID),
                stale: false,
                handle: .window(pid: entry.pid, ax: win)
            )
        }
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
    static let bundleID = Bundle.main.bundleIdentifier ?? "dev.pika"
}
