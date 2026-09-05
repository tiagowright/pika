import Foundation
import Carbon.HIToolbox

/// A deliberately tiny TOML-subset parser — just enough for the flat
/// `[section] key = value` shape in UX.md §7's config sketch. Not a
/// general TOML implementation; arrays/nesting beyond one level aren't
/// needed for v1's schema.
struct Config {
    var hotkeyKeyCode: UInt32 = UInt32(kVK_Space)
    var hotkeyModifiers: UInt32 = UInt32(controlKey)

    var theme = Theme.catppuccinMocha
    var fontSize: CGFloat = 13
    var inputFontSize: CGFloat = 15
    var panelWidth: CGFloat = 680
    var maxRows: Int = 10
    var showIcons: Bool = true
    var cursorBlink: Bool = false

    var recencyWeight: Double = 40
    var learning: Bool = true
    var learnWeight: Double = 60
    var includeCurrent: Bool = false

    var chromeTabs: Bool = true

    static let defaultText = """
    hotkey = "ctrl+space"

    [appearance]
    theme        = "catppuccin-mocha"
    font         = "JetBrains Mono"
    font_size    = 13
    width        = 680
    max_rows     = 10
    show_icons   = true

    [appearance.cursor]
    blink = false

    [ranking]
    recency_weight  = 40
    learning        = true
    learn_weight    = 60
    include_current = false

    [sources]
    chrome_tabs = true
    """

    static func loadOrCreateDefault() -> Config {
        let dir = AppPaths.configDirectory
        let file = dir.appendingPathComponent("config.toml")
        if let data = try? String(contentsOf: file, encoding: .utf8) {
            return parse(data)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? defaultText.write(to: file, atomically: true, encoding: .utf8)
        return Config()
    }

    private static func parse(_ text: String) -> Config {
        var cfg = Config()
        var section = ""
        var table: [String: [String: String]] = [:]

        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast())
                continue
            }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[line.startIndex..<eq].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if let hashIdx = value.firstIndex(of: "#") { value = String(value[value.startIndex..<hashIdx]).trimmingCharacters(in: .whitespaces) }
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            table[section, default: [:]][key] = value
        }

        if let hotkey = table[""]?["hotkey"], let parsed = parseHotkey(hotkey) {
            cfg.hotkeyKeyCode = parsed.keyCode
            cfg.hotkeyModifiers = parsed.modifiers
        }
        if let v = table["appearance"]?["font_size"].flatMap(Double.init) { cfg.fontSize = CGFloat(v) }
        if let v = table["appearance"]?["width"].flatMap(Double.init) { cfg.panelWidth = CGFloat(v) }
        if let v = table["appearance"]?["max_rows"].flatMap(Int.init) { cfg.maxRows = v }
        if let v = table["appearance"]?["show_icons"].flatMap(boolValue) { cfg.showIcons = v }
        if let v = table["appearance.cursor"]?["blink"].flatMap(boolValue) { cfg.cursorBlink = v }
        if let v = table["ranking"]?["recency_weight"].flatMap(Double.init) { cfg.recencyWeight = v }
        if let v = table["ranking"]?["learning"].flatMap(boolValue) { cfg.learning = v }
        if let v = table["ranking"]?["learn_weight"].flatMap(Double.init) { cfg.learnWeight = v }
        if let v = table["ranking"]?["include_current"].flatMap(boolValue) { cfg.includeCurrent = v }
        if let v = table["sources"]?["chrome_tabs"].flatMap(boolValue) { cfg.chromeTabs = v }

        return cfg
    }

    private static func boolValue(_ s: String) -> Bool? {
        switch s.lowercased() { case "true": return true; case "false": return false; default: return nil }
    }

    /// Parses "ctrl+space", "cmd+shift+k", etc. into Carbon modifier
    /// flags + a virtual keycode.
    private static func parseHotkey(_ s: String) -> (keyCode: UInt32, modifiers: UInt32)? {
        let parts = s.lowercased().split(separator: "+").map(String.init)
        guard let last = parts.last else { return nil }
        var mods: UInt32 = 0
        for p in parts.dropLast() {
            switch p {
            case "ctrl", "control": mods |= UInt32(controlKey)
            case "cmd", "command": mods |= UInt32(cmdKey)
            case "alt", "option": mods |= UInt32(optionKey)
            case "shift": mods |= UInt32(shiftKey)
            default: break
            }
        }
        guard let keyCode = keyCodeMap[last] else { return nil }
        return (keyCode, mods)
    }

    private static let keyCodeMap: [String: UInt32] = [
        "space": UInt32(kVK_Space), "return": UInt32(kVK_Return), "tab": UInt32(kVK_Tab),
        "escape": UInt32(kVK_Escape),
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
        "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
    ]
}
