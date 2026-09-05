import Foundation

/// One scored, matched target ready to render. `matchedIndices` are byte
/// offsets into the target's haystack, used to highlight matched
/// characters per UX.md §6.
struct ScoredTarget {
    let target: Target
    let score: Double
    let matchedIndices: [Int]
}

enum FuzzyMatcher {
    // Tunable weights — see TECHNICAL.md §7 and config.toml [ranking].
    struct Weights {
        var appNameStart: Double = 120
        var titleWordStart: Double = 80
        var appNameAnywhere: Double = 40
        var consecutive: Double = 50
        var caseMatch: Double = 10
        var gapPenalty: Double = -5
        var gapPenaltyCap: Double = -40
        var leadingGapPenalty: Double = -3
        var prefixOfAppName: Double = 100
        var recencyWeight: Double = 40
        var learnWeight: Double = 60
    }

    /// Folds a query character the same way Target.haystack was folded.
    private static func foldQueryByte(_ c: Character) -> UInt8? {
        guard let scalar = c.unicodeScalars.first, c.unicodeScalars.count == 1 else { return nil }
        if scalar.isASCII {
            let v = UInt8(scalar.value)
            if v >= 65 && v <= 90 { return v + 32 }
            return v
        }
        return 0xFF
    }

    /// One AND-separated token of the query, as folded bytes plus a
    /// letter-presence mask for O(1) rejection (TECHNICAL.md §4/§7).
    struct Token {
        let bytes: [UInt8]
        let letterMask: UInt32
    }

    static func tokenize(_ query: String) -> [Token] {
        query.split(separator: " ").map { sub in
            var bytes: [UInt8] = []
            var mask: UInt32 = 0
            for c in sub {
                guard let b = foldQueryByte(c) else { continue }
                bytes.append(b)
                if b >= UInt8(ascii: "a") && b <= UInt8(ascii: "z") {
                    mask |= (1 << UInt32(b - UInt8(ascii: "a")))
                }
            }
            return Token(bytes: bytes, letterMask: mask)
        }
    }

    /// Greedy forward subsequence match of `token` inside `target`,
    /// scoring as it goes. Returns nil if the token isn't a subsequence
    /// at all. This is intentionally the *simple* fzf-style scan, not a
    /// full Smith-Waterman DP: at our target counts (tens to low
    /// thousands of rows) it's already microseconds, and it composes
    /// cleanly with multi-token AND queries.
    private static func matchToken(_ token: Token, in target: Target, weights: Weights) -> (score: Double, indices: [Int])? {
        guard !token.bytes.isEmpty else { return nil }
        // O(1) reject: every letter in the query token must appear somewhere in the haystack.
        if token.letterMask & ~target.letterMask != 0 { return nil }

        var score = 0.0
        var indices: [Int] = []
        indices.reserveCapacity(token.bytes.count)
        var searchFrom = 0
        var lastMatchIndex = -1
        let hay = target.haystack

        for qb in token.bytes {
            var found = -1
            var j = searchFrom
            while j < hay.count {
                if hay[j] == qb { found = j; break }
                j += 1
            }
            guard found >= 0 else { return nil }

            let isWordStart = (found < 64) && (target.wordStartMask & (1 << UInt64(found)) != 0)
            let inAppName = found < target.appNameLength

            if inAppName {
                score += (found == 0) ? weights.appNameStart : weights.appNameAnywhere
            } else if isWordStart {
                score += weights.titleWordStart
            }

            if lastMatchIndex >= 0 {
                let gap = found - lastMatchIndex - 1
                if gap == 0 {
                    score += weights.consecutive
                } else {
                    score += max(weights.gapPenaltyCap, Double(gap) * weights.gapPenalty)
                }
            } else if found > 0 {
                score += max(weights.gapPenaltyCap, Double(found) * weights.leadingGapPenalty)
            }

            indices.append(found)
            lastMatchIndex = found
            searchFrom = found + 1
        }

        // Whole first token is a prefix of the app name.
        if token.bytes.count <= target.appNameLength {
            var isPrefix = true
            for (i, b) in token.bytes.enumerated() where target.haystack[i] != b { isPrefix = false; break }
            if isPrefix { score += weights.prefixOfAppName }
        }

        return (score, indices)
    }

    /// `nowReference` lets recency scoring and tests be deterministic.
    /// `learnedBonus` is looked up by the caller (LearnedStore) per
    /// target id so this file stays free of persistence concerns.
    static func rank(
        targets: [Target],
        query: String,
        weights: Weights,
        now: TimeInterval,
        learnedBonus: (TargetID) -> Double
    ) -> [ScoredTarget] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            // Empty query: pure MRU, per UX.md §3 S1. Caller is responsible
            // for excluding the current window before calling this.
            return targets
                .sorted { $0.lastFocusedAt > $1.lastFocusedAt }
                .map { ScoredTarget(target: $0, score: $0.lastFocusedAt, matchedIndices: []) }
        }

        let tokens = tokenize(trimmed)
        guard !tokens.isEmpty else { return [] }

        var results: [ScoredTarget] = []
        results.reserveCapacity(targets.count)

        for target in targets {
            var total = 0.0
            var allIndices: [Int] = []
            var ok = true
            for token in tokens {
                guard let (s, idx) = matchToken(token, in: target, weights: weights) else { ok = false; break }
                total += s
                allIndices.append(contentsOf: idx)
            }
            guard ok else { continue }

            let ageSeconds = max(0, now - target.lastFocusedAt)
            let recencyBonus = weights.recencyWeight * exp(-ageSeconds / 480.0) // ~8 min half-life-ish decay
            total += recencyBonus
            // learnedBonus(id) returns log2(1+count) from LearnedStore;
            // weights.learnWeight is the only scaling applied here.
            total += weights.learnWeight * learnedBonus(target.id)

            results.append(ScoredTarget(target: target, score: total, matchedIndices: allIndices))
        }

        results.sort { $0.score > $1.score }
        return results
    }

    /// True iff `query` is a subsequence-extension of `previousQuery`
    /// (i.e. previousQuery is a prefix of query). Matching is monotone in
    /// this case — see TECHNICAL.md §7 — so the caller can narrow the
    /// candidate set instead of re-scanning everything.
    static func isExtension(of previousQuery: String, query: String) -> Bool {
        !previousQuery.isEmpty && query.hasPrefix(previousQuery) && query != previousQuery
    }
}
