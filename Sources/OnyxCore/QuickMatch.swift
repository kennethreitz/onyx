import Foundation

/// The matcher behind ⌘O, the command palette and [[link completion.
///
/// Ranking, per query token, from best to worst:
///   exact  >  prefix  >  word boundary / initials ("hl" → Hebrew Letters, "let" → Hebrew Letters)
///          >  contiguous substring  >  scattered subsequence
/// Matching ignores case and diacritics ("resume" finds Résumé). A multi-token query needs every
/// token to match somewhere (title, an alias, or the folder path) in any order, so
/// "hebrew aleph" finds Knowledge/Hebrew Letters/Aleph. Keys are folded once, up front.
public enum MatchTier: Int, Comparable, Sendable {
    case subsequence = 1, substring, boundary, prefix, exact
    public static func < (a: MatchTier, b: MatchTier) -> Bool { a.rawValue < b.rawValue }
}

/// A string folded for matching, aligned 1:1 with the original's Characters, so match
/// positions double as highlight offsets.
public struct MatchKey: Sendable {
    public let text: String
    let chars: [UInt32]
    let starts: [Bool]          // word starts: string start, after a separator, camelCase, letter↔digit
    let wordStarts: [Int]

    public init(_ s: String) {
        text = s
        var c: [UInt32] = [], raw: [Character] = []
        c.reserveCapacity(s.count); raw.reserveCapacity(s.count)
        for ch in s {
            raw.append(ch)
            if ch.isASCII {
                let v = ch.asciiValue!
                c.append(UInt32(v >= 65 && v <= 90 ? v + 32 : v))
            } else {
                let f = String(ch).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
                c.append(f.unicodeScalars.first?.value ?? ch.unicodeScalars.first!.value)
            }
        }
        chars = c
        var st = [Bool](repeating: false, count: c.count), ws: [Int] = []
        for i in 0..<c.count {
            let cur = raw[i]
            guard cur.isLetter || cur.isNumber else { continue }
            var start = i == 0
            if i > 0 {
                let p = raw[i - 1]
                if !(p.isLetter || p.isNumber) { start = true }
                else if p.isLowercase && cur.isUppercase { start = true }
                else if p.isLetter != cur.isLetter { start = true }
            }
            if start { st[i] = true; ws.append(i) }
        }
        starts = st; wordStarts = ws
    }

    public var isEmpty: Bool { chars.isEmpty }
}

public struct FieldMatch: Sendable {
    public var tier: MatchTier
    public var score: Int          // tier * 1000 + quality (0…999)
    public var positions: [Int]    // Character offsets in the field
}

public enum QuickMatch {
    /// Fold a query token the same way keys are folded.
    public static func fold(_ s: String) -> [UInt32] { MatchKey(s).chars }

    /// Split a query into tokens on whitespace and "/" (so "hebrew/aleph" works like "hebrew aleph").
    public static func tokens(_ q: String) -> [[UInt32]] {
        q.split(whereSeparator: { $0.isWhitespace || $0 == "/" }).map { fold(String($0)) }.filter { !$0.isEmpty }
    }

    /// Best match of one folded token in one field, or nil.
    public static func match(_ t: [UInt32], in k: MatchKey, minTier: MatchTier = .subsequence) -> FieldMatch? {
        let f = k.chars, n = f.count, m = t.count
        guard m > 0, m <= n else { return nil }
        // exact / prefix
        if f.starts(with: t) {
            if m == n { return FieldMatch(tier: .exact, score: 5999, positions: Array(0..<m)) }
            let endsWord = k.starts[m] || !isAlnum(f[m])
            let quality = 880 - min(400, (n - m) * 4) + (endsWord ? 80 : 0)
            if endsWord || minTier > .boundary { return FieldMatch(tier: .prefix, score: 4000 + min(999, quality), positions: Array(0..<m)) }
            // a partial first word: a whole word later on is the better reading ("20" in 2026-11-20)
            if let w = wholeWord(t, k) { return FieldMatch(tier: .prefix, score: 4000 + 965 - min(300, w * 3), positions: Array(w..<(w + m))) }
            return FieldMatch(tier: .prefix, score: 4000 + min(999, quality), positions: Array(0..<m))
        }
        if minTier <= .prefix, let w = wholeWord(t, k) {
            // the token is an entire word of the field: as good as a prefix
            return FieldMatch(tier: .prefix, score: 4000 + 940 - min(300, w * 3) - min(200, (n - m) * 2), positions: Array(w..<(w + m)))
        }
        if minTier > .boundary { return nil }
        // word boundary: the token is a run of word prefixes, in order ("hl", "heblet", "let")
        if let (pos, words, fullWords, skipped) = boundary(t, k) {
            var q = 850 - (words - 1) * 25 - skipped * 12 - min(250, (n - m) * 2) + fullWords * 40
            if pos.first == 0 { q += 50 }
            return FieldMatch(tier: .boundary, score: 3000 + max(0, min(999, q)), positions: pos)
        }
        if minTier > .substring { return nil }
        // contiguous substring
        if let at = find(t, f) {
            let q = 800 - min(300, at * 6) - min(300, (n - m) * 2)
            return FieldMatch(tier: .substring, score: 2000 + max(0, q), positions: Array(at..<(at + m)))
        }
        if minTier > .subsequence { return nil }
        // scattered subsequence: best alignment, rewarding word starts and runs
        if let (pos, q) = subsequence(t, k) {
            return FieldMatch(tier: .subsequence, score: 1000 + max(0, min(999, q)), positions: pos)
        }
        return nil
    }

    /// Offset of a word (after the first) that equals the token exactly.
    static func wholeWord(_ t: [UInt32], _ k: MatchKey) -> Int? {
        let f = k.chars, m = t.count
        for s in k.wordStarts where s > 0 && s + m <= f.count {
            let e = s + m
            guard e == f.count || k.starts[e] || !isAlnum(f[e]) else { continue }
            var j = 0
            while j < m && f[s + j] == t[j] { j += 1 }
            if j == m { return s }
        }
        return nil
    }

    static func find(_ t: [UInt32], _ f: [UInt32]) -> Int? {
        let m = t.count
        guard f.count >= m else { return nil }
        var i = 0
        while i + m <= f.count {
            if f[i] == t[0] {
                var j = 1
                while j < m && f[i + j] == t[j] { j += 1 }
                if j == m { return i }
            }
            i += 1
        }
        return nil
    }

    /// Decompose the token into consecutive chunks, each a prefix of a later word.
    static func boundary(_ t: [UInt32], _ k: MatchKey) -> (positions: [Int], words: Int, fullWords: Int, skipped: Int)? {
        let f = k.chars, ws = k.wordStarts
        var best: ([Int], Int, Int, Int)? = nil
        func wordEnd(_ wi: Int) -> Int {
            var e = ws[wi] + 1
            while e < f.count && !(k.starts[e]) && isAlnum(f[e]) { e += 1 }
            return e
        }
        func go(_ qi: Int, _ wi: Int, _ pos: [Int], _ words: Int, _ full: Int, _ skipped: Int, _ budget: inout Int) {
            if budget <= 0 { return }
            budget -= 1
            if qi == t.count {
                if best == nil || words < best!.1 || (words == best!.1 && skipped < best!.3) { best = (pos, words, full, skipped) }
                return
            }
            var w = wi
            while w < ws.count {
                let s = ws[w], e = wordEnd(w)
                var l = 0
                while qi + l < t.count && s + l < e && f[s + l] == t[qi + l] { l += 1 }
                if l > 0 {
                    // longest chunk first; shorter chunks let later words take over ("hebl" → HEBrew Letters)
                    var take = l
                    while take > 0 {
                        go(qi + take, w + 1, pos + Array(s..<(s + take)), words + 1, full + (take == e - s ? 1 : 0), skipped + (w - wi) * (words > 0 ? 1 : 0), &budget)
                        if best != nil && best!.1 == 1 { return }
                        take -= 1
                    }
                }
                w += 1
            }
        }
        var budget = 400
        go(0, 0, [], 0, 0, 0, &budget)
        return best
    }

    static func isAlnum(_ c: UInt32) -> Bool {
        (c >= 48 && c <= 57) || (c >= 97 && c <= 122) || c > 127
    }

    /// Smith-Waterman-ish DP over (token, field): pick the alignment that maximizes word-start
    /// hits and consecutive runs, minus gaps.
    static func subsequence(_ t: [UInt32], _ k: MatchKey) -> ([Int], Int)? {
        let f = k.chars, n = f.count, m = t.count
        // quick reject
        var qi = 0
        for c in f where qi < m && c == t[qi] { qi += 1 }
        guard qi == m else { return nil }
        let NEG = Int.min / 4
        // score[i][j]: best score with t[i] matched at f[j]
        var score = [Int](repeating: NEG, count: m * n)
        var from = [Int](repeating: -1, count: m * n)
        for i in 0..<m {
            var bestPrev = NEG, bestPrevJ = -1
            for j in 0..<n {
                if i > 0, j > 0 {
                    let p = score[(i - 1) * n + j - 1]
                    // carry the best predecessor strictly left of j, with a gap penalty
                    if p > NEG { let pg = p; if pg > bestPrev { bestPrev = pg; bestPrevJ = j - 1 } }
                }
                guard f[j] == t[i] else { continue }
                var s = 10 + (k.starts[j] ? 30 : 0) + (j == 0 ? 20 : 0)
                if i == 0 { score[j] = s - min(20, j); continue }
                // consecutive with previous match?
                let adj = j > 0 ? score[(i - 1) * n + j - 1] : NEG
                var cand = NEG, cj = -1
                if adj > NEG { cand = adj + s + 25; cj = j - 1 }
                if bestPrev > NEG {
                    let gap = j - bestPrevJ - 1
                    let g = bestPrev + s - min(30, 3 + gap)
                    if g > cand { cand = g; cj = bestPrevJ }
                }
                s = cand
                if cj >= 0 { score[i * n + j] = s; from[i * n + j] = cj }
            }
        }
        var bj = -1, bs = NEG
        for j in 0..<n where score[(m - 1) * n + j] > bs { bs = score[(m - 1) * n + j]; bj = j }
        guard bj >= 0 else { return nil }
        var pos = [Int](repeating: 0, count: m)
        var j = bj
        for i in stride(from: m - 1, through: 0, by: -1) { pos[i] = j; j = from[i * n + j] }
        // reject letters sprinkled at random: two thirds must start a word or continue a run
        var good = 0
        for (i, p) in pos.enumerated() where k.starts[p] || (i > 0 && pos[i - 1] == p - 1) || (i + 1 < m && pos[i + 1] == p + 1) { good += 1 }
        guard good * 3 >= m * 2 else { return nil }
        let quality = 300 + bs * 4 / m - min(200, n - m)
        return (pos, quality)
    }
}

/// One note, pre-folded for ⌘O.
public struct QuickEntry: Sendable {
    public let path: String
    public let name: MatchKey
    public let folder: MatchKey          // "Knowledge/Hebrew Letters"
    public let aliases: [MatchKey]
    public let mtime: Date
    public let dated: Date?              // daily-note style names (2026-11-20) carry their own date
}

public struct QuickHit: Sendable {
    public let entry: QuickEntry
    public let score: Int
    public let nameHits: [Int]
    public let folderHits: [Int]
    public let alias: String?            // the alias that matched, if it beat the title
    public let aliasHits: [Int]
    public let exact: Bool               // the whole query is this note's name (or alias / path)
}

public struct QuickIndex: Sendable {
    public let entries: [QuickEntry]

    public init(_ snap: VaultSnapshot) {
        entries = snap.notes.values.map { n in
            QuickEntry(path: n.path, name: MatchKey(n.name), folder: MatchKey(n.folder), aliases: n.aliases.map(MatchKey.init), mtime: n.mtime, dated: QuickIndex.date(in: n.name))
        }.sorted { $0.path < $1.path }
    }
    public init(entries: [QuickEntry]) { self.entries = entries }

    static let dayFormat: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    public static func date(in name: String) -> Date? {
        guard name.count >= 10, let d = name.first, d.isNumber else { return nil }
        return dayFormat.date(from: String(name.prefix(10)))
    }

    /// Rank notes for a query. `recent` is most-recent-first; it and modification time nudge
    /// ordering within a tier but never lift a worse kind of match over a better one.
    public func search(_ query: String, recent: [String] = [], now: Date = Date(), limit: Int = 60) -> [QuickHit] {
        let toks = QuickMatch.tokens(query)
        guard !toks.isEmpty else { return [] }
        let whole = QuickMatch.fold(query.trimmingCharacters(in: .whitespaces))
        let wholePath = QuickMatch.fold(query.trimmingCharacters(in: .whitespaces).lowercased().hasSuffix(".md") ? String(query.trimmingCharacters(in: .whitespaces).dropLast(3)) : query.trimmingCharacters(in: .whitespaces))
        var rank: [String: Int] = [:]
        for (i, p) in recent.prefix(50).enumerated() { rank[p] = i }
        var hits: [QuickHit] = []
        hits.reserveCapacity(256)
        for e in entries {
            var total = 0
            var nameHits = Set<Int>(), folderHits = Set<Int>(), aliasHits: [Int: Set<Int>] = [:]
            var ok = true
            for t in toks {
                var best = Int.min, kind = 0, pos: [Int] = [], ai = -1
                if let m = QuickMatch.match(t, in: e.name) { best = m.score + 400; kind = 1; pos = m.positions }
                for (i, a) in e.aliases.enumerated() {
                    if let m = QuickMatch.match(t, in: a), m.score + 250 > best { best = m.score + 250; kind = 2; pos = m.positions; ai = i }
                }
                // the folder path only counts for real words, not letters scattered across it
                if let m = QuickMatch.match(t, in: e.folder, minTier: .substring) {
                    let s = m.score * 6 / 10
                    if s > best { best = s; kind = 3; pos = m.positions }
                }
                guard best > Int.min else { ok = false; break }
                total += best
                switch kind {
                case 1: nameHits.formUnion(pos)
                case 2: aliasHits[ai, default: []].formUnion(pos)
                default: folderHits.formUnion(pos)
                }
            }
            guard ok else { continue }
            // the whole query read as one title ("onyx plan", "hebrew letters")
            var exact = false
            if toks.count > 1, let m = QuickMatch.match(whole, in: e.name, minTier: .boundary) {
                total += m.tier.rawValue * 1000; nameHits = Set(m.positions)
                exact = m.tier == .exact
            } else if toks.count == 1, e.name.chars == whole {
                exact = true
            }
            if !exact, e.aliases.contains(where: { $0.chars == whole }) { exact = true }
            if !exact, toks.count > 1 || query.contains("/") {
                let p = MatchKey(e.folder.text.isEmpty ? e.name.text : e.folder.text + "/" + e.name.text)
                if p.chars == wholePath { exact = true; total += 3000 }
            }
            if exact { total += 2000 }
            // recency: opened lately, then edited lately (≤ ~350, well under a tier step)
            if let r = rank[e.path] { total += 250 - r * 5 }
            let age = now.timeIntervalSince(e.mtime) / 86_400
            if age < 30 { total += Int(100 * (1 - max(0, age) / 30)) }
            if let d = e.dated {   // daily notes: newest first, today on top
                let days = abs(now.timeIntervalSince(d)) / 86_400
                total += max(0, 120 - Int(days))
            }
            total -= e.folder.chars.count / 6                       // shallower wins ties
            var best: (Int, Set<Int>)? = nil
            for (i, s) in aliasHits where nameHits.isEmpty { if best == nil || s.count > best!.1.count { best = (i, s) } }
            hits.append(QuickHit(entry: e, score: total, nameHits: nameHits.sorted(), folderHits: folderHits.sorted(),
                                 alias: best.map { e.aliases[$0.0].text }, aliasHits: best.map { $0.1.sorted() } ?? [], exact: exact))
        }
        hits.sort { $0.score != $1.score ? $0.score > $1.score : $0.entry.path < $1.entry.path }
        return Array(hits.prefix(limit))
    }

    /// Whether some note is already named exactly this (case/diacritic-insensitive), or lives at this path.
    public func hasExact(_ query: String) -> Bool {
        var q = query.trimmingCharacters(in: .whitespaces)
        if q.lowercased().hasSuffix(".md") { q = String(q.dropLast(3)) }
        let f = QuickMatch.fold(q)
        guard !f.isEmpty else { return true }
        if q.contains("/") {
            return entries.contains { MatchKey($0.folder.text.isEmpty ? $0.name.text : $0.folder.text + "/" + $0.name.text).chars == f }
        }
        return entries.contains { $0.name.chars == f }
    }
}
