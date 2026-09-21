import AppKit
import ApplicationServices

/// Enter → foreground, per TECHNICAL.md §10. Order matters: raise the
/// specific AX window before activating the app, so the app doesn't
/// flash whatever window it last had frontmost; select the Chrome tab
/// last since it's a separate, slower round-trip that shouldn't be on
/// the perceived-latency path (the window is already up by then).
enum Activation {
    static func activate(_ target: Target) {
        let now = Date().timeIntervalSince1970
        MRUStore.shared.touch(id: target.id, title: target.title, at: now)
        IndexStore.shared.bumpRecency(target.id, to: now)

        switch target.handle {
        case .window(let pid, let ax):
            raiseAndActivate(pid: pid, ax: ax)
        case .tab(let pid, let ax, let windowIndex, let tabIndex):
            raiseAndActivate(pid: pid, ax: ax)
            selectChromeTab(windowID: windowIndex, tabIndex: tabIndex)
        }
    }

    private static func raiseAndActivate(pid: pid_t, ax: AXUIElement) {
        let queue = DispatchQueue(label: "pika.activate")
        queue.async {
            AXUIElementSetAttributeValue(ax, kAXMinimizedAttribute as CFString, false as CFTypeRef)
            // Main *before* raise: activation follows the app's main
            // window, so if the target lives on another Space this is
            // what makes macOS switch Spaces rather than surfacing
            // whatever the app happens to have on the current one.
            AXUIElementSetAttributeValue(ax, kAXMainAttribute as CFString, true as CFTypeRef)
            AXUIElementPerformAction(ax, kAXRaiseAction as CFString)
            DispatchQueue.main.async {
                NSRunningApplication(processIdentifier: pid)?.activate(options: [])
                // One more raise once the app owns the foreground. Apps
                // that restore their own front window on activation
                // would otherwise beat us back to the wrong Space; a
                // repeat raise on an already-front window is a no-op.
                queue.asyncAfter(deadline: .now() + 0.05) {
                    AXUIElementPerformAction(ax, kAXRaiseAction as CFString)
                }
            }
        }
    }

    private static func selectChromeTab(windowID: Int, tabIndex: Int) {
        let source = """
        tell application "Google Chrome"
            set active tab index of (first window whose id is \(windowID)) to \(tabIndex)
        end tell
        """
        DispatchQueue(label: "pika.chrome.select").async {
            NSAppleScript(source: source)?.executeAndReturnError(nil)
        }
    }
}
