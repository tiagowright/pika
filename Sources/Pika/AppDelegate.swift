import AppKit
import ApplicationServices
import os

private let log = Logger(subsystem: "io.github.tiagowright.pika", category: "launch")

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotKeyManager = HotKeyManager()
    private var activityToken: NSObjectProtocol?
    private var statusItem: StatusItemController?
    private var started = false
    private lazy var settings = SettingsWindowController(hotKey: hotKeyManager)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon, no menu bar — LSUIElement equivalent (TECHNICAL.md §3)
        NSApp.mainMenu = Self.makeMainMenu()
        disableAppNap()
        // Launch at login is no longer registered silently here: only from
        // Settings (and, in step 6, onboarding) — SETTINGS.md §2.4.6.

        // Before the Accessibility check: the menu is how a user who hasn't
        // granted it yet finds out, and how they quit.
        statusItem = StatusItemController(hotKey: hotKeyManager) { [weak self] pane in self?.openSettings(pane) }
        PanelController.shared.onOpenSettings = { [weak self] in self?.openSettings(nil) }

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

    /// Opening Pika.app again while it's running — from Finder, Spotlight,
    /// or Raycast — opens Settings. With no Dock icon, and a menu bar icon
    /// the notch can hide, it's the way in that always works (SETTINGS.md
    /// §1.2 E2).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings(nil)
        return false
    }

    /// Never shown (Pika is an accessory app), but its key equivalents
    /// still work in Pika's windows: ⌘W closes Settings, ⌘C copies the
    /// troubleshooting command. No ⌘Q: quitting Pika by reflex would
    /// silently kill the hotkey; Quit lives in the menu bar item.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = menu
            main.addItem(item)
        }
        submenu("Pika", [])
        submenu("File", [NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")])
        submenu("Edit", [
            NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
            NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
            NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
            NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
        ])
        submenu("Window", [NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")])
        return main
    }

    private func openSettings(_ pane: SettingsModel.Pane?) {
        settings.show(pane)
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
