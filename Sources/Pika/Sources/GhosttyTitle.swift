import ApplicationServices

/// Ghostty-specific title cleanup, per the decision in TECHNICAL.md.
///
/// Ghostty's window titles are the raw shell/tab title: a running
/// command ("kiro-cli chat --model ...") or a path
/// ("…/Technical Advisor/Nile/wiki"). Two problems observed on this
/// machine's actual windows:
///
///   1. Several Ghostty windows can share the *exact same* title (e.g.
///      four windows all running the same `kiro-cli` command), which
///      makes them indistinguishable in the list.
///   2. Titles sometimes carry a leading decorative/status glyph
///      (spinner, bell) that isn't useful text to match against and
///      would otherwise get counted as a spurious "word".
///
/// Ghostty's AppleScript dictionary exposes no extra properties beyond
/// the standard `name of window` (confirmed via `sdef`), so there's no
/// cwd to query directly. This does the two things that are actually
/// achievable from the title text alone:
///
///   - Strip a leading run of non-alphanumeric symbols.
///   - If AXDocument/AXURL is present (some terminals do set it to a
///     file:// cwd even without exposing it via AppleScript), prefer its
///     last path component as a *prefix* to the title, so it's both
///     visible and gets the app-name-adjacent word-start bonus.
///   - Disambiguate exact-duplicate titles among Ghostty windows with a
///     " · N" suffix, using stacking order, so `Enter` after typing
///     enough to narrow to Ghostty always has distinguishable rows.
///
/// Generic word-boundary matching already treats `/` as a separator
/// (Target.swift), so path segments inside a title are already
/// individually matchable — this only handles what's genuinely specific
/// to Ghostty's output.
enum GhosttyTitle {
    static let bundleID = "com.mitchellh.ghostty"

    static func documentBasename(for window: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXDocumentAttribute as CFString, &value) == .success,
              let urlString = value as? String else { return nil }
        guard let url = URL(string: urlString) else { return nil }
        let name = url.lastPathComponent
        return name.isEmpty ? nil : name
    }

    private static func stripLeadingSymbols(_ title: String) -> String {
        var s = Substring(title)
        while let first = s.first, !(first.isLetter || first.isNumber) {
            s.removeFirst()
        }
        return s.isEmpty ? title : String(s)
    }

    /// Cleans one title. Disambiguation across sibling windows happens
    /// separately in `disambiguate`, since it needs the full set.
    static func clean(title: String, window: AXUIElement) -> String {
        var cleaned = stripLeadingSymbols(title)
        if let doc = documentBasename(for: window), !cleaned.contains(doc) {
            cleaned = "\(doc) — \(cleaned)"
        }
        return cleaned
    }

    /// Appends " · 2", " · 3", ... to exact-duplicate titles within the
    /// same app, in stable (stacking) order, so otherwise-identical rows
    /// stay individually selectable.
    static func disambiguate(_ titles: [String]) -> [String] {
        var seenCount: [String: Int] = [:]
        var result: [String] = []
        result.reserveCapacity(titles.count)
        for t in titles {
            let n = (seenCount[t] ?? 0) + 1
            seenCount[t] = n
            result.append(n == 1 ? t : "\(t) · \(n)")
        }
        return result
    }
}
