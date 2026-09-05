import AppKit

/// A borderless `NSPanel` refuses key window status by default, which
/// silently swallows every keystroke and click — they fall through to
/// whatever window is actually key underneath. `.nonactivatingPanel`
/// means becoming key does *not* activate our app or steal the menu
/// bar/Dock focus from the frontmost app, which is exactly what a
/// Spotlight-style overlay wants — but it still has to explicitly opt
/// in to key status to receive input at all.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Owns the single `NSPanel` instance. Pre-warmed once at launch and
/// never released — TECHNICAL.md §9 measured a first `orderFront` at
/// ~150ms on a cold panel vs ~3ms once warmed, which is the single
/// largest hot-path win available, so this class exists specifically to
/// make "create it once" hard to get wrong later.
final class PanelController {
    static let shared = PanelController()

    private var panel: NSPanel!
    private var view: PikaView!
    private let config: Config

    private(set) var isVisible = false

    private init() {
        config = Config.loadOrCreateDefault()
    }

    func prewarm() {
        PikaFont.registerBundled()

        let initialFrame = NSRect(x: 0, y: 0, width: config.panelWidth, height: 300)
        let panel = KeyablePanel(contentRect: initialFrame, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false

        let view = PikaView(config: config)
        view.wantsLayer = true
        view.layer?.cornerRadius = 6
        view.layer?.masksToBounds = true
        view.layer?.borderWidth = 1
        view.layer?.borderColor = config.theme.border.cgColor
        panel.contentView = view

        view.onEnter = { [weak self] target in self?.select(target) }
        view.onDismiss = { [weak self] in self?.hide() }

        self.panel = panel
        self.view = view

        // Force one offscreen layout + display pass now, so the first
        // real show later is just an orderFrontRegardless(), not a
        // cold-start layout (TECHNICAL.md §9/§12 checklist).
        panel.orderFrontRegardless()
        panel.display()
        panel.orderOut(nil)

        WindowSource.shared.start()
        if config.chromeTabs {
            ChromeTabSource.shared.scheduleRefresh(tier: .focusedWindow, delay: 0.3)
            ChromeTabSource.shared.scheduleRefresh(tier: .allWindows, delay: 1.0)
        }
        LearnedStore.shared.decayAll()
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        view.reset()
        layout()
        position()
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(view)
        isVisible = true
    }

    func hide() {
        panel.orderOut(nil)
        isVisible = false
    }

    /// Called from background sources (icons, Chrome tabs) landing while
    /// the panel may be open. A no-op, not a redraw, when hidden.
    func refreshIfVisible() {
        guard isVisible else { return }
        DispatchQueue.main.async { [weak self] in
            self?.view.refresh()
            self?.layout()
        }
    }

    private func layout() {
        let height = view.contentHeight
        panel.setContentSize(NSSize(width: config.panelWidth, height: height))
        view.frame = NSRect(x: 0, y: 0, width: config.panelWidth, height: height)
        view.needsDisplay = true
    }

    /// UX decision: panel appears on the screen containing the mouse.
    private func position() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        let frame = screen.visibleFrame
        let w = panel.frame.width
        let h = panel.frame.height
        let x = frame.minX + (frame.width - w) / 2
        let y = frame.minY + frame.height * 0.62 - h // ~38% from top, per UX.md §2
        panel.setFrameOrigin(NSPoint(x: x, y: max(frame.minY, y)))
    }

    private func select(_ target: Target) {
        hide() // perceived latency for the switch is ~0 — see TECHNICAL.md §10
        Activation.activate(target)
    }
}
