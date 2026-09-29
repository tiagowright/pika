import AppKit
import ApplicationServices
import os

private let log = Logger(subsystem: "io.github.tiagowright.pika", category: "menu")

/// The menu bar item: Pika's only visible presence, and the way back to
/// everything that isn't the switcher (SETTINGS.md §1.5). It badges
/// itself whenever something needs the user — a missing permission, a
/// hotkey that won't fire, a broken config line — and the menu says what
/// and offers the fix.
///
/// Main thread only.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let hotKey: HotKeyManager
    private var isBadged: Bool?

    private struct Problem {
        let title: String       // the fix, as a menu command
        let detail: String      // what's wrong
        let badges: Bool
        let perform: () -> Void
    }

    init(hotKey: HotKeyManager) {
        self.hotKey = hotKey
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        ConfigStore.shared.observeIssues { [weak self] _ in self?.refresh() }
        ConfigStore.shared.observe { [weak self] _, _ in self?.refresh() }
        PermissionCenter.shared.observe { [weak self] in self?.refresh() }
        refresh()
    }

    /// Re-checks every problem and updates the badge. Call when anything
    /// the problems depend on may have changed.
    func refresh() {
        let badged = problems().contains { $0.badges }
        guard badged != isBadged else { return }
        isBadged = badged
        item.button?.image = PikaGlyph.menuBarImage(badged: badged)
        item.button?.toolTip = badged ? "Pika needs attention" : "Pika"
    }

    // MARK: - Problems

    private func problems() -> [Problem] {
        var result: [Problem] = []
        let config = ConfigStore.shared.config
        let permissions = PermissionCenter.shared

        if !permissions.accessibility {
            result.append(Problem(
                title: "Grant Accessibility…",
                detail: "Pika can't list or switch windows without it",
                badges: true,
                perform: { Self.openSystemSettings("com.apple.preference.security?Privacy_Accessibility") }
            ))
        }

        switch hotKey.health(for: config) {
        case .takenByApp:
            result.append(Problem(
                title: "Change the hotkey…",
                detail: "\(config.hotkey) is taken by another app, so it does nothing",
                badges: true,
                perform: Self.openConfigFile
            ))
        case .shadowedBySystem(let clash):
            result.append(Problem(
                title: "Open Keyboard Shortcuts…",
                detail: "macOS uses \(config.hotkey) for “\(clash)” and gets it first",
                badges: true,
                perform: { Self.openSystemSettings("com.apple.Keyboard-Settings.extension") }
            ))
        case .ok, .notRegisteredYet:
            break
        }

        // Optional, so a note rather than a badge — but the user did ask
        // for Chrome tabs, so say why they aren't there.
        if config.chromeTabs, permissions.chrome.grant == .denied {
            result.append(Problem(
                title: "Allow Chrome tabs…",
                detail: "Automation for Google Chrome is off, so Chrome is listed by window",
                badges: false,
                perform: { Self.openSystemSettings("com.apple.preference.security?Privacy_Automation") }
            ))
        }

        for issue in ConfigStore.shared.issues.prefix(5) {
            result.append(Problem(
                title: issue.isNotice ? "Tidy config.toml…" : "Fix config.toml…",
                detail: issue.line.map { "line \($0): \(issue.message)" } ?? issue.message,
                badges: !issue.isNotice,
                perform: Self.openConfigFile
            ))
        }
        return result
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        // Permissions can change behind our back; opening the menu is a
        // good moment to look. Chrome's answer arrives asynchronously and
        // refreshes the badge; the open menu shows what's known now.
        PermissionCenter.shared.refresh()
        refresh()
        menu.removeAllItems()

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let header = NSMenuItem(title: version.map { "Pika \($0)" } ?? "Pika (development build)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let problems = problems()
        if !problems.isEmpty {
            menu.addItem(.separator())
            for problem in problems {
                let row = ClosureMenuItem(title: problem.title, action: problem.perform)
                row.subtitle = problem.detail
                row.image = NSImage(systemSymbolName: problem.badges ? "exclamationmark.triangle.fill" : "info.circle",
                                    accessibilityDescription: problem.badges ? "Problem" : "Note")?
                    .withSymbolConfiguration(.init(paletteColors: [problem.badges ? .systemOrange : .secondaryLabelColor]))
                menu.addItem(row)
            }
        }

        menu.addItem(.separator())
        // Replaced by Settings… (⌘,) once the settings window exists (SETTINGS.md §4 step 5).
        menu.addItem(ClosureMenuItem(title: "Open config.toml…", keyEquivalent: ",", action: Self.openConfigFile))
        menu.addItem(themeMenuItem())

        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: "Quit Pika", keyEquivalent: "q") { NSApp.terminate(nil) })
    }

    private func themeMenuItem() -> NSMenuItem {
        let current = ConfigStore.shared.config.themeMode
        let submenu = NSMenu()
        let choices: [(ThemeMode, String)] = [(.auto, "Auto (follow macOS)"), (.dark, "Dark — Mocha"), (.light, "Light — Latte")]
        for (mode, title) in choices {
            let choice = ClosureMenuItem(title: title) { Self.setTheme(mode) }
            choice.state = mode == current ? .on : .off
            submenu.addItem(choice)
        }
        let item = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    // MARK: - Actions

    private static func setTheme(_ mode: ThemeMode) {
        do {
            try ConfigStore.shared.set(section: "appearance", key: "theme", to: .string(mode.rawValue))
        } catch {
            log.error("Couldn't save theme: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert(error: error)
            alert.messageText = "Pika couldn't save the theme to config.toml"
            NSApp.activate()
            alert.runModal()
        }
    }

    static func openConfigFile() {
        ConfigStore.shared.ensureFileExists()
        let url = ConfigStore.shared.fileURL
        // .toml often has no default app; fall back to TextEdit rather
        // than showing the "no application" dialog.
        if NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                                    configuration: NSWorkspace.OpenConfiguration())
        }
    }

    static func openSystemSettings(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// An `NSMenuItem` that runs a closure, so each row doesn't need its own
/// `@objc` method.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, keyEquivalent: String = "", action handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: keyEquivalent)
        target = self
    }
    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}
