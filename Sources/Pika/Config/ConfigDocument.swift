import Foundation

/// A problem found in `config.toml`, reported to the user rather than
/// silently defaulted away (SHIPPING.md §4.2, SETTINGS.md §1.4.4).
struct ConfigIssue: Equatable {
    let line: Int?       // 1-based; nil when the issue isn't tied to a line
    let message: String

    var description: String {
        line.map { "config.toml line \($0): \(message)" } ?? "config.toml: \(message)"
    }
}

/// `config.toml` as an ordered list of its lines, so Pika can change one
/// value without disturbing the user's comments, alignment, key order,
/// or keys it doesn't know (SETTINGS.md §1.4.2). Same TOML subset as
/// before: `[section]` headers and `key = value` lines, one level of
/// dotted section names, no arrays or inline tables.
///
/// Unmodified, `text` reproduces the input byte for byte.
struct ConfigDocument {
    struct Entry {
        let section: String
        let key: String
        let line: Int
        /// Everything up to the value, e.g. `"font_size    = "`.
        var prefix: String
        /// The value exactly as written, quotes included.
        var literal: String
        /// Whitespace and any trailing `# comment` after the value.
        var suffix: String

        var raw: String { prefix + literal + suffix }

        /// The value with string quotes removed and escapes resolved.
        var value: String {
            guard literal.hasPrefix("\""), literal.hasSuffix("\""), literal.count >= 2 else { return literal }
            return ConfigDocument.unescape(String(literal.dropFirst().dropLast()))
        }
    }

    enum Line {
        case other(String)                 // blank, comment, or unparseable
        case section(name: String, raw: String)
        case entry(Entry)

        var raw: String {
            switch self {
            case .other(let raw), .section(_, let raw): return raw
            case .entry(let e): return e.raw
            }
        }
    }

    private(set) var lines: [Line] = []
    /// Structural problems: malformed lines and duplicate keys.
    private(set) var issues: [ConfigIssue] = []

    init(text: String) {
        var section = ""
        var seen: Set<String> = []
        // `split(omittingEmptySubsequences: false)` keeps a trailing empty
        // element when the file ends in "\n", so joining with "\n"
        // restores it exactly. A "\r" stays inside its line's raw text.
        for (i, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let raw = String(rawLine)
            let lineNumber = i + 1
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                lines.append(.other(raw))
                continue
            }
            if trimmed.hasPrefix("[") {
                let header = Self.stripComment(trimmed)
                if header.hasSuffix("]"), header.count > 2 {
                    section = String(header.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                    lines.append(.section(name: section, raw: raw))
                } else {
                    issues.append(ConfigIssue(line: lineNumber, message: "can't read section header `\(trimmed)`"))
                    lines.append(.other(raw))
                }
                continue
            }
            guard let entry = Self.parseEntry(raw, section: section, line: lineNumber) else {
                issues.append(ConfigIssue(line: lineNumber, message: "can't read `\(trimmed)` — expected `key = value`"))
                lines.append(.other(raw))
                continue
            }
            let path = Self.path(section, entry.key)
            if !seen.insert(path).inserted {
                issues.append(ConfigIssue(line: lineNumber, message: "`\(path)` is set more than once — the last one wins"))
            }
            lines.append(.entry(entry))
        }
    }

    var text: String { lines.map(\.raw).joined(separator: "\n") }

    /// Every entry in file order. A duplicated key appears more than once;
    /// callers take the last.
    var entries: [Entry] {
        lines.compactMap { if case .entry(let e) = $0 { return e } else { return nil } }
    }

    func entry(section: String, key: String) -> Entry? {
        entries.last { $0.section == section && $0.key == key }
    }

    /// Sets `section.key` to `literal` (already TOML-encoded — see
    /// `ConfigValue`). An existing line keeps its prefix and comment; a
    /// new key goes at the end of its section; a new section goes at the
    /// end of the file.
    mutating func set(section: String, key: String, literal: String) {
        if let idx = lines.lastIndex(where: { if case .entry(let e) = $0 { e.section == section && e.key == key } else { false } }),
           case .entry(var e) = lines[idx] {
            // Keep a trailing comment's column where the old value allows it.
            let oldWidth = e.literal.count
            e.literal = literal
            if e.suffix.contains("#") {
                let padding = e.suffix.prefix { $0 == " " || $0 == "\t" }.count
                let rest = e.suffix.drop { $0 == " " || $0 == "\t" }
                e.suffix = String(repeating: " ", count: max(1, padding + oldWidth - literal.count)) + rest
            }
            lines[idx] = .entry(e)
            return
        }

        let newEntry = Entry(section: section, key: key, line: 0, prefix: "\(key) = ", literal: literal, suffix: "")
        if let insertAt = insertionIndex(forSection: section) {
            lines.insert(.entry(newEntry), at: insertAt)
            return
        }

        // Section doesn't exist yet: append it, separated by one blank line.
        while case .other(let raw)? = lines.last, raw.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        if !lines.isEmpty { lines.append(.other("")) }
        lines.append(.section(name: section, raw: "[\(section)]"))
        lines.append(.entry(newEntry))
        lines.append(.other("")) // keep the file ending in a newline
    }

    /// Just after the last non-blank line belonging to `section`, or nil
    /// if the section has no header (root keys always have a place: the
    /// top of the file, before the first header).
    private func insertionIndex(forSection section: String) -> Int? {
        var current = ""
        var start: Int? = section.isEmpty ? 0 : nil
        var lastContent: Int?
        for (i, line) in lines.enumerated() {
            if case .section(let name, _) = line {
                if current == section, start != nil { break }
                current = name
                if name == section { start = i + 1; lastContent = i }
                continue
            }
            guard current == section, start != nil else { continue }
            if case .other(let raw) = line, raw.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            lastContent = i
        }
        guard let start else { return nil }
        return lastContent.map { $0 + 1 } ?? start
    }

    // MARK: - Lexing

    static func path(_ section: String, _ key: String) -> String {
        section.isEmpty ? key : "\(section).\(key)"
    }

    private static let bareKeyChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")

    private static func parseEntry(_ raw: String, section: String, line: Int) -> Entry? {
        guard let eq = raw.firstIndex(of: "=") else { return nil }
        let key = raw[raw.startIndex..<eq].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, key.unicodeScalars.allSatisfy(bareKeyChars.contains) else { return nil }

        var valueStart = raw.index(after: eq)
        while valueStart < raw.endIndex, raw[valueStart] == " " || raw[valueStart] == "\t" {
            valueStart = raw.index(after: valueStart)
        }
        let rest = raw[valueStart...]
        let literalEnd: String.Index
        if rest.first == "\"" {
            guard let close = closingQuote(in: rest) else { return nil }
            literalEnd = raw.index(after: close)
        } else {
            let hash = rest.firstIndex(of: "#") ?? raw.endIndex
            var end = hash
            while end > valueStart, raw[raw.index(before: end)].isWhitespace { end = raw.index(before: end) }
            literalEnd = end
        }
        guard literalEnd > valueStart else { return nil }
        let suffix = raw[literalEnd...]
        // Anything after the value other than whitespace must be a comment.
        let afterValue = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard afterValue.isEmpty || afterValue.hasPrefix("#") else { return nil }

        return Entry(
            section: section, key: key, line: line,
            prefix: String(raw[..<valueStart]),
            literal: String(raw[valueStart..<literalEnd]),
            suffix: String(suffix)
        )
    }

    /// Index of the `"` closing the string that opens at `s.startIndex`.
    private static func closingQuote(in s: Substring) -> String.Index? {
        var i = s.index(after: s.startIndex)
        while i < s.endIndex {
            if s[i] == "\\" {
                i = s.index(after: i)
                if i < s.endIndex { i = s.index(after: i) }
                continue
            }
            if s[i] == "\"" { return i }
            i = s.index(after: i)
        }
        return nil
    }

    private static func stripComment(_ s: String) -> String {
        guard let hash = s.firstIndex(of: "#") else { return s }
        return s[..<hash].trimmingCharacters(in: .whitespaces)
    }

    static func unescape(_ s: String) -> String {
        guard s.contains("\\") else { return s }
        var out = ""
        var escaping = false
        for c in s {
            if escaping {
                switch c {
                case "n": out.append("\n")
                case "t": out.append("\t")
                default: out.append(c)
                }
                escaping = false
            } else if c == "\\" {
                escaping = true
            } else {
                out.append(c)
            }
        }
        return out
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}

/// A typed value to write back into `config.toml`.
enum ConfigValue: Equatable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)

    var literal: String {
        switch self {
        case .string(let s): return "\"\(ConfigDocument.escape(s))\""
        case .bool(let b): return b ? "true" : "false"
        case .int(let i): return String(i)
        case .double(let d):
            return d.rounded() == d && abs(d) < 1e15 ? String(Int(d)) : String(d)
        }
    }
}
