import AppKit

/// Pika is an accessory app — no Dock icon, not in ⌘Tab — which is right
/// for the switcher and wrong for real windows: once the user leaves for
/// System Settings, there's no way back but the menu bar. So while Setup
/// or Settings is open, Pika becomes a regular app (Dock icon, ⌘Tab, menu
/// bar menus), and returns to accessory when the last one closes.
///
/// Main thread only.
enum AppPresence {
    private static var openWindows: Set<ObjectIdentifier> = []

    static func windowOpened(_ window: NSWindow) {
        openWindows.insert(ObjectIdentifier(window))
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        bringForward(window)
        // The switch to a regular app lands asynchronously, and an
        // activation requested before it can be dropped: ask again once
        // it has.
        DispatchQueue.main.async { bringForward(window) }
    }

    /// `NSApp.activate()` is cooperative, and macOS turns it down when the
    /// keypress that asked for Settings went to Pika's non-activating
    /// switcher panel rather than to an active Pika. The window then sits
    /// in front but inactive — drawn dimmed — until the user clicks away
    /// and back. The user did ask for this window, so activate outright.
    private static func bringForward(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    static func windowClosed(_ window: NSWindow) {
        openWindows.remove(ObjectIdentifier(window))
        guard openWindows.isEmpty else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
