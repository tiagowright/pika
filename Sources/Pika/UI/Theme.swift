import AppKit
import CoreText

/// `[appearance] theme` in config.toml.
enum ThemeMode: String, CaseIterable {
    case auto   // follow macOS
    case dark   // Catppuccin Mocha
    case light  // Catppuccin Latte
}

/// Catppuccin, as named tokens per UX.md §7 so drawing code never names
/// a colour directly.
struct Theme: Equatable {
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

    /// Latte's overlays sit much closer to its background than Mocha's do,
    /// so mapping each token to the same Catppuccin role as Mocha fails
    /// contrast (2.8:1 for dim text). Where the roles differ from Mocha,
    /// the choice is explained in SETTINGS.md §3.2 and pinned by
    /// ThemeContrastTests.
    static let catppuccinLatte = Theme(
        bg:        NSColor(hex: 0xeff1f5), // base
        bgInput:   NSColor(hex: 0xe6e9ef), // mantle
        border:    NSColor(hex: 0x9ca0b0), // overlay0 — surface1 vanishes against a light window behind
        fg:        NSColor(hex: 0x4c4f69), // text
        fgDim:     NSColor(hex: 0x6c6f85), // subtext0 — same contrast as Mocha's overlay1
        fgMuted:   NSColor(hex: 0x7c7f93), // overlay2 — same contrast as Mocha's overlay0
        accent:    NSColor(hex: 0x8839ef), // mauve
        accentAlt: NSColor(hex: 0x1e66f5), // blue
        selBg:     NSColor(hex: 0xd8dae1), // overlay2 at 20% over base, per the style guide
        warn:      NSColor(hex: 0xdf8e1d)  // yellow — under 3:1, so never used as colour alone
    )

    static func resolve(_ mode: ThemeMode, systemIsDark: Bool) -> Theme {
        switch mode {
        case .dark: return .catppuccinMocha
        case .light: return .catppuccinLatte
        case .auto: return systemIsDark ? .catppuccinMocha : .catppuccinLatte
        }
    }
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
        // variable font, and its exact PS name isn't worth hardcoding. A
        // weight trait selects one of its named instances (SemiBold etc.),
        // which keep the same advance width, so columns don't shift.
        var attributes: [NSFontDescriptor.AttributeName: Any] = [.family: family]
        if weight != .regular {
            attributes[.traits] = [NSFontDescriptor.TraitKey.weight: weight]
        }
        let descriptor = NSFontDescriptor(fontAttributes: attributes)
        if let f = NSFont(descriptor: descriptor, size: size) { return f }
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }
}
