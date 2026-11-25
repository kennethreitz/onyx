import Foundation

/// A plain-text occurrence of a note's title or alias that is not already a link.
public struct UnlinkedMention: Hashable, Sendable {
    public var source: String
    public var line: Int
    public var context: String
    /// UTF-16 range of the matched text in the source note.
    public var range: NSRange
    /// The exact characters that matched.
    public var matched: String
    /// The title or alias that was searched for.
    public var needle: String

    public init(source: String, line: Int, context: String, range: NSRange, matched: String, needle: String) {
        self.source = source
        self.line = line
        self.context = context
        self.range = range
        self.matched = matched
        self.needle = needle
    }
}

/// Find and convert unlinked mentions of a note (title and aliases) in other notes.
///
/// Matches are case-insensitive and must sit on word boundaries, so "Note" does
/// not hit "Notebook". Occurrences inside fenced or inline code, comments,
/// frontmatter, wikilinks, or Markdown links are ignored.
public enum UnlinkedMentions {
    public static let minimumLength = 3

    /// Titles and aliases worth searching for, longest first so a longer phrase wins.
    public static func needles(for note: NoteRecord) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        func add(_ raw: String) {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.count >= minimumLength else { return }
            let key = t.lowercased()
            guard seen.insert(key).inserted else { return }
            out.append(t)
        }
        add(note.name)
        add(note.title)
        for a in note.aliases { add(a) }
        return out.sorted { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }
    }

    public static func find(in text: String, source: String, needles: [String]) -> [UnlinkedMention] {
        guard !needles.isEmpty, !text.isEmpty else { return [] }
        let ns = text as NSString
        let skip = skipRanges(in: text)
        var hits: [UnlinkedMention] = []
        var taken = IndexSet()
        let lowered = text.lowercased() as NSString
        for needle in needles {
            let n = needle as NSString
            let nLower = needle.lowercased() as NSString
            var from = 0
            while from < lowered.length {
                let r = lowered.range(of: nLower as String, options: [.literal], range: NSRange(location: from, length: lowered.length - from))
                if r.location == NSNotFound { break }
                from = NSMaxRange(r) > r.location ? NSMaxRange(r) : r.location + 1
                guard wordBoundary(in: ns, range: r) else { continue }
                guard !skip.contains(where: { NSIntersectionRange($0, r).length > 0 }) else { continue }
                let covered = IndexSet(integersIn: r.location..<NSMaxRange(r))
                guard taken.intersection(covered).isEmpty else { continue }
                taken.formUnion(covered)
                let matched = ns.substring(with: r)
                let (line, context) = lineContext(ns, at: r.location)
                hits.append(UnlinkedMention(source: source, line: line, context: context, range: r, matched: matched, needle: n as String))
            }
        }
        return hits.sorted { $0.range.location < $1.range.location }
    }

    public static func find(in snap: VaultSnapshot, of path: String, limit: Int = 200) -> [UnlinkedMention] {
        guard let note = snap.notes[path] else { return [] }
        let keys = needles(for: note)
        guard !keys.isEmpty else { return [] }
        var out: [UnlinkedMention] = []
        for p in snap.sortedNotePaths where p != path {
            guard let other = snap.notes[p] else { continue }
            // Cheap prefilter: any needle in the lowered body.
            let hit = keys.contains { ByteSearch.count($0.lowercased(), in: other.lowered, cap: 1) > 0 }
            guard hit else { continue }
            out.append(contentsOf: find(in: other.content, source: p, needles: keys))
            if out.count >= limit { break }
        }
        if out.count > limit { out = Array(out.prefix(limit)) }
        return out
    }

    /// Wrap one occurrence as a wikilink. Same-looking titles become `[[Title]]`;
    /// other display text (an alias, different casing kept as the alias) becomes `[[Title|text]]`.
    public static func link(_ text: String, range: NSRange, title: String) -> String? {
        let ns = text as NSString
        guard range.location != NSNotFound, range.length > 0, NSMaxRange(range) <= ns.length else { return nil }
        let display = ns.substring(with: range)
        let replacement: String
        if display.compare(title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            replacement = "[[\(title)]]"
        } else {
            replacement = "[[\(title)|\(display)]]"
        }
        return ns.replacingCharacters(in: range, with: replacement)
    }

    /// Convert every mention, right-to-left so earlier ranges stay valid. Mentions
    /// must all come from the same `text`.
    public static func linkAll(_ text: String, mentions: [UnlinkedMention], title: String) -> (text: String, count: Int) {
        var out = text
        var count = 0
        for m in mentions.sorted(by: { $0.range.location > $1.range.location }) {
            if let next = link(out, range: m.range, title: title) {
                out = next
                count += 1
            }
        }
        return (out, count)
    }

    // MARK: - Internals

    static func skipRanges(in text: String) -> [NSRange] {
        let ns = text as NSString
        let all = NSRange(location: 0, length: ns.length)
        var skip = NoteParser.codeRanges(text)
        skip += MarkdownLinks.codeSpan.matches(in: text, range: all).map(\.range)
        skip += MarkdownLinks.comment.matches(in: text, range: all).map(\.range)
        skip += MarkdownLinks.link.matches(in: text, range: all).map(\.range)
        skip += NoteParser.parseWikiLinks(text).map(\.range)
        let fm = Frontmatter.parse(text)
        if fm.bodyOffset > 0 {
            skip.append(NSRange(location: 0, length: min(fm.bodyOffset, ns.length)))
        }
        return skip
    }

    static func wordBoundary(in ns: NSString, range r: NSRange) -> Bool {
        if r.location > 0, isWordChar(ns, at: r.location - 1) { return false }
        let end = NSMaxRange(r)
        if end < ns.length, isWordChar(ns, at: end) { return false }
        return true
    }

    static func isWordChar(_ ns: NSString, at i: Int) -> Bool {
        guard i >= 0, i < ns.length else { return false }
        let seq = ns.rangeOfComposedCharacterSequence(at: i)
        let s = ns.substring(with: seq)
        guard let ch = s.first else { return false }
        if ch == "_" { return true }
        return ch.isLetter || ch.isNumber
    }

    static func lineContext(_ ns: NSString, at location: Int) -> (Int, String) {
        let start = ns.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: min(location, ns.length)))
        let lineStart = start.location == NSNotFound ? 0 : NSMaxRange(start)
        let rest = NSRange(location: lineStart, length: ns.length - lineStart)
        let nl = ns.range(of: "\n", options: [], range: rest)
        let lineEnd = nl.location == NSNotFound ? ns.length : nl.location
        let line = ns.substring(with: NSRange(location: lineStart, length: lineEnd - lineStart))
            .trimmingCharacters(in: .whitespaces)
        let prefix = ns.substring(with: NSRange(location: 0, length: lineStart))
        let number = prefix.reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
        return (number, line)
    }
}
