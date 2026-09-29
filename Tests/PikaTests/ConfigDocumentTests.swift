import Testing
@testable import Pika

@Suite struct ConfigDocumentTests {
    static let sample = """
    # top comment
    hotkey = "ctrl+space"   # the hotkey

    [appearance]
    theme        = "catppuccin-mocha"
    font_size    = 13            # 9–24
    title = "has # inside"  # real comment

    [ranking]
    learning = true
    unknown_key = 5

    """

    @Test func roundTripsByteForByte() {
        for text in [Self.sample, Config.defaultText, "", "a = 1", "a = 1\n\n\n", "x = 1\r\ny = 2\r\n", "  weird line\n[bad"] {
            #expect(ConfigDocument(text: text).text == text)
        }
    }

    @Test func setReplacesOnlyTheValueAndKeepsCommentColumn() {
        var doc = ConfigDocument(text: Self.sample)
        doc.set(section: "appearance", key: "font_size", literal: "15")
        #expect(doc.text.contains("font_size    = 15            # 9–24"))
        doc.set(section: "appearance", key: "font_size", literal: "13")
        #expect(doc.text == Self.sample)

        // A value longer than the gap pushes the comment right, one space
        // after the value; the old column can't be recovered afterwards.
        doc.set(section: "appearance", key: "font_size", literal: "123456789012345678")
        #expect(doc.text.contains("font_size    = 123456789012345678 # 9–24"))
    }

    @Test func setQuotedStringsWithHashes() {
        var doc = ConfigDocument(text: Self.sample)
        #expect(doc.entry(section: "appearance", key: "title")?.value == "has # inside")
        doc.set(section: "appearance", key: "theme", literal: ConfigValue.string("a \"q\"").literal)
        #expect(ConfigDocument(text: doc.text).entry(section: "appearance", key: "theme")?.value == "a \"q\"")
    }

    @Test func newKeyGoesAtEndOfItsSection() {
        var doc = ConfigDocument(text: Self.sample)
        doc.set(section: "appearance", key: "width", literal: "700")
        #expect(doc.text.contains("title = \"has # inside\"  # real comment\nwidth = 700\n\n[ranking]"))
    }

    @Test func newRootKeyGoesBeforeFirstSection() {
        var doc = ConfigDocument(text: "[a]\nx = 1\n")
        doc.set(section: "", key: "hotkey", literal: "\"cmd+k\"")
        #expect(doc.text == "hotkey = \"cmd+k\"\n[a]\nx = 1\n")

        var doc2 = ConfigDocument(text: Self.sample)
        doc2.set(section: "", key: "other", literal: "1")
        #expect(doc2.text.hasPrefix("# top comment\nhotkey = \"ctrl+space\"   # the hotkey\nother = 1\n\n[appearance]"))
    }

    @Test func newSectionIsAppended() {
        var doc = ConfigDocument(text: Self.sample)
        doc.set(section: "sources", key: "chrome_tabs", literal: "false")
        #expect(doc.text.hasSuffix("unknown_key = 5\n\n[sources]\nchrome_tabs = false\n"))
        doc.set(section: "sources", key: "chrome_tabs", literal: "true")
        #expect(doc.text.hasSuffix("[sources]\nchrome_tabs = true\n"))

        var empty = ConfigDocument(text: "")
        empty.set(section: "a", key: "b", literal: "1")
        #expect(empty.text == "[a]\nb = 1\n")
    }

    @Test func duplicatesAndMalformedLinesAreReported() {
        let doc = ConfigDocument(text: "a = 1\na = 2\n[oops\nnot a key value\nb = \"unterminated\nc = \"x\" junk\n")
        #expect(doc.issues.map(\.line) == [2, 3, 4, 5, 6])
        #expect(doc.entry(section: "", key: "a")?.literal == "2")
    }
}

@Suite struct ConfigParseTests {
    @Test func defaultTextHasNoIssues() {
        let (cfg, issues) = Config.parse(ConfigDocument(text: Config.defaultText))
        #expect(issues.isEmpty)
        #expect(cfg == Config())
    }

    @Test func valuesAreApplied() {
        let (cfg, issues) = Config.parse(ConfigDocument(text: """
        hotkey = "cmd+shift+k"
        [appearance]
        font_size = 15
        max_rows = 12
        [sources]
        chrome_tabs = false
        """))
        #expect(issues.isEmpty)
        #expect(cfg.hotkey == "cmd+shift+k")
        #expect(cfg.fontSize == 15 && cfg.inputFontSize == 17)
        #expect(cfg.maxRows == 12)
        #expect(cfg.chromeTabs == false)
    }

    @Test func problemsAreReportedAndDefaultsKept() {
        let (cfg, issues) = Config.parse(ConfigDocument(text: """
        hotkey = "k"
        [appearance]
        font = "JetBrains Mono"
        font_size = 200
        show_icons = yes
        width = 700 wide
        colour = "red"
        [nope]
        x = 1
        """))
        #expect(issues.map(\.line) == [1, 3, 4, 5, 6, 7, 9])
        #expect(cfg == Config())
        #expect(issues[0].message.contains("needs at least one of ctrl, cmd, or alt"))
        #expect(issues[1].message.contains("ignored"))
        #expect(issues[2].message.contains("outside 9–24"))
        #expect(issues[4].message.contains("should be a number"))
        #expect(issues[6].message.contains("unknown section `[nope]`"))
    }

    @Test func hotkeyParsing() {
        #expect((try? Config.parseHotkey("ctrl+space").get()) != nil)
        #expect((try? Config.parseHotkey("Alt + Space").get()) != nil)
        #expect((try? Config.parseHotkey("hyper+space").get()) == nil)
        #expect((try? Config.parseHotkey("ctrl+f13").get()) == nil)
        #expect((try? Config.parseHotkey("shift+a").get()) == nil)
    }
}

@Suite struct HotkeyStringTests {
    @Test func roundTripsThroughParse() throws {
        for (code, cmd, ctrl, opt, shift) in [(UInt32(49), false, true, false, false), (40, true, false, false, true), (122, false, true, true, false), (42, true, false, false, false)] {
            let s = try #require(Config.hotkeyString(keyCode: code, command: cmd, control: ctrl, option: opt, shift: shift))
            let parsed = try Config.parseHotkey(s).get()
            #expect(parsed.keyCode == code, "\(s)")
        }
        #expect(Config.hotkeyString(keyCode: 49, command: false, control: true, option: false, shift: false) == "ctrl+space")
        #expect(Config.hotkeyString(keyCode: 40, command: true, control: false, option: false, shift: true) == "shift+cmd+k")
        #expect(Config.hotkeyString(keyCode: 999, command: true, control: false, option: false, shift: false) == nil)
    }
}
