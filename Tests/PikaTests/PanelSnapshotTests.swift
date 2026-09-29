import AppKit
import Testing
@testable import Pika

/// Renders the real panel in both themes, over a light and a dark window,
/// for eyeballing (SETTINGS.md §3.2.3). Opt-in: set PIKA_SNAPSHOT_DIR.
@MainActor @Suite struct PanelSnapshotTests {
    static let outDir = ProcessInfo.processInfo.environment["PIKA_SNAPSHOT_DIR"]

    static func target(_ app: String, _ bundleID: String, _ title: String, iconPath: String, age: TimeInterval) -> Target {
        let (bytes, appLen, mask) = TargetBuilder.makeHaystack(appName: app, title: title)
        return Target(
            id: TargetID(bundleID: bundleID, discriminator: title), kind: .window,
            appName: app, bundleID: bundleID, title: title,
            haystack: bytes, appNameLength: appLen, wordStartMask: mask,
            letterMask: TargetBuilder.letterMask(bytes),
            lastFocusedAt: Date().timeIntervalSince1970 - age,
            icon: NSWorkspace.shared.icon(forFile: iconPath), stale: false,
            handle: .window(pid: 0, ax: AXUIElementCreateApplication(0))
        )
    }

    @Test(.enabled(if: outDir != nil)) func render() throws {
        PikaFont.registerBundled()
        IndexStore.shared.replace([
            Self.target("Zed", "dev.zed.Zed", "pika — README.md", iconPath: "/System/Applications/TextEdit.app", age: 12),
            Self.target("Finder", "com.apple.finder", "pika", iconPath: "/System/Library/CoreServices/Finder.app", age: 240),
            Self.target("Ghostty", "com.mitchellh.ghostty", "~/Projects/Python/leet/appswitch/pika", iconPath: "/System/Applications/Utilities/Terminal.app", age: 60),
            Self.target("Chrome", "com.google.Chrome", "pika/README.md at main · tiagowright/pika", iconPath: "/Applications/Safari.app", age: 480),
            Self.target("Notes", "com.apple.Notes", "Pika planning", iconPath: "/System/Applications/Notes.app", age: 3600),
            Self.target("Safari", "com.apple.Safari", "Catppuccin palette", iconPath: "/Applications/Safari.app", age: 7200),
        ])

        for (name, theme) in [("mocha", Theme.catppuccinMocha), ("latte", Theme.catppuccinLatte)] {
            for query in ["", "pi"] {
                let view = PikaView(config: Config(), theme: theme)
                view.reset()
                for c in query {
                    let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                             context: nil, characters: String(c), charactersIgnoringModifiers: String(c), isARepeat: false, keyCode: 0)!
                    view.keyDown(with: e)
                }
                view.frame = NSRect(x: 0, y: 0, width: 680, height: view.contentHeight)
                let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                view.cacheDisplay(in: view.bounds, to: rep)

                for (behindName, behind) in [("on-light", NSColor.white), ("on-dark", NSColor(hex: 0x1c1c1e))] {
                    let margin: CGFloat = 40
                    let size = NSSize(width: 680 + margin * 2, height: view.bounds.height + margin * 2)
                    let image = NSImage(size: size, flipped: false) { _ in
                        behind.setFill(); NSRect(origin: .zero, size: size).fill()
                        let panelRect = NSRect(x: margin, y: margin, width: 680, height: view.bounds.height)
                        let clip = NSBezierPath(roundedRect: panelRect, xRadius: 6, yRadius: 6)
                        NSGraphicsContext.saveGraphicsState(); clip.addClip()
                        rep.draw(in: panelRect)
                        NSGraphicsContext.restoreGraphicsState()
                        theme.border.setStroke()
                        let border = NSBezierPath(roundedRect: panelRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
                        border.lineWidth = 1; border.stroke()
                        return true
                    }
                    let out = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
                    let q = query.isEmpty ? "empty" : query
                    try out.write(to: URL(fileURLWithPath: Self.outDir!).appendingPathComponent("\(name)-\(q)-\(behindName).png"))
                }
            }
        }
    }
}
