import Foundation
import os

private let log = Logger(subsystem: "io.github.tiagowright.pika", category: "config")

/// The one live copy of Pika's settings (SETTINGS.md §1.4). Replaces the
/// separate `Config.loadOrCreateDefault()` calls the panel and the app
/// delegate used to make. `config.toml` stays the source of truth:
/// `set` writes the file, and edits made to the file by hand are picked
/// up by a watcher and pushed to observers.
///
/// Main thread only.
final class ConfigStore {
    static let shared = ConfigStore()

    private(set) var config = Config()
    private(set) var issues: [ConfigIssue] = []

    /// Where the file is (or would be). Writes go to the symlink's target,
    /// so a dotfiles-managed config stays a symlink.
    let fileURL: URL
    private var document = ConfigDocument(text: Config.defaultText)
    private var observers: [(_ old: Config, _ new: Config) -> Void] = []
    private var issueObservers: [([ConfigIssue]) -> Void] = []

    private var fileSource: DispatchSourceFileSystemObject?
    private var dirSource: DispatchSourceFileSystemObject?
    private var pendingReload: DispatchWorkItem?

    /// Internal rather than private so tests can point it at a temp file.
    init(fileURL: URL = AppPaths.configDirectory.appendingPathComponent("config.toml")) {
        self.fileURL = fileURL
        load(createIfMissing: true)
    }

    private var resolvedURL: URL { fileURL.resolvingSymlinksInPath() }

    // MARK: - Observing

    /// Called on every change to the parsed config, from `set` or from
    /// an edit to the file. Not called if a reload changes nothing.
    func observe(_ handler: @escaping (_ old: Config, _ new: Config) -> Void) {
        observers.append(handler)
    }

    /// Called whenever the set of reported problems changes.
    func observeIssues(_ handler: @escaping ([ConfigIssue]) -> Void) {
        issueObservers.append(handler)
    }

    // MARK: - Writing

    /// Sets one key and writes the file, preserving everything else in it.
    func set(section: String, key: String, to value: ConfigValue) throws {
        var doc = document
        doc.set(section: section, key: key, literal: value.literal)
        try write(doc.text)
        apply(doc)
    }

    private func write(_ text: String) throws {
        let url = resolvedURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Reading

    func reload() { load(createIfMissing: false) }

    private func load(createIfMissing: Bool) {
        let url = resolvedURL
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch CocoaError.fileReadNoSuchFile where createIfMissing {
            do { try write(Config.defaultText) } catch {
                log.error("Couldn't create \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            text = Config.defaultText
        } catch CocoaError.fileReadNoSuchFile {
            // Deleted, or mid-way through an editor's save: keep what we
            // have and wait for the next event rather than recreating it
            // underneath the user.
            log.info("config.toml is missing; keeping the current settings")
            return
        } catch {
            publish(issues: [ConfigIssue(line: nil, message: "can't be read (\(error.localizedDescription)) — using defaults")])
            return
        }
        // Our own writes come back through the watcher; skip those.
        guard createIfMissing || text != document.text else { return }
        apply(ConfigDocument(text: text))
    }

    private func apply(_ doc: ConfigDocument) {
        document = doc
        let (newConfig, newIssues) = Config.parse(doc)
        let old = config
        config = newConfig
        publish(issues: newIssues)
        if old != newConfig {
            observers.forEach { $0(old, newConfig) }
        }
    }

    private func publish(issues newIssues: [ConfigIssue]) {
        guard newIssues != issues else { return }
        issues = newIssues
        for issue in newIssues {
            log.error("\(issue.description, privacy: .public)")
        }
        issueObservers.forEach { $0(newIssues) }
    }

    // MARK: - Watching

    /// Watches the file (for in-place writes) and its directory (for the
    /// atomic save most editors do, which swaps in a new file and leaves
    /// a watcher on the old one deaf).
    func startWatching() {
        guard dirSource == nil else { return }
        dirSource = makeSource(path: resolvedURL.deletingLastPathComponent().path, events: [.write, .rename, .delete])
        armFileSource()
    }

    private func armFileSource() {
        fileSource?.cancel()
        fileSource = makeSource(path: resolvedURL.path, events: [.write, .extend, .delete, .rename])
    }

    private func makeSource(path: String, events: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: events, queue: .main)
        source.setEventHandler { [weak self] in self?.scheduleReload() }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    /// Editors save in bursts (truncate, write, rename, chmod); wait for
    /// them to settle before reading.
    private func scheduleReload() {
        pendingReload?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.armFileSource() // follow the new file if it was replaced
            self.reload()
        }
        pendingReload = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }
}
