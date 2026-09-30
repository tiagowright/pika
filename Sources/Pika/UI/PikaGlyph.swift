import AppKit

/// Pika's artwork, bundled as SVG in `Resources/Icons` — see `icons/`
/// for how the variants are made and a page to inspect them all. NSImage
/// renders SVG natively, so every size stays crisp from the one file.
enum PikaArt {
    static func svg(_ name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "svg", subdirectory: "Icons") else { return nil }
        return NSImage(contentsOf: url)
    }

    /// Pika.app's AppIcon.icns is the Mocha icon, so the light theme swaps
    /// in Latte while Pika runs (Dock, ⌘Tab, Settings, onboarding) and
    /// the dark theme goes back to the bundle's own icon.
    static func applyAppIcon(for theme: Theme) {
        NSApp.applicationIconImage = theme.isDark ? nil : latteAppIcon
    }
    private static let latteAppIcon = svg("pika-origami-latte")
}

/// The simplified leaping pika: the menu bar icon, and the same mark in
/// the switcher's query row so the two read as one app. Flat facets from
/// the app icon, in Mocha colours on dark backgrounds and Latte on light.
enum PikaGlyph {
    private static let mocha = PikaArt.svg("pika-glyph-mocha")
    private static let latte = PikaArt.svg("pika-glyph-latte")

    /// Width over height of the glyph's viewBox (296 × 198).
    static let aspect: CGFloat = 296.0 / 198.0

    /// The glyph for one background, at its SVG size; callers size it.
    static func image(dark: Bool) -> NSImage? { dark ? mocha : latte }

    /// Draws the glyph as large as fits, centred in `rect`. Works in
    /// flipped and unflipped contexts.
    static func draw(in rect: NSRect, dark: Bool) {
        guard let art = image(dark: dark) else { return }
        let width = min(rect.width, rect.height * aspect)
        let height = width / aspect
        let target = NSRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
        art.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    /// The status item image. It follows the menu bar's own appearance,
    /// which tracks the wallpaper rather than the Pika theme: AppKit
    /// reruns the handler whenever that appearance changes. `badged` adds
    /// an orange dot: something needs the user's attention.
    static func menuBarImage(badged: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 24, height: 16), flipped: true) { rect in
            let dark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            draw(in: rect, dark: dark)
            if badged {
                let context = NSGraphicsContext.current
                let dot = NSRect(x: rect.maxX - 6, y: rect.maxY - 6, width: 6, height: 6)
                context?.compositingOperation = .clear
                NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill() // gap around the dot
                context?.compositingOperation = .sourceOver
                NSColor.systemOrange.setFill()
                NSBezierPath(ovalIn: dot).fill()
            }
            return true
        }
        image.accessibilityDescription = badged ? "Pika — needs attention" : "Pika"
        return image
    }
}
