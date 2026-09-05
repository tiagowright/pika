import AppKit
import CoreText

/// Catppuccin Mocha, as named tokens per UX.md §7 so a config file can
/// swap the whole palette without touching drawing code.
struct Theme {
    var bg: NSColor
    var bgInput: NSColor
    var border: NSColor
    var fg: NSColor
    var fgDim: NSColor
    var fgMuted: NSColor
    var accent: NSColor
    var accentAlt: NSColor
    var selBg: NSColor
    var warn: NSColor

    static let catppuccinMocha = Theme(
        bg:        NSColor(hex: 0x1e1e2e),
        bgInput:   NSColor(hex: 0x181825),
        border:    NSColor(hex: 0x45475a),
        fg:        NSColor(hex: 0xcdd6f4),
        fgDim:     NSColor(hex: 0x7f849c),
        fgMuted:   NSColor(hex: 0x6c7086),
        accent:    NSColor(hex: 0xcba6f7),
        accentAlt: NSColor(hex: 0x89b4fa),
        selBg:     NSColor(hex: 0x313244),
        warn:      NSColor(hex: 0xf9e2af)
    )
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
}

enum PikaFont {
    static let family = "JetBrains Mono"

    /// Registers the bundled JetBrains Mono so it's available even on a
    /// machine that never installed it (UX.md: "bundled with the app").
    static func registerBundled() {
        guard let url = Bundle.module.url(forResource: "JetBrainsMono", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    static func font(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        // Look up by family (not PostScript name) — the bundled file is a
        // variable font, and its exact PS name isn't worth hardcoding.
        let descriptor = NSFontDescriptor(fontAttributes: [.family: family])
        if let f = NSFont(descriptor: descriptor, size: size) { return f }
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }
}
