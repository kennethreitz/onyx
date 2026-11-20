import Foundation

public enum Fuzzy {
    /// Score one string against a query (higher is better; nil = no match). Backed by
    /// QuickMatch, so tiers, word boundaries and diacritic folding apply here too.
    public static func score(_ query: String, _ candidate: String) -> Int? {
        match(query, candidate)?.score
    }

    /// Every token must match the candidate; returns the summed score and highlight offsets.
    public static func match(_ query: String, _ candidate: String) -> (score: Int, positions: [Int])? {
        let toks = QuickMatch.tokens(query)
        if toks.isEmpty { return (0, []) }
        let k = MatchKey(candidate)
        var total = 0, pos = Set<Int>()
        for t in toks {
            guard let m = QuickMatch.match(t, in: k) else { return nil }
            total += m.score; pos.formUnion(m.positions)
        }
        if toks.count > 1, let m = QuickMatch.match(QuickMatch.fold(query.trimmingCharacters(in: .whitespaces)), in: k, minTier: .boundary) {
            total += m.tier.rawValue * 1000; pos = Set(m.positions)
        }
        return (total - k.text.count / 8, pos.sorted())
    }
}
