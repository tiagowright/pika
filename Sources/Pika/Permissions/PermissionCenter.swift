import AppKit
import ApplicationServices
import CoreServices
import ServiceManagement
import os

private let log = Logger(subsystem: "io.github.tiagowright.pika", category: "permissions")

/// A macOS privacy decision about Pika.
enum Grant: String, Codable {
    case granted, denied, notAsked
}

/// Automation → Google Chrome. Chrome has to be running to be asked or
/// checked, so the not-running cases carry the last answer seen.
enum ChromeAccess: Equatable {
    case granted
    case denied
    case notAsked
    case chromeNotRunning(lastKnown: Grant?)
    case chromeNotInstalled

    /// The best answer available, whether or not Chrome is running.
    var grant: Grant? {
        switch self {
        case .granted: return .granted
        case .denied: return .denied
        case .notAsked: return .notAsked
        case .chromeNotRunning(let lastKnown): return lastKnown
        case .chromeNotInstalled: return nil
        }
    }
}

enum LoginItemState: Equatable {
    case on, off
    case needsApproval   // registered, but switched off in System Settings → Login Items
    case unavailable     // not running from a stable app bundle (e.g. `swift run`)
}

/// Live, never-guessed state for everything Pika needs from macOS
/// (SETTINGS.md §2.1, §2.3.1). The menu bar item, and later the settings
/// window and onboarding, all read from here.
///
/// It re-checks when there's reason to think something changed: at start,
/// when the user comes back from System Settings, when Chrome launches or
/// quits, when the menu opens, and every second while Accessibility is
/// still missing. Nothing polls once everything is granted.
///
/// Main thread only, except where noted.
final class PermissionCenter {
    static let shared = PermissionCenter()

    static let chromeBundleID = ChromeTabSource.bundleID

    private(set) var accessibility = AXIsProcessTrusted()
    private(set) var chrome: ChromeAccess = .chromeNotInstalled
    private(set) var loginItem: LoginItemState = .unavailable

    private var observers: [() -> Void] = []
    private var accessibilityTimer: Timer?
    private var chromeCheckInFlight = false
    private let queue = DispatchQueue(label: "pika.permissions")

    private init() {
        chrome = .chromeNotRunning(lastKnown: StateStore.shared.state.chromeAutomation)
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appActivated(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(chromeLaunchedOrQuit(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(chromeLaunchedOrQuit(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        refresh()
    }

    /// Called whenever any permission changes.
    func observe(_ handler: @escaping () -> Void) {
        observers.append(handler)
    }

    func refresh() {
        let before = (accessibility, chrome, loginItem)
        accessibility = AXIsProcessTrusted()
        loginItem = Self.currentLoginItemState()
        updateAccessibilityPolling()
        checkChrome()
        if before != (accessibility, chrome, loginItem) { notify() }
    }

    // MARK: - Chrome

    /// Shows Apple's Automation prompt if Chrome hasn't been asked yet.
    /// Chrome must be running. Blocks a background queue until the user
    /// answers, then reports on the main thread.
    func requestChromeAccess(completion: ((ChromeAccess) -> Void)? = nil) {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: Self.chromeBundleID).first != nil else {
            completion?(chrome)
            return
        }
        queue.async {
            let status = Self.automationStatus(askUserIfNeeded: true)
            DispatchQueue.main.async {
                self.applyChromeStatus(status)
                completion?(self.chrome)
            }
        }
    }

    /// ChromeTabSource saw -1743 from a real Apple Event: definitive.
    func noteChromeDenied() {
        applyChromeStatus(OSStatus(errAEEventNotPermitted))
    }

    private func checkChrome() {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.chromeBundleID) != nil else {
            setChrome(.chromeNotInstalled)
            return
        }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: Self.chromeBundleID).first != nil else {
            setChrome(.chromeNotRunning(lastKnown: StateStore.shared.state.chromeAutomation))
            return
        }
        guard !chromeCheckInFlight else { return }
        chromeCheckInFlight = true
        // Tens of ms on first call (an IPC to tccd), so off the main thread.
        queue.async {
            let status = Self.automationStatus(askUserIfNeeded: false)
            DispatchQueue.main.async {
                self.chromeCheckInFlight = false
                self.applyChromeStatus(status)
            }
        }
    }

    private func applyChromeStatus(_ status: OSStatus) {
        let access: ChromeAccess
        switch status {
        case noErr: access = .granted
        case OSStatus(errAEEventNotPermitted): access = .denied
        case OSStatus(errAEEventWouldRequireUserConsent): access = .notAsked
        case OSStatus(procNotFound): access = .chromeNotRunning(lastKnown: StateStore.shared.state.chromeAutomation)
        default:
            log.error("AEDeterminePermissionToAutomateTarget(Chrome) returned \(status)")
            return
        }
        switch access {
        case .granted: StateStore.shared.update { $0.chromeAutomation = .granted }
        case .denied: StateStore.shared.update { $0.chromeAutomation = .denied }
        case .notAsked: StateStore.shared.update { $0.chromeAutomation = .notAsked }
        case .chromeNotRunning, .chromeNotInstalled: break
        }
        setChrome(access)
    }

    private func setChrome(_ access: ChromeAccess) {
        guard access != chrome else { return }
        let wasGranted = chrome == .granted
        chrome = access
        if access == .granted, !wasGranted {
            ChromeTabSource.shared.permissionGranted()
        }
        notify()
    }

    /// Safe from any thread.
    private static func automationStatus(askUserIfNeeded: Bool) -> OSStatus {
        var target = AEAddressDesc()
        let bundleID = Array(chromeBundleID.utf8)
        guard AECreateDesc(DescType(typeApplicationBundleID), bundleID, bundleID.count, &target) == noErr else {
            return OSStatus(paramErr)
        }
        defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(&target, AEEventClass(typeWildCard), AEEventID(typeWildCard), askUserIfNeeded)
    }

    // MARK: - Accessibility

    /// There's no notification for an Accessibility grant, so poll — but
    /// only while it's missing, and only once a second (AXIsProcessTrusted
    /// is a cheap local check).
    private func updateAccessibilityPolling() {
        if accessibility {
            accessibilityTimer?.invalidate()
            accessibilityTimer = nil
        } else if accessibilityTimer == nil {
            accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self, AXIsProcessTrusted() else { return }
                self.refresh()
            }
        }
    }

    // MARK: - Login item

    private static func currentLoginItemState() -> LoginItemState {
        switch SMAppService.mainApp.status {
        case .enabled: return .on
        case .notRegistered: return .off
        case .requiresApproval: return .needsApproval
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }

    // MARK: - Triggers

    /// True while System Settings is the active app, so that leaving it —
    /// when a grant most likely just changed — triggers a refresh.
    private var inSystemSettings = false

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if app.bundleIdentifier == "com.apple.systempreferences" {
            inSystemSettings = true
        } else if inSystemSettings {
            inSystemSettings = false
            refresh()
        }
    }

    @objc private func chromeLaunchedOrQuit(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == Self.chromeBundleID else { return }
        // A just-launched Chrome may not answer yet; give it a moment.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.refresh() }
    }

    private func notify() {
        observers.forEach { $0() }
    }
}
