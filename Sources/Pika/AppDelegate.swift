import AppKit
import ApplicationServices
import os

private let log = Logger(subsystem: "io.github.tiagowright.pika", category: "launch")

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotKeyManager = HotKeyManager()
    private var activityToken: NSObjectProtocol?
    private var statusItem: StatusItemController?
    private var started = false
    private lazy var settingsModel: SettingsModel = {
        let model = SettingsModel(hotKey: hotKeyManager)
        model.runSetupAgain = { [weak self] in self?.onboarding.show() }
        return model
    }()
    private lazy var settings = SettingsWindowController(model: settingsModel)
    private lazy var onboarding = OnboardingWindowController(model: settingsModel)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // no Dock icon, no menu bar — LSUIElement equivalent (TECHNICAL.md §3)
        NSApp.mainMenu = Self.makeMainMenu()
        disableAppNap()
        // Launch at login is never registered silently: only from
        // onboarding or Settings (SETTINGS.md §2.4.6).

        // Neither needs Accessibility, and onboarding runs before it's granted.
        ConfigStore.shared.startWatching()
        Appearance.shared.start()

        // Before the Accessibility check: the menu is how a user who hasn't
        // granted it yet finds out, and how they quit.
        statusItem = StatusItemController(hotKey: hotKeyManager) { [weak self] pane in self?.openSettings(pane) }
        PanelController.shared.onOpenSettings = { [weak self] in self?.openSettings(nil) }

        let permissions = PermissionCenter.shared
        permissions.observe { [weak self] in
            if permissions.accessibility { self?.startEverything() }
        }
        permissions.start()

        if permissions.accessibility { startEverything() }

        // No system prompt at launch: onboarding explains first, and its
        // Accessibility row asks. PermissionCenter polls until the grant
        // lands, then startEverything runs.
        if Onboarding.isDue { onboarding.show() }
    }

    /// Opening Pika.app again while it's running — from Finder, Spotlight,
    /// or Raycast — opens Settings. With no Dock icon, and a menu bar icon
    /// the notch can hide, it's the way in that always works (SETTINGS.md
    /// §1.2 E2).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if onboarding.isOpen { onboarding.show(resetting: false) } else { openSettings(nil) }
        return false
    }

    /// Visible only while Setup or Settings is open (AppPresence); its key
    /// equivalents work in Pika's windows either way: ⌘W closes, ⌘C copies
    /// the troubleshooting command. Quit has no ⌘Q: quitting by reflex to
    /// dismiss a window would silently kill the hotkey.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = menu
            main.addItem(item)
        }
        submenu("Pika", [
            NSMenuItem(title: "Hide Pika", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"),
            .separator(),
            NSMenuItem(title: "Quit Pika", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""),
        ])
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

    /// On onboarding's last page, pressing the hotkey is the lesson: it
    /// finishes setup and shows the real switcher.
    private func hotkeyPressed() {
        if onboarding.isWaitingForHotkey {
            onboarding.finish()
            PanelController.shared.show()
            return
        }
        PanelController.shared.toggle()
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
        PanelController.shared.prewarm()
        hotKeyManager.onPressed = { [weak self] in self?.hotkeyPressed() }
        hotKeyManager.register(keyCode: store.config.hotkeyKeyCode, modifiers: store.config.hotkeyModifiers)
        statusItem?.refresh()
        settingsModel.sync() // the hotkey row flips from "waiting" to working
        store.observe { [weak self] old, new in
            guard new.hotkeyKeyCode != old.hotkeyKeyCode || new.hotkeyModifiers != old.hotkeyModifiers else { return }
            self?.hotKeyManager.register(keyCode: new.hotkeyKeyCode, modifiers: new.hotkeyModifiers)
            self?.statusItem?.refresh()
        }
    }
}
