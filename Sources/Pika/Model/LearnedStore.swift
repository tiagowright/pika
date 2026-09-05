import Foundation

/// Persists (normalized query -> target key -> count) so a short query
/// can learn to prefer the target you actually pick, per UX.md "It
/// learns" and TECHNICAL.md §7. Loaded fully into memory at launch —
/// no file I/O on the hot path.
final class LearnedStore {
    static let shared = LearnedStore()

    private var lock = NSLock()
    private var counts: [String: [String: Double]] = [:] // query -> targetKey -> count
    private let fileURL: URL
    private var writeWorkItem: DispatchWorkItem?

    private init() {
        let dir = AppPaths.supportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("learned.json")
        load()
    }

    private func targetKey(_ id: TargetID) -> String { "\(id.bundleID)\u{0}\(id.discriminator)" }

    /// Bonus for a specific target given the current query, summed over
    /// the query and every prefix of it (so learning "slack" also helps
    /// "s", "sl", "sla" — see UX.md).
    func bonus(query: String, id: TargetID) -> Double {
        guard !query.isEmpty else { return 0 }
        let key = targetKey(id)
        lock.lock(); defer { lock.unlock() }
        var total = 0.0
        var prefix = ""
        for ch in query {
            prefix.append(ch)
            if let c = counts[prefix]?[key], c > 0 {
                total += log2(1 + c)
            }
        }
        return total
    }

    func record(query: String, id: TargetID) {
        guard !query.isEmpty else { return }
        let key = targetKey(id)
        lock.lock()
        var perQuery = counts[query] ?? [:]
        perQuery[key, default: 0] += 1
        counts[query] = perQuery
        lock.unlock()
        scheduleSave()
    }

    /// Slow decay so abandoned projects stop hijacking their letters
    /// after a few weeks, without any manual cleanup. Called once per
    /// launch (see TECHNICAL.md §7).
    func decayAll(factor: Double = 0.98, floor: Double = 0.1) {
        lock.lock()
        for (q, entries) in counts {
            var kept: [String: Double] = [:]
            for (k, v) in entries {
                let decayed = v * factor
                if decayed >= floor { kept[k] = decayed }
            }
            if kept.isEmpty { counts.removeValue(forKey: q) } else { counts[q] = kept }
        }
        lock.unlock()
        scheduleSave()
    }

    func forgetAll() {
        lock.lock(); counts = [:]; lock.unlock()
        scheduleSave()
    }

    private func scheduleSave() {
        writeWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.save() }
        writeWorkItem = item
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2, execute: item)
    }

    private func save() {
        lock.lock(); let snapshot = counts; lock.unlock()
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: [String: Double]].self, from: data) else { return }
        counts = decoded
    }
}
