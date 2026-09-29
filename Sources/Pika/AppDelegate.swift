import AppKit
import ApplicationServices
import ServiceManagement
import os

private let log = Logger(subsystem: "io.github.tiagowright.pika", category: "launch")

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotKeyManager = HotKeyManager()
    private var activityToken: NSObjectProtocol?
    private var statusItem: StatusItemController?
    private var started = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon, no menu bar — LSUIElement equivalent (TECHNICAL.md §3)
        disableAppNap()
        registerAsLoginItem()
        // Before the Accessibility check: the menu is how a user who hasn't
        // granted it yet finds out, and how they quit.
        statusItem = StatusItemController(hotKey: hotKeyManager)

        let permissions = PermissionCenter.shared
        permissions.observe { [weak self] in
            if permissions.accessibility { self?.startEverything() }
        }
        permissions.start()

        if permissions.accessibility {
            startEverything()
        } else {
            // Shows the system prompt the first time only. PermissionCenter
            // polls until the grant lands, then startEverything runs.
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
    }

    /// A resident agent that sits idle gets throttled by App Nap, and the
    /// *first* hotkey press after a quiet period would visibly lag —
    /// exactly the "fast except the first time" bug called out in
    /// TECHNICAL.md §3. Held for the process lifetime.
    private func disableAppNap() {
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "Instant window switching"
        )
    }

    /// Registers Pika.app to launch at login via `SMAppService` (macOS
    /// 13+) — no separate LaunchAgent plist to maintain. Idempotent: safe
    /// to call on every launch, since it's a no-op once already
    /// registered. Requires Pika to be running from a stable path (see
    /// build.sh, which installs to /Applications) — SMAppService ties
    /// the registration to the bundle's location.
    private func registerAsLoginItem() {
        let service = SMAppService.mainApp
        guard service.status != .enabled else { return }
        do {
            try service.register()
            log.info("Registered as a login item")
        } catch {
            log.error("Failed to register as a login item: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Runs once, the first time Accessibility is known to be granted.
    private func startEverything() {
        guard !started else { return }
        started = true
        let store = ConfigStore.shared
        store.startWatching()
        Appearance.shared.start()
        PanelController.shared.prewarm()
        hotKeyManager.onPressed = { PanelController.shared.toggle() }
        hotKeyManager.register(keyCode: store.config.hotkeyKeyCode, modifiers: store.config.hotkeyModifiers)
        statusItem?.refresh()
        store.observe { [weak self] old, new in
            guard new.hotkeyKeyCode != old.hotkeyKeyCode || new.hotkeyModifiers != old.hotkeyModifiers else { return }
            self?.hotKeyManager.register(keyCode: new.hotkeyKeyCode, modifiers: new.hotkeyModifiers)
            self?.statusItem?.refresh()
        }
    }
}
