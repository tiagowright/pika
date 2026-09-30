import AppKit
import SwiftUI

/// Owns the one settings window. Created on first use and kept, so
/// reopening is instant and the window remembers its pane and position.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    let model: SettingsModel
    private var flagsMonitor: Any?

    /// Onboarding shares the same model, so both always agree.
    init(model: SettingsModel) {
        PikaFont.registerBundled() // Settings can open before the panel is ever built
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.title = "Pika Settings"
        window.contentMinSize = NSSize(width: 680, height: 460)
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
        window.center()
        window.setFrameAutosaveName("PikaSettings")
        super.init(window: window)
        window.delegate = self
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(_ pane: SettingsModel.Pane? = nil) {
        if let pane { model.pane = pane }
        PermissionCenter.shared.refresh()
        model.sync()
        guard let window else { return }
        AppPresence.windowOpened(window)
        showWindow(nil)
        // Pika has no Dock icon and is rarely the active app, and macOS may
        // decline activation; ordering front regardless keeps the window
        // from opening behind whatever the user was in.
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        // Coming back from System Settings: look again (SETTINGS.md §2.3.1).
        PermissionCenter.shared.refresh()
        model.sync()
        // ⌥ reveals config keys, only while this window is key.
        flagsMonitor = flagsMonitor ?? NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.model.showKeys = event.modifierFlags.contains(.option)
            return event
        }
    }

    func windowWillClose(_ notification: Notification) {
        model.stopRecordingHotkey()
        if let window { AppPresence.windowClosed(window) }
    }

    func windowDidResignKey(_ notification: Notification) {
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        flagsMonitor = nil
        model.showKeys = false
    }
}
