import AppKit
import SwiftUI
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

@MainActor @Suite struct MenuBarIconSnapshotTests {
    @Test(.enabled(if: PanelSnapshotTests.outDir != nil)) func render() throws {
        for badged in [false, true] {
            for (name, bg, appearance) in [("light", NSColor(white: 0.93, alpha: 1), NSAppearance(named: .aqua)!),
                                           ("dark", NSColor(white: 0.15, alpha: 1), NSAppearance(named: .darkAqua)!)] {
                let icon = PikaGlyph.menuBarImage(badged: badged)
                let scale: CGFloat = 8
                let size = NSSize(width: 18 * scale, height: 18 * scale)
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
                                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                appearance.performAsCurrentDrawingAppearance {
                    bg.setFill(); NSRect(origin: .zero, size: size).fill()
                    if icon.isTemplate {
                        // What the menu bar does with a template: tint it with the label colour.
                        let tinted = NSImage(size: icon.size, flipped: false) { r in
                            icon.draw(in: r); NSColor.labelColor.set(); r.fill(using: .sourceAtop); return true
                        }
                        tinted.draw(in: NSRect(origin: .zero, size: size))
                    } else {
                        icon.draw(in: NSRect(origin: .zero, size: size))
                    }
                }
                NSGraphicsContext.restoreGraphicsState()
                try rep.representation(using: .png, properties: [:])!
                    .write(to: URL(fileURLWithPath: PanelSnapshotTests.outDir!).appendingPathComponent("menubar-\(badged ? "badged" : "plain")-\(name).png"))
            }
        }
    }
}

@MainActor @Suite struct SettingsSnapshotTests {
    @Test(.enabled(if: PanelSnapshotTests.outDir != nil)) func render() throws {
        PikaFont.registerBundled()
        _ = NSApplication.shared
        let model = SettingsModel(hotKey: HotKeyManager())
        for (name, appearance) in [("light", NSAppearance(named: .aqua)!), ("dark", NSAppearance(named: .darkAqua)!)] {
            for pane in SettingsModel.Pane.allCases where name == "light" || [.permissions, .appearance].contains(pane) {
                model.pane = pane
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
                                      styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
                window.appearance = appearance
                window.isReleasedWhenClosed = false
                window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
                window.setContentSize(NSSize(width: 760, height: 540))
                // SwiftUI draws through Core Animation, which cacheDisplay
                // can't capture: put the window on screen and let the window
                // server take the picture.
                window.center()
                window.orderFrontRegardless()
                RunLoop.main.run(until: Date().addingTimeInterval(0.6)) // let SwiftUI settle
                let out = URL(fileURLWithPath: PanelSnapshotTests.outDir!).appendingPathComponent("settings-\(pane.rawValue)-\(name).png")
                let capture = Process()
                capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), out.path]
                try capture.run()
                capture.waitUntilExit()
                window.close()
            }
        }
    }
}
