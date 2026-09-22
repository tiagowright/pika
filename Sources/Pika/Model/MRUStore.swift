import Foundation

/// Recency, keyed by (bundleID, title) rather than CGWindowID — window
/// IDs don't survive a restart, titles usually do (TECHNICAL.md §8).
/// In-memory is the source of truth during a session; disk is a
/// debounced snapshot so ordering survives a relaunch.
final class MRUStore {
    static let shared = MRUStore()

    private var lock = NSLock()
    private var recency: [String: TimeInterval] = [:]
    private var writeWorkItem: DispatchWorkItem?
    private let fileURL: URL

    private init() {
        let dir = AppPaths.supportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("mru.json")
        load()
    }

    private func key(for id: TargetID) -> String { "\(id.bundleID)\u{0}\(id.discriminator)" }

    /// Also stores a title-based fallback key so a window that changed
    /// its CGWindowID-derived discriminator (e.g. after a relaunch) can
    /// still recover approximate recency by title.
    func lastFocusedAt(bundleID: String, title: String) -> TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return recency["\(bundleID)\u{0}title:\(title)"] ?? 0
    }

    func touch(id: TargetID, title: String, at time: TimeInterval = Date().timeIntervalSince1970) {
        lock.lock()
        recency[key(for: id)] = time
        recency["\(id.bundleID)\u{0}title:\(title)"] = time
        lock.unlock()
        scheduleSave()
    }

    private func scheduleSave() {
        writeWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.save() }
        writeWorkItem = item
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2, execute: item)
    }

    private func save() {
        lock.lock()
        let snapshot = recency
        lock.unlock()
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: TimeInterval].self, from: data) else { return }
        recency = decoded
    }
}

enum AppPaths {
    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("io.github.tiagowright.pika", isDirectory: true)
    }
    static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("io.github.tiagowright.pika", isDirectory: true)
    }
    static var configDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/pika", isDirectory: true)
    }
}
