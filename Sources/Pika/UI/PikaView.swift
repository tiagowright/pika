import AppKit

/// The entire panel — input row + result rows — as one hand-drawn view.
/// TECHNICAL.md §9 argues for AppKit over SwiftUI here specifically
/// because a keystroke-driven list needs a *bounded* redraw cost, and a
/// single `draw(_:)` over ≤10 fixed-height rows gives that for free.
final class PikaView: NSView {
    let config: Config
    private var query: String = ""
    private var results: [ScoredTarget] = []
    private var selectedID: TargetID?
    private var lastNonEmptyQuery: String = ""
    private var lastCandidates: [Target] = [] // for incremental narrowing, see FuzzyMatcher.isExtension

    private let inputRowHeight: CGFloat = 40
    private let rowHeight: CGFloat = 26
    private let horizontalPadding: CGFloat = 14
    private let iconSize: CGFloat = 16
    private let appColumnWidth: CGFloat = 120

    var onEnter: ((Target) -> Void)?
    var onDismiss: (() -> Void)?

    init(config: Config) {
        self.config = config
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    var contentHeight: CGFloat {
        let rows = max(1, min(results.count, config.maxRows))
        return inputRowHeight + CGFloat(rows) * rowHeight
    }

    // MARK: - Public control

    /// Called every time the panel opens. Resets to the empty-query MRU
    /// state per UX.md §3 S1, with the current window excluded.
    func reset() {
        query = ""
        lastNonEmptyQuery = ""
        lastCandidates = []
        recomputeResults(preserveSelection: false)
    }

    /// Re-runs matching against whatever the index currently holds,
    /// without disturbing the selection if the selected target still
    /// exists (UX.md §9: "fill-in never moves your selection").
    func refresh() {
        recomputeResults(preserveSelection: true)
    }

    // MARK: - Matching

    private func excludedCurrentID() -> TargetID? {
        config.includeCurrent ? nil : WindowSource.shared.currentFrontmostID
    }

    private func recomputeResults(preserveSelection: Bool) {
        let excluded = excludedCurrentID()
        let allTargets = IndexStore.shared.targets.filter { $0.id != excluded }

        // Matching is monotone in query length (TECHNICAL.md §7): if a
        // target didn't match "zp" it can't match "zpi", so extending
        // the previous query only ever needs to re-scan its own surviving
        // candidates, not the whole index.
        let candidatePool: [Target] = (!query.isEmpty && FuzzyMatcher.isExtension(of: lastNonEmptyQuery, query: query))
            ? lastCandidates
            : allTargets

        var weights = FuzzyMatcher.Weights()
        weights.recencyWeight = config.recencyWeight
        weights.learnWeight = config.learning ? config.learnWeight : 0

        let now = Date().timeIntervalSince1970
        let scored = FuzzyMatcher.rank(
            targets: candidatePool,
            query: query,
            weights: weights,
            now: now,
            learnedBonus: { LearnedStore.shared.bonus(query: self.query, id: $0) }
        )

        if !query.isEmpty {
            lastNonEmptyQuery = query
            lastCandidates = scored.map { $0.target }
        }

        let previousID = selectedID
        results = scored

        if preserveSelection, let previousID, results.contains(where: { $0.target.id == previousID }) {
            selectedID = previousID
        } else {
            selectedID = results.first?.target.id
        }

        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    private var selectedIndex: Int {
        guard let selectedID else { return 0 }
        return results.firstIndex { $0.target.id == selectedID } ?? 0
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isControl = flags.contains(.control) && !flags.contains(.command) && !flags.contains(.option)
        let isCommand = flags.contains(.command) && !flags.contains(.control) && !flags.contains(.option)
        let isOption = flags.contains(.option) && !flags.contains(.control) && !flags.contains(.command)

        // Delete/Backspace with a modifier: since the query has no
        // interior cursor (arrows navigate rows, not text — see UX.md
        // §4), "delete to start of line" and "delete previous word" both
        // collapse to the same edits as their terminal-style Ctrl
        // equivalents below. Bound here too because Cmd+Delete and
        // Option+Delete are the standard macOS text-field muscle memory,
        // and the brief asked for both to work side by side.
        if event.keyCode == 51 {
            if isCommand { query = ""; recomputeResults(preserveSelection: false); return }
            if isOption { deleteLastWord(); return }
            if flags.isEmpty {
                if !query.isEmpty { query.removeLast(); recomputeResults(preserveSelection: false) }
                return
            }
        }

        switch event.keyCode {
        case 53: // Escape
            onDismiss?()
            return
        case 36: // Return
            if let target = results.first(where: { $0.target.id == selectedID })?.target ?? results.first?.target {
                if !query.isEmpty { LearnedStore.shared.record(query: query, id: target.id) }
                onEnter?(target)
            }
            return
        case 125: // Down
            move(by: 1); return
        case 126: // Up
            move(by: -1); return
        default: break
        }

        if isControl {
            switch event.keyCode {
            case 45: move(by: 1); return   // Ctrl+N
            case 35: move(by: -1); return  // Ctrl+P
            case 13: deleteLastWord(); return // Ctrl+W
            case 32: query = ""; recomputeResults(preserveSelection: false); return // Ctrl+U
            default: return
            }
        }

        guard let chars = event.characters, !chars.isEmpty else { return }
        // Filter out control characters that slipped through (e.g. other
        // Ctrl-combos we don't bind); only accept printable text.
        let printable = chars.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F }
        guard !printable.isEmpty else { return }
        query.append(String(String.UnicodeScalarView(printable)))
        recomputeResults(preserveSelection: false)
    }

    private func deleteLastWord() {
        guard !query.isEmpty else { return }
        while query.last == " " { query.removeLast() }
        while let last = query.last, last != " " { query.removeLast() }
        recomputeResults(preserveSelection: false)
    }

    private func move(by delta: Int) {
        guard !results.isEmpty else { return }
        let newIndex = max(0, min(results.count - 1, selectedIndex + delta)) // clamps — no wraparound, per UX.md §4
        selectedID = results[newIndex].target.id
        needsDisplay = true
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard p.y >= inputRowHeight else { return }
        let visibleStart = scrollOffset()
        let rowIdx = visibleStart + Int((p.y - inputRowHeight) / rowHeight)
        guard rowIdx >= 0, rowIdx < results.count else { return }
        let target = results[rowIdx].target
        if !query.isEmpty { LearnedStore.shared.record(query: query, id: target.id) }
        onEnter?(target)
    }

    /// Keeps the selected row inside the visible window when the list is
    /// longer than `maxRows` — constant-height rows make this arithmetic
    /// rather than a measurement pass (TECHNICAL.md §9).
    private func scrollOffset() -> Int {
        guard results.count > config.maxRows else { return 0 }
        let sel = selectedIndex
        let maxStart = results.count - config.maxRows
        return max(0, min(maxStart, sel - config.maxRows / 2))
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let theme = config.theme
        theme.bg.setFill()
        bounds.fill()

        drawInputRow(theme: theme)

        theme.border.setStroke()
        let dividerY = inputRowHeight
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: dividerY))
        path.line(to: NSPoint(x: bounds.width, y: dividerY))
        path.lineWidth = 1
        path.stroke()

        if results.isEmpty {
            drawEmptyState(theme: theme)
            return
        }

        let start = scrollOffset()
        let visible = results[start..<min(results.count, start + config.maxRows)]
        for (offset, scored) in visible.enumerated() {
            let rowRect = NSRect(x: 0, y: inputRowHeight + CGFloat(offset) * rowHeight, width: bounds.width, height: rowHeight)
            drawRow(scored, in: rowRect, theme: theme, isSelected: scored.target.id == selectedID)
        }
    }

    private func drawInputRow(theme: Theme) {
        let rect = NSRect(x: 0, y: 0, width: bounds.width, height: inputRowHeight)
        theme.bgInput.setFill()
        rect.fill()

        let font = PikaFont.font(size: config.inputFontSize)
        let promptAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: theme.accent]
        let textAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: theme.fg]

        var x = horizontalPadding
        let prompt = "❯ "
        (prompt as NSString).draw(at: NSPoint(x: x, y: (inputRowHeight - font.ascender + font.descender) / 2), withAttributes: promptAttrs)
        x += (prompt as NSString).size(withAttributes: promptAttrs).width

        (query as NSString).draw(at: NSPoint(x: x, y: (inputRowHeight - font.ascender + font.descender) / 2), withAttributes: textAttrs)
        x += (query as NSString).size(withAttributes: textAttrs).width

        // Static block cursor — no blink, per UX.md's "no idle redraws" call.
        let cursorWidth = font.maximumAdvancement.width
        let cursorRect = NSRect(x: x, y: (inputRowHeight - font.pointSize * 1.15) / 2, width: cursorWidth, height: font.pointSize * 1.15)
        theme.accent.withAlphaComponent(0.85).setFill()
        cursorRect.fill()
    }

    /// `NSString.draw(at:)` takes the *top-left* of the string's box, and
    /// this view is flipped (y grows downward) — so centering is just
    /// `rect.minY + (rect.height - lineHeight) / 2` with no separate
    /// descender correction. Getting this wrong (as an earlier version
    /// did, mixing in an extra `- font.descender`) pushes text toward
    /// the bottom of the row instead of centering it against the icon.
    private func centeredTextY(in rect: NSRect, font: NSFont) -> CGFloat {
        rect.minY + (rect.height - (font.ascender - font.descender)) / 2
    }

    private func drawEmptyState(theme: Theme) {
        let font = PikaFont.font(size: config.fontSize)
        let text = "no matching window"
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: theme.fgMuted]
        let rowRect = NSRect(x: 0, y: inputRowHeight, width: bounds.width, height: rowHeight)
        (text as NSString).draw(at: NSPoint(x: horizontalPadding, y: centeredTextY(in: rowRect, font: font)), withAttributes: attrs)
    }

    private func drawRow(_ scored: ScoredTarget, in rect: NSRect, theme: Theme, isSelected: Bool) {
        if isSelected {
            theme.selBg.setFill()
            rect.fill()
            let bar = NSRect(x: 0, y: rect.minY, width: 3, height: rect.height)
            theme.accent.setFill()
            bar.fill()
        }

        let font = PikaFont.font(size: config.fontSize)
        var x = horizontalPadding

        if config.showIcons {
            if let icon = scored.target.icon {
                icon.draw(in: NSRect(x: x, y: rect.minY + (rect.height - iconSize) / 2, width: iconSize, height: iconSize))
            }
            x += iconSize + 8
        }

        let textY = centeredTextY(in: rect, font: font)
        let appColX = x
        drawHighlighted(
            scored.target.appName, matched: matchedInAppName(scored),
            at: NSPoint(x: appColX, y: textY),
            font: font, baseColor: isSelected ? theme.accentAlt : theme.fgDim, highlightColor: theme.accent,
            maxWidth: appColumnWidth - 8
        )

        let titleX = appColX + appColumnWidth
        let recencyText = formatRecency(scored.target.lastFocusedAt)
        let recencyFont = PikaFont.font(size: config.fontSize - 2)
        let recencyWidth = (recencyText as NSString).size(withAttributes: [.font: recencyFont]).width
        let titleMaxWidth = rect.width - titleX - recencyWidth - horizontalPadding - 12

        drawHighlighted(
            scored.target.title, matched: matchedInTitle(scored),
            at: NSPoint(x: titleX, y: textY),
            font: font, baseColor: theme.fg, highlightColor: theme.accent,
            maxWidth: titleMaxWidth
        )

        let recencyAttrs: [NSAttributedString.Key: Any] = [.font: recencyFont, .foregroundColor: theme.fgDim]
        (recencyText as NSString).draw(
            at: NSPoint(x: rect.width - horizontalPadding - recencyWidth, y: centeredTextY(in: rect, font: recencyFont)),
            withAttributes: recencyAttrs
        )
    }

    private func matchedInAppName(_ s: ScoredTarget) -> Set<Int> {
        Set(s.matchedIndices.filter { $0 < s.target.appNameLength })
    }
    private func matchedInTitle(_ s: ScoredTarget) -> Set<Int> {
        let base = s.target.appNameLength + 1
        return Set(s.matchedIndices.filter { $0 >= base }.map { $0 - base })
    }

    /// Middle-truncates long titles keeping head and tail per UX.md §9
    /// ("the tail usually holds the filename"), then draws with matched
    /// byte offsets recolored to the accent.
    private func drawHighlighted(_ text: String, matched: Set<Int>, at point: NSPoint, font: NSFont, baseColor: NSColor, highlightColor: NSColor, maxWidth: CGFloat) {
        guard maxWidth > 0 else { return }
        let attrString = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: baseColor])
        for i in matched where i < text.utf8.count {
            // matched indices are byte offsets into our ASCII-folded haystack;
            // for v1 (US-keyboard, mostly-ASCII titles) this lines up with
            // NSString UTF-16 offsets closely enough for highlighting.
            if i < attrString.length {
                attrString.addAttribute(.foregroundColor, value: highlightColor, range: NSRange(location: i, length: 1))
            }
        }

        var size = attrString.size()
        if size.width > maxWidth {
            let truncated = middleTruncate(text, font: font, maxWidth: maxWidth)
            let fallback = NSAttributedString(string: truncated, attributes: [.font: font, .foregroundColor: baseColor])
            size = fallback.size()
            fallback.draw(at: point)
            return
        }
        attrString.draw(at: point)
    }

    private func middleTruncate(_ text: String, font: NSFont, maxWidth: CGFloat) -> String {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        if (text as NSString).size(withAttributes: attrs).width <= maxWidth { return text }
        let ellipsis = "…"
        var head = ""
        var tail = ""
        let chars = Array(text)
        var i = 0, j = chars.count - 1
        while i <= j {
            let candidate = head + String(chars[i]) + ellipsis + String(chars[j]) + tail
            if (candidate as NSString).size(withAttributes: attrs).width > maxWidth { break }
            head.append(chars[i]); if i != j { tail = String(chars[j]) + tail }
            i += 1; j -= 1
        }
        return head + ellipsis + tail
    }

    private func formatRecency(_ timestamp: TimeInterval) -> String {
        guard timestamp > 0 else { return "" }
        let age = max(0, Date().timeIntervalSince1970 - timestamp)
        switch age {
        case ..<60: return "\(Int(age))s"
        case ..<3600: return "\(Int(age / 60))m"
        case ..<86400: return "\(Int(age / 3600))h"
        default: return "\(Int(age / 86400))d"
        }
    }
}
