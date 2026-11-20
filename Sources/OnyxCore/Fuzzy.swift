import Foundation

public enum Fuzzy {
    /// Subsequence fuzzy score. Higher is better; nil means no match.
    public static func score(_ query: String, _ candidate: String) -> Int? {
        let q = Array(query.lowercased().filter { $0 != " " })
        if q.isEmpty { return 0 }
        let c = Array(candidate.lowercased())
        var qi = 0, score = 0, streak = 0, lastMatch = -2
        for (ci, ch) in c.enumerated() where qi < q.count {
            if ch == q[qi] {
                var bonus = 1
                if ci == lastMatch + 1 { streak += 1; bonus += streak * 3 } else { streak = 0 }
                if ci == 0 { bonus += 8 }
                else { let prev = c[ci - 1]; if prev == " " || prev == "/" || prev == "-" || prev == "_" || prev == "." { bonus += 6 } }
                score += bonus
                lastMatch = ci
                qi += 1
            }
        }
        guard qi == q.count else { return nil }
        if candidate.lowercased().hasPrefix(query.lowercased()) { score += 25 }
        if candidate.lowercased() == query.lowercased() { score += 50 }
        return score - c.count / 8
    }
}
