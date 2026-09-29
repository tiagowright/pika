import Foundation
import Testing
@testable import Pika

@Suite struct MRUTrimmingTests {
    let now: TimeInterval = 2_000_000_000

    @Test func dropsEntriesOlderThanThirtyDays() {
        let day: TimeInterval = 86_400
        let recency = ["fresh": now - day, "edge": now - 30 * day, "stale": now - 31 * day]
        let kept = MRUStore.pruned(recency, now: now)
        #expect(Set(kept.keys) == ["fresh", "edge"])
    }

    @Test func keepsTheNewestWhenOverTheCap() {
        let recency = Dictionary(uniqueKeysWithValues: (0..<50).map { ("k\($0)", now - TimeInterval($0)) })
        let kept = MRUStore.pruned(recency, now: now, maxEntries: 10)
        #expect(kept.count == 10)
        #expect(Set(kept.keys) == Set((0..<10).map { "k\($0)" }))
    }

    @Test func defaultsMatchTheAgreedLimits() {
        #expect(MRUStore.maxAge == 30 * 86_400)
        #expect(MRUStore.maxEntries == 10_000)
    }
}

@Suite struct LearnedTrimmingTests {
    @Test func decaysAndDropsBelowFloor() {
        let counts = ["zp": ["a": 10.0, "b": 0.1], "x": ["c": 0.1]]
        let out = LearnedStore.decayed(counts, factor: 0.98)
        #expect(abs((out["zp"]?["a"] ?? 0) - 9.8) < 1e-9)
        #expect(out["zp"]?["b"] == nil)   // 0.098 < 0.1
        #expect(out["x"] == nil)          // emptied queries go too
    }

    @Test func thirtyDaysOfDecayCompounds() {
        let out = LearnedStore.decayed(["q": ["a": 1.0]], factor: pow(LearnedStore.dailyDecay, 30))
        #expect(abs((out["q"]?["a"] ?? 0) - pow(0.98, 30)) < 1e-9)
    }

    @Test func capKeepsQueriesWithTheMostPicks() {
        var counts: [String: [String: Double]] = [:]
        for i in 0..<20 { counts["q\(i)"] = ["t": Double(i), "u": 1] }
        let out = LearnedStore.capped(counts, maxQueries: 5)
        #expect(Set(out.keys) == ["q19", "q18", "q17", "q16", "q15"])
        #expect(LearnedStore.capped(counts, maxQueries: 50).count == 20)
        #expect(LearnedStore.maxQueries == 500)
    }

    @Test func readsTheOldBareFormatAndTheNewOne() throws {
        let legacy = try JSONEncoder().encode(["zp": ["a": 2.0]])
        #expect((try? JSONDecoder().decode(LearnedStore.File.self, from: legacy)) == nil)
        #expect((try JSONDecoder().decode([String: [String: Double]].self, from: legacy))["zp"]?["a"] == 2)
        let current = try JSONEncoder().encode(LearnedStore.File(decayedAt: 5, counts: ["zp": ["a": 2.0]]))
        #expect(try JSONDecoder().decode(LearnedStore.File.self, from: current).decayedAt == 5)
    }
}
