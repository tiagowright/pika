import AppKit
import Observation
import ServiceManagement
import os

private let log = Logger(subsystem: "io.github.tiagowright.pika", category: "settings")

/// Everything the settings window shows, mirrored from the live stores so
/// SwiftUI can observe it. It also holds the window's transient UI state
/// (recording, slider drafts, confirmations): SwiftUI's `@State` is a
/// compiler macro whose plugin ships only with Xcode, and Pika builds with
/// the Command Line Tools alone.
/// The window never keeps its own copy of a
/// setting: every change is written to config.toml through ConfigStore,
/// and what's shown is whatever ConfigStore then parsed (SETTINGS.md §1.1).
///
/// Main thread only.
@Observable
final class SettingsModel {
    enum Pane: String, CaseIterable, Identifiable {
        case general, permissions, appearance, search, sources, privacy, about
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "General"
            case .permissions: return "Permissions"
            case .appearance: return "Appearance"
            case .search: return "Search & Ranking"
            case .sources: return "Sources"
            case .privacy: return "Privacy & Data"
            case .about: return "About"
            }
        }

        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .permissions: return "lock.shield"
            case .appearance: return "paintpalette"
            case .search: return "magnifyingglass"
            case .sources: return "square.stack"
            case .privacy: return "hand.raised"
            case .about: return "info.circle"
            }
        }
    }

    var pane: Pane = .general

    private(set) var config: Config
    private(set) var issues: [ConfigIssue]
    private(set) var accessibility: Bool
    private(set) var chrome: ChromeAccess
    private(set) var loginItem: LoginItemState
    private(set) var hotkeyHealth: HotkeyHealth
    private(set) var theme: Theme

    /// Optional checklist items the user chose to skip during onboarding
    /// (SETTINGS.md §2.4.4), mirrored from state.json.
    private(set) var skipped: Set<String>

    /// Settings → Permissions → Run Setup Again (SETTINGS.md §2.4.1).
    @ObservationIgnored var runSetupAgain: (() -> Void)?

    /// ⌥ held: show each control's config.toml key.
    var showKeys = false
    /// Set when a write to config.toml fails; shown as an alert.
    var saveError: String?

    // Transient UI state (see the type comment).
    var recordingHotkey = false
    var hotkeyHint: String?
    var sliderDrafts: [String: Double] = [:]
    var confirmForgetLearned = false
    var privacyConfirm: PrivacyAction?
    private(set) var showAccessibilityTroubleshooting = false
    @ObservationIgnored private var hotkeyMonitor: Any?
    @ObservationIgnored private var troubleshootingTimer: DispatchWorkItem?

    enum PrivacyAction: String, Identifiable {
        case recency, learned, icons
        var id: String { rawValue }
    }

    @ObservationIgnored let hotKey: HotKeyManager

    init(hotKey: HotKeyManager) {
        self.hotKey = hotKey
        let store = ConfigStore.shared
        let permissions = PermissionCenter.shared
        config = store.config
        issues = store.issues
        accessibility = permissions.accessibility
        chrome = permissions.chrome
        loginItem = permissions.loginItem
        hotkeyHealth = hotKey.health(for: store.config)
        theme = Appearance.shared.theme
        skipped = Set(StateStore.shared.state.skipped)

        store.observe { [weak self] _, _ in self?.sync() }
        store.observeIssues { [weak self] _ in self?.sync() }
        permissions.observe { [weak self] in self?.sync() }
        Appearance.shared.observe { [weak self] theme in self?.theme = theme }
    }

    /// Re-reads everything. Cheap; called on any store change and when the
    /// window comes forward.
    func sync() {
        let permissions = PermissionCenter.shared
        config = ConfigStore.shared.config
        issues = ConfigStore.shared.issues
        accessibility = permissions.accessibility
        chrome = permissions.chrome
        loginItem = permissions.loginItem
        hotkeyHealth = hotKey.health(for: config)
        skipped = Set(StateStore.shared.state.skipped)
        if accessibility {
            troubleshootingTimer?.cancel()
            showAccessibilityTroubleshooting = false
        }
    }

    // MARK: - Writing settings

    func set(_ section: String, _ key: String, _ value: ConfigValue) {
        do {
            try ConfigStore.shared.set(section: section, key: key, to: value)
        } catch {
            log.error("Couldn't write \(section).\(key): \(error.localizedDescription, privacy: .public)")
            saveError = "Pika couldn't save to config.toml: \(error.localizedDescription)"
        }
        sync() // the hotkey observer in AppDelegate has re-registered by now
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("Launch at login: \(error.localizedDescription, privacy: .public)")
            saveError = "macOS didn't accept the change: \(error.localizedDescription)"
        }
        PermissionCenter.shared.refresh()
        sync()
    }

    func requestChromeAccess() {
        PermissionCenter.shared.requestChromeAccess { [weak self] _ in self?.sync() }
    }

    func openChrome() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: PermissionCenter.chromeBundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func requestAccessibility() {
        // Shows the system prompt only the very first time; after that,
        // System Settings is the only way.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        StatusItemController.openSystemSettings(SystemSettingsPane.accessibility)

        // Still not granted 20 s later: explain the usual reasons
        // (SETTINGS.md §2.3.5, S8).
        troubleshootingTimer?.cancel()
        let check = DispatchWorkItem { [weak self] in
            guard let self, !PermissionCenter.shared.accessibility else { return }
            self.showAccessibilityTroubleshooting = true
        }
        troubleshootingTimer = check
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: check)
    }

    // MARK: - Hotkey recording

    /// While recording, the global hotkey is released, so pressing the
    /// current one is captured here instead of opening the panel.
    func startRecordingHotkey() {
        guard !recordingHotkey else { return }
        hotkeyHint = nil
        recordingHotkey = true
        hotKey.suspend()
        hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleRecorded(event)
            return nil // swallow everything while recording
        }
    }

    func stopRecordingHotkey() {
        if let hotkeyMonitor { NSEvent.removeMonitor(hotkeyMonitor) }
        hotkeyMonitor = nil
        guard recordingHotkey else { return }
        recordingHotkey = false
        hotKey.resume()
        sync()
    }

    private func handleRecorded(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53, flags.isEmpty { // Esc cancels
            hotkeyHint = nil
            stopRecordingHotkey()
            return
        }
        guard let text = Config.hotkeyString(
            keyCode: UInt32(event.keyCode),
            command: flags.contains(.command), control: flags.contains(.control),
            option: flags.contains(.option), shift: flags.contains(.shift)
        ) else {
            hotkeyHint = "Pika can't use that key. Try a letter, number, space, or F-key."
            return
        }
        if case .failure(let problem) = Config.parseHotkey(text) {
            hotkeyHint = "\(text): \(problem.message)."
            return
        }
        hotkeyHint = nil
        set("", "hotkey", .string(text))
        stopRecordingHotkey()
    }

    // MARK: - Onboarding

    /// Skipping Chrome also turns Chrome tabs off, so Pika never springs
    /// the Automation prompt on someone who said no here (SHIPPING O4).
    func skip(_ item: PermissionChecklist.Item) {
        StateStore.shared.update { state in
            if !state.skipped.contains(item.id) { state.skipped.append(item.id) }
        }
        if item == .chrome, config.chromeTabs {
            set("sources", "chrome_tabs", .bool(false))
        }
        sync()
    }

    func isSkipped(_ item: PermissionChecklist.Item) -> Bool { skipped.contains(item.id) }

    /// Everything onboarding requires: Accessibility, and a hotkey that
    /// will actually fire.
    var requiredItemsDone: Bool {
        accessibility && !hotkeyHealth.isProblem && hotkeyHealth != .notRegisteredYet
    }

    // MARK: - Data

    func perform(_ action: PrivacyAction) {
        switch action {
        case .recency: MRUStore.shared.forgetAll()
        case .learned: LearnedStore.shared.forgetAll()
        case .icons: IconCache.shared.clearDisk()
        }
    }
}

/// Deep links into System Settings (SHIPPING.md §4.1.3).
enum SystemSettingsPane {
    static let accessibility = "com.apple.preference.security?Privacy_Accessibility"
    static let automation = "com.apple.preference.security?Privacy_Automation"
    static let loginItems = "com.apple.LoginItems-Settings.extension"
    static let keyboard = "com.apple.Keyboard-Settings.extension"
}
