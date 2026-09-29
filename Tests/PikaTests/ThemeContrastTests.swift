import AppKit
import Testing
@testable import Pika

/// WCAG 2 contrast floors for every token pair the panel draws
/// (SETTINGS.md §3.2). Mocha is the reference: where Mocha itself sits
/// below AA (dim and muted text), Latte must match it rather than be worse.
@Suite struct ThemeContrastTests {
    static func luminance(_ c: NSColor) -> Double {
        let s = c.usingColorSpace(.sRGB)!
        func lin(_ v: CGFloat) -> Double {
            let v = Double(v)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(s.redComponent) + 0.7152 * lin(s.greenComponent) + 0.0722 * lin(s.blueComponent)
    }

    static func contrast(_ a: NSColor, _ b: NSColor) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    struct Floor: CustomStringConvertible {
        let fg: KeyPath<Theme, NSColor>
        let bg: KeyPath<Theme, NSColor>
        let min: Double
        let label: String
        var description: String { label }
    }

    static let floors: [Floor] = [
        Floor(fg: \.fg, bg: \.bg, min: 4.5, label: "title on panel"),
        Floor(fg: \.fg, bg: \.bgInput, min: 4.5, label: "query text"),
        Floor(fg: \.fg, bg: \.selBg, min: 4.5, label: "title on selected row"),
        Floor(fg: \.fgDim, bg: \.bg, min: 4.3, label: "app name and recency"),
        Floor(fg: \.fgMuted, bg: \.bg, min: 3.3, label: "placeholder and empty state"),
        Floor(fg: \.accent, bg: \.bg, min: 4.5, label: "matched characters"),
        Floor(fg: \.accent, bg: \.bgInput, min: 4.4, label: "prompt glyph"),
        Floor(fg: \.accent, bg: \.selBg, min: 3.5, label: "matched characters on selected row (semibold)"),
        Floor(fg: \.accentAlt, bg: \.selBg, min: 3.0, label: "app name on selected row"),
        Floor(fg: \.selBg, bg: \.bg, min: 1.1, label: "selected row stands out at all"),
        Floor(fg: \.border, bg: \.bg, min: 1.75, label: "panel border"),
    ]

    @Test(arguments: floors) func mocha(_ f: Floor) {
        let t = Theme.catppuccinMocha
        #expect(Self.contrast(t[keyPath: f.fg], t[keyPath: f.bg]) >= f.min)
    }

    @Test(arguments: floors) func latte(_ f: Floor) {
        let t = Theme.catppuccinLatte
        #expect(Self.contrast(t[keyPath: f.fg], t[keyPath: f.bg]) >= f.min)
    }

    @Test func resolve() {
        #expect(Theme.resolve(.auto, systemIsDark: true) == .catppuccinMocha)
        #expect(Theme.resolve(.auto, systemIsDark: false) == .catppuccinLatte)
        #expect(Theme.resolve(.dark, systemIsDark: false) == .catppuccinMocha)
        #expect(Theme.resolve(.light, systemIsDark: true) == .catppuccinLatte)
    }
}

@Suite struct ThemeConfigTests {
    func mode(_ literal: String) -> (ThemeMode, [ConfigIssue]) {
        let (cfg, issues) = Config.parse(ConfigDocument(text: "[appearance]\ntheme = \(literal)\n"))
        return (cfg.themeMode, issues)
    }

    @Test func acceptsModesAndFlavourNames() {
        #expect(mode("\"auto\"").0 == .auto)
        #expect(mode("\"dark\"").0 == .dark)
        #expect(mode("\"Light\"").0 == .light)
        #expect(mode("\"catppuccin-mocha\"").0 == .dark)
        #expect(mode("\"catppuccin-latte\"").0 == .light)
        #expect(mode("\"dark\"").1.isEmpty)
    }

    @Test func defaultsToAuto() {
        #expect(Config().themeMode == .auto)
        #expect(Config.parse(ConfigDocument(text: "")).0.themeMode == .auto)
    }

    @Test func unknownValueIsReported() {
        let (m, issues) = mode("\"latt\"")
        #expect(m == .auto)
        #expect(issues.count == 1 && issues[0].message.contains("should be auto, dark, or light"))
    }
}
