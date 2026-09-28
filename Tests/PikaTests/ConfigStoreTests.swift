import Foundation
import Testing
@testable import Pika

@MainActor @Suite(.serialized) struct ConfigStoreTests {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("pika-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func settle() async throws { try await Task.sleep(for: .milliseconds(400)) }

    @Test func createsDefaultFileWhenMissing() throws {
        let url = dir.appendingPathComponent("config.toml")
        let store = ConfigStore(fileURL: url)
        #expect(try String(contentsOf: url, encoding: .utf8) == Config.defaultText)
        #expect(store.config == Config())
        #expect(store.issues.isEmpty)
    }

    @Test func setWritesOnlyThatValueAndNotifies() throws {
        let url = dir.appendingPathComponent("config.toml")
        let store = ConfigStore(fileURL: url)
        var seen: [CGFloat] = []
        store.observe { _, new in seen.append(new.fontSize) }
        try store.set(section: "appearance", key: "font_size", to: .int(15))
        let expected = Config.defaultText.replacingOccurrences(of: "font_size    = 13 ", with: "font_size    = 15 ")
        #expect(try String(contentsOf: url, encoding: .utf8) == expected)
        #expect(seen == [15])
    }

    @Test func picksUpInPlaceAndAtomicEdits() async throws {
        let url = dir.appendingPathComponent("config.toml")
        let store = ConfigStore(fileURL: url)
        store.startWatching()
        var rows: [Int] = []
        store.observe { _, new in rows.append(new.maxRows) }

        // In-place write, as `echo >` or vim with backupcopy=yes would do.
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data(Config.defaultText.replacingOccurrences(of: "max_rows     = 10", with: "max_rows     = 12").utf8))
        try handle.close()
        try await settle()
        #expect(rows == [12])

        // Atomic replace, as most editors save.
        try Config.defaultText.replacingOccurrences(of: "max_rows     = 10", with: "max_rows     = 20")
            .write(to: url, atomically: true, encoding: .utf8)
        try await settle()
        #expect(rows == [12, 20])

        // And again, so the file watcher is known to follow the new inode.
        try Config.defaultText.replacingOccurrences(of: "max_rows     = 10", with: "max_rows     = 5 junk")
            .write(to: url, atomically: true, encoding: .utf8)
        try await settle()
        #expect(rows == [12, 20, 10])
        #expect(store.issues.count == 1)

        // Our own write doesn't come back as a second notification.
        try store.set(section: "appearance", key: "max_rows", to: .int(7))
        try await settle()
        #expect(rows == [12, 20, 10, 7])
        #expect(store.issues.isEmpty)
    }

    @Test func writesThroughSymlinks() throws {
        let real = dir.appendingPathComponent("dotfiles-config.toml")
        try Config.defaultText.write(to: real, atomically: true, encoding: .utf8)
        let link = dir.appendingPathComponent("config.toml")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let store = ConfigStore(fileURL: link)
        try store.set(section: "sources", key: "chrome_tabs", to: .bool(false))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == real.path)
        #expect(try String(contentsOf: real, encoding: .utf8).contains("chrome_tabs = false"))
    }
}
