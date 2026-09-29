import Foundation

/// Persists (normalized query -> target key -> count) so a short query
/// can learn to prefer the target you actually pick, per UX.md "It
/// learns" and TECHNICAL.md §7. Loaded fully into memory at launch —
/// no file I/O on the hot path.
final class LearnedStore {
    static let shared = LearnedStore()

    private var lock = NSLock()
    private var counts: [String: [String: Double]] = [:] // query -> targetKey -> count
    /// When decay last ran. Decay is by elapsed days, not by launches, so a
    /// Pika left running for weeks still forgets (and frequent relaunches
    /// don't forget faster).
    private var decayedAt = Date().timeIntervalSince1970

    /// 2% a day, dropping a pick once it falls below 0.1: an abandoned
    /// query fades out over a few months without any manual cleanup.
    static let dailyDecay = 0.98
    static let floor = 0.1
    /// Bound on learned.json: the queries with the most picks survive.
    static let maxQueries = 500
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
        decayIfDue()
        let key = targetKey(id)
        lock.lock()
        var perQuery = counts[query] ?? [:]
        perQuery[key, default: 0] += 1
        counts[query] = perQuery
        lock.unlock()
        scheduleSave()
    }

    /// Applies one step of decay per whole day since the last run, so
    /// abandoned projects stop hijacking their letters (TECHNICAL.md §7).
    /// Called at launch and whenever a pick is recorded.
    func decayIfDue(now: TimeInterval = Date().timeIntervalSince1970) {
        lock.lock()
        let days = Int((now - decayedAt) / 86_400)
        guard days >= 1 else { lock.unlock(); return }
        counts = Self.decayed(counts, factor: pow(Self.dailyDecay, Double(days)))
        decayedAt += Double(days) * 86_400
        lock.unlock()
        scheduleSave()
    }

    static func decayed(_ counts: [String: [String: Double]], factor: Double, floor: Double = floor) -> [String: [String: Double]] {
        var result: [String: [String: Double]] = [:]
        for (q, entries) in counts {
            var kept: [String: Double] = [:]
            for (k, v) in entries where v * factor >= floor { kept[k] = v * factor }
            if !kept.isEmpty { result[q] = kept }
        }
        return result
    }

    /// Keeps the `maxQueries` queries with the most picks.
    static func capped(_ counts: [String: [String: Double]], maxQueries: Int = maxQueries) -> [String: [String: Double]] {
        guard counts.count > maxQueries else { return counts }
        let totals: [String: Double] = counts.mapValues { $0.values.reduce(0, +) }
        let ranked: [String] = totals.keys.sorted { a, b in
            let (ta, tb) = (totals[a]!, totals[b]!)
            return ta != tb ? ta > tb : a < b
        }
        var kept: [String: [String: Double]] = [:]
        for query in ranked.prefix(maxQueries) { kept[query] = counts[query] }
        return kept
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

    /// On-disk shape. Before daily decay, learned.json was the bare
    /// `counts` dictionary; `load` still reads that.
    struct File: Codable {
        var decayedAt: TimeInterval
        var counts: [String: [String: Double]]
    }

    private func save() {
        lock.lock()
        counts = Self.capped(counts)
        let snapshot = File(decayedAt: decayedAt, counts: counts)
        lock.unlock()
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let file = try? JSONDecoder().decode(File.self, from: data) {
            counts = Self.capped(file.counts)
            decayedAt = file.decayedAt
        } else if let legacy = try? JSONDecoder().decode([String: [String: Double]].self, from: data) {
            counts = Self.capped(legacy) // decay clock starts now
        }
    }
}
