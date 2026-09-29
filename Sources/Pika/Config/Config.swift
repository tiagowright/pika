import Foundation
import Carbon.HIToolbox

/// Pika's settings, as read from `config.toml` (via `ConfigDocument`).
/// Every value here has a default, so a missing or partly broken file
/// still yields a working config — but anything that couldn't be applied
/// is reported through `parse`'s issues, never silently dropped
/// (SHIPPING.md §4.2).
struct Config: Equatable {
    var hotkey: String = "ctrl+space"
    var hotkeyKeyCode: UInt32 = UInt32(kVK_Space)
    var hotkeyModifiers: UInt32 = UInt32(controlKey)

    var themeMode: ThemeMode = .auto
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
    # Pika settings. Edit by hand or from Pika → Settings — Pika keeps your
    # comments and ordering when it changes a value, and picks up edits
    # here without a restart.

    hotkey = "ctrl+space"        # modifiers (ctrl, cmd, alt, shift) + key, e.g. "cmd+shift+k"

    [appearance]
    theme        = "auto"        # auto (follow macOS), dark, or light
    font_size    = 13            # 9–24
    width        = 680           # panel width in points, 400–1600
    max_rows     = 10            # 3–30
    show_icons   = true

    [appearance.cursor]
    blink = false

    [ranking]
    recency_weight  = 40         # 0–200; how much recency nudges a match
    learning        = true       # remember which target you pick per query
    learn_weight    = 60         # 0–200
    include_current = false      # list the window you're already in

    [sources]
    chrome_tabs = true           # list individual Chrome tabs (asks for Automation)

    """

    // MARK: - Schema

    enum Kind { case string, bool, number }

    struct Key {
        let kind: Kind
        var range: ClosedRange<Double>? = nil
    }

    /// Every key Pika reads. Anything else in the file is reported.
    static let schema: [String: [String: Key]] = [
        "": ["hotkey": Key(kind: .string)],
        "appearance": [
            "theme": Key(kind: .string),
            "font_size": Key(kind: .number, range: 9...24),
            "width": Key(kind: .number, range: 400...1600),
            "max_rows": Key(kind: .number, range: 3...30),
            "show_icons": Key(kind: .bool),
        ],
        "appearance.cursor": ["blink": Key(kind: .bool)],
        "ranking": [
            "recency_weight": Key(kind: .number, range: 0...200),
            "learning": Key(kind: .bool),
            "learn_weight": Key(kind: .number, range: 0...200),
            "include_current": Key(kind: .bool),
        ],
        "sources": ["chrome_tabs": Key(kind: .bool)],
    ]

    /// Keys that older default files contain but that do nothing. Named
    /// specifically so the report says why, rather than "unknown key".
    private static let retiredKeys: [String: String] = [
        "appearance.font": "the font is always the bundled JetBrains Mono — this line can be deleted",
    ]

    // MARK: - Parsing

    static func parse(_ doc: ConfigDocument) -> (Config, [ConfigIssue]) {
        var cfg = Config()
        var issues = doc.issues
        var values: [String: (entry: ConfigDocument.Entry, value: Any)] = [:]

        for entry in doc.entries {
            let path = ConfigDocument.path(entry.section, entry.key)
            if let reason = retiredKeys[path] {
                issues.append(ConfigIssue(line: entry.line, message: "`\(path)` is ignored: \(reason)", isNotice: true))
                continue
            }
            guard let spec = schema[entry.section]?[entry.key] else {
                let known = schema[entry.section] == nil && !entry.section.isEmpty
                    ? "unknown section `[\(entry.section)]`"
                    : "unknown key `\(path)`"
                issues.append(ConfigIssue(line: entry.line, message: "\(known) — ignored"))
                continue
            }
            switch typed(entry, spec) {
            case .success(let v): values[path] = (entry, v)
            case .failure(let problem):
                issues.append(ConfigIssue(line: entry.line, message: "`\(path) = \(entry.literal)` \(problem.message) — using the default"))
            }
        }

        func string(_ p: String) -> String? { values[p]?.value as? String }
        func bool(_ p: String) -> Bool? { values[p]?.value as? Bool }
        func number(_ p: String) -> Double? { values[p]?.value as? Double }

        if let v = string("hotkey"), let entry = values["hotkey"]?.entry {
            switch parseHotkey(v) {
            case .success(let parsed):
                cfg.hotkey = v
                cfg.hotkeyKeyCode = parsed.keyCode
                cfg.hotkeyModifiers = parsed.modifiers
            case .failure(let problem):
                issues.append(ConfigIssue(line: entry.line, message: "hotkey \"\(v)\": \(problem.message) — using \"\(cfg.hotkey)\""))
            }
        }
        if let v = string("appearance.theme"), let entry = values["appearance.theme"]?.entry {
            if let mode = themeAliases[v.lowercased()] {
                cfg.themeMode = mode
            } else {
                issues.append(ConfigIssue(line: entry.line, message: "`appearance.theme = \(entry.literal)` should be auto, dark, or light — using auto"))
            }
        }
        if let v = number("appearance.font_size") {
            cfg.fontSize = CGFloat(v)
            cfg.inputFontSize = CGFloat(v) + 2
        }
        if let v = number("appearance.width") { cfg.panelWidth = CGFloat(v) }
        if let v = number("appearance.max_rows") { cfg.maxRows = Int(v.rounded()) }
        if let v = bool("appearance.show_icons") { cfg.showIcons = v }
        if let v = bool("appearance.cursor.blink") { cfg.cursorBlink = v }
        if let v = number("ranking.recency_weight") { cfg.recencyWeight = v }
        if let v = bool("ranking.learning") { cfg.learning = v }
        if let v = number("ranking.learn_weight") { cfg.learnWeight = v }
        if let v = bool("ranking.include_current") { cfg.includeCurrent = v }
        if let v = bool("sources.chrome_tabs") { cfg.chromeTabs = v }

        issues.sort { ($0.line ?? .max) < ($1.line ?? .max) }
        return (cfg, issues)
    }

    /// The flavour names are what older default files wrote.
    private static let themeAliases: [String: ThemeMode] = [
        "auto": .auto, "dark": .dark, "light": .light,
        "catppuccin-mocha": .dark, "catppuccin-latte": .light,
    ]

    struct Problem: Error { let message: String }

    /// Checks a value against its key's kind. Numbers outside the key's
    /// range are rejected rather than clamped, so the file and the running
    /// config never quietly disagree.
    private static func typed(_ entry: ConfigDocument.Entry, _ spec: Key) -> Result<Any, Problem> {
        let quoted = entry.literal.hasPrefix("\"")
        switch spec.kind {
        case .string:
            // TOML wants quotes; accept a bare word too, as the old parser did.
            return .success(entry.value)
        case .bool:
            switch entry.literal {
            case "true": return .success(true)
            case "false": return .success(false)
            default: return .failure(Problem(message: "should be true or false"))
            }
        case .number:
            guard !quoted, let d = Double(entry.literal.replacingOccurrences(of: "_", with: "")) else {
                return .failure(Problem(message: "should be a number"))
            }
            if let range = spec.range, !range.contains(d) {
                return .failure(Problem(message: "is outside \(ConfigValue.double(range.lowerBound).literal)–\(ConfigValue.double(range.upperBound).literal)"))
            }
            return .success(d)
        }
    }

    // MARK: - Hotkey

    /// Parses "ctrl+space", "cmd+shift+k", etc. into Carbon modifier
    /// flags + a virtual keycode.
    static func parseHotkey(_ s: String) -> Result<(keyCode: UInt32, modifiers: UInt32), Problem> {
        let parts = s.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = parts.last, !last.isEmpty else { return .failure(Problem(message: "no key given")) }
        var mods: UInt32 = 0
        for p in parts.dropLast() {
            switch p {
            case "ctrl", "control": mods |= UInt32(controlKey)
            case "cmd", "command": mods |= UInt32(cmdKey)
            case "alt", "option", "opt": mods |= UInt32(optionKey)
            case "shift": mods |= UInt32(shiftKey)
            default: return .failure(Problem(message: "unknown modifier `\(p)`"))
            }
        }
        guard let keyCode = keyCodeMap[last] else { return .failure(Problem(message: "unknown key `\(last)`")) }
        // A global hotkey with no modifier (or only shift) would swallow
        // that key everywhere on the system.
        guard mods & ~UInt32(shiftKey) != 0 else {
            return .failure(Problem(message: "needs at least one of ctrl, cmd, or alt"))
        }
        return .success((keyCode, mods))
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
