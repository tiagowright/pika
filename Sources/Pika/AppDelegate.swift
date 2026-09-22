import AppKit
import ApplicationServices
import ServiceManagement
import os

private let log = Logger(subsystem: "io.github.tiagowright.pika", category: "launch")

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotKeyManager = HotKeyManager()
    private var activityToken: NSObjectProtocol?
    private var permissionCheckTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon, no menu bar — LSUIElement equivalent (TECHNICAL.md §3)
        disableAppNap()
        registerAsLoginItem()

        if AXIsProcessTrusted() {
            startEverything()
        } else {
            promptForAccessibilityAndWait()
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

    private func promptForAccessibilityAndWait() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else { return }
            if AXIsProcessTrusted() {
                timer.invalidate()
                self.permissionCheckTimer = nil
                self.startEverything()
            }
        }
    }

    private func startEverything() {
        let config = Config.loadOrCreateDefault()
        PanelController.shared.prewarm()
        hotKeyManager.onPressed = { PanelController.shared.toggle() }
        hotKeyManager.register(keyCode: config.hotkeyKeyCode, modifiers: config.hotkeyModifiers)
    }
}
