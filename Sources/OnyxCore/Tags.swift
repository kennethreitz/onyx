import Foundation

// Hierarchical tags, Obsidian-compatible and free of AppKit.
//
// `#parent/child/grandchild` (inline) and `tags:` / `tag:` in frontmatter are the same tag.
// Tags compare case-insensitively (`#Book` and `#book` are one tag); the tree shows the
// spelling used most. Filtering by a tag includes its descendants (Obsidian's `tag:#parent`),
// with an exact-only option. Tags never come from code (fenced or inline), [[links]],
// Markdown link targets, URLs or headings (`# Heading` needs a space, so it never matches).

/// Names, keys and paths.
public enum TagName {
    /// Characters a tag may contain after `#`: letters, numbers, marks, symbols (emoji), `_ - /`.
    static let charClass = #"[\p{L}\p{N}\p{M}\p{So}\p{Sk}_\-/\x{200D}\x{FE0F}]"#

    /// The comparison key: lowercased, without `#` or stray slashes.
    public static func key(_ tag: String) -> String { (normalize(tag) ?? tag).lowercased() }

    /// `#a//b/` → `a/b`; nil when nothing valid remains (or it is all digits, like `#2024`).
    public static func normalize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix("#") { s.removeFirst() }
        let parts = s.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty else { return nil }
        let joined = parts.joined(separator: "/")
        guard isValidBody(joined) else { return nil }
        return joined
    }

    static func isValidBody(_ s: String) -> Bool {
        var nonDigit = false
        for u in s.unicodeScalars {
            if CharacterSet.decimalDigits.contains(u) { continue }
            if u == "/" { continue }
            if u == "_" || u == "-" || u == "\u{200D}" || u == "\u{FE0F}" { nonDigit = true; continue }
            switch u.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                 .nonspacingMark, .spacingMark, .enclosingMark, .otherSymbol, .modifierSymbol,
                 .letterNumber, .otherNumber:
                nonDigit = true
            default: return false
            }
        }
        return nonDigit
    }

    public static func segments(_ tag: String) -> [String] { tag.split(separator: "/").map(String.init) }
    public static func leaf(_ tag: String) -> String { segments(tag).last ?? tag }
    public static func parent(_ tag: String) -> String? {
        guard let i = tag.lastIndex(of: "/") else { return nil }
        return String(tag[..<i])
    }
    /// `a`, `a/b`, `a/b/c` for `a/b/c`.
    public static func ancestry(_ tag: String) -> [String] {
        var out: [String] = [], cur = ""
        for s in segments(tag) { cur = cur.isEmpty ? s : cur + "/" + s; out.append(cur) }
        return out
    }

    /// Whether `tag` is `filter` or nested under it (case-insensitive).
    public static func matches(_ tag: String, filter: String, exact: Bool = false) -> Bool {
        let t = key(tag), f = key(filter)
        return t == f || (!exact && t.hasPrefix(f + "/"))
    }

    /// `tag` moved from under `old` to under `new`: `a/b/c` from `a/b` to `x` is `x/c`.
    /// Nil when `tag` isn't `old` or a descendant. The rest keeps its own spelling.
    public static func moved(_ tag: String, from old: String, to new: String) -> String? {
        let t = segments(tag), o = segments(key(old))
        guard !o.isEmpty, t.count >= o.count, zip(t, o).allSatisfy({ $0.lowercased() == $1 }) else { return nil }
        let rest = t.dropFirst(o.count)
        return rest.isEmpty ? new : new + "/" + rest.joined(separator: "/")
    }

    /// Where dragging `tag` onto `target` puts it (nil target: top level).
    public static func reparented(_ tag: String, onto target: String?) -> String {
        guard let target, !target.isEmpty else { return leaf(tag) }
        return target + "/" + leaf(tag)
    }

    /// Why `old` can't become `new`, or nil when it can.
    public static func renameProblem(from old: String, to new: String) -> String? {
        let trimmed = new.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Enter a tag name." }
        if trimmed.contains(where: { $0.isWhitespace }) { return "Tags can’t contain spaces." }
        guard let n = normalize(trimmed) else { return "Tags need a letter, and only letters, numbers, - _ and /." }
        if n == normalize(old) { return "That’s the current name." }
        return nil
    }
}

/// One tag occurrence in a note's text.
public struct TagOccurrence: Equatable, Sendable {
    public var name: String          // as written, without `#`
    public var range: NSRange        // UTF-16 range of `name` (the `#` is just before it inline)
    public var inFrontmatter: Bool
}

/// Finds tags in text with their ranges.
public enum TagScanner {
    /// `#tag` not preceded by a word character, `/`, `&` or another `#` (URLs, entities, `##`).
    public static let inlineRegex = try! NSRegularExpression(pattern: #"(?<![\w/&#])#("# + TagName.charClass + #"+)"#)
    static let inlineCodeRegex = try! NSRegularExpression(pattern: #"(`+)(?:(?!\1)[\s\S])+?\1"#)
    static let urlRegex = try! NSRegularExpression(pattern: #"[A-Za-z][A-Za-z0-9+.\-]*://[^\s<>\]\)]+"#)
    static let mdTargetRegex = try! NSRegularExpression(pattern: #"\]\([^)\n]*\)"#)
    static let wikiRegex = try! NSRegularExpression(pattern: #"\[\[[^\[\]\n]*\]\]"#)

    /// Ranges inside which `#` never starts a tag: inline code, [[links]], `](targets)`, URLs.
    public static func exclusions(_ text: String, in range: NSRange) -> [NSRange] {
        var out: [NSRange] = []
        let ns = text as NSString
        let slice = ns.substring(with: range)
        if slice.contains("`") { out += inlineCodeRegex.matches(in: text, range: range).map(\.range) }
        if slice.contains("[[") { out += wikiRegex.matches(in: text, range: range).map(\.range) }
        if slice.contains("](") { out += mdTargetRegex.matches(in: text, range: range).map(\.range) }
        if slice.contains("://") { out += urlRegex.matches(in: text, range: range).map(\.range) }
        return out
    }

    /// Inline tags in `range` (default: the body), skipping `code` ranges (fences) and exclusions.
    public static func inline(_ text: String, in range: NSRange? = nil, code: [NSRange]? = nil, bodyOffset: Int? = nil) -> [TagOccurrence] {
        let ns = text as NSString
        let start = bodyOffset ?? (range == nil ? Frontmatter.parse(text).bodyOffset : 0)
        let body = range ?? NSRange(location: start, length: ns.length - start)
        guard body.length > 0, ns.substring(with: body).contains("#") else { return [] }
        let fences = code ?? NoteParser.codeRanges(text)
        // exclusions are worked out per line, and only for lines that have a candidate tag
        var skipLine = NSRange(location: NSNotFound, length: 0)
        var skip: [NSRange] = []
        var out: [TagOccurrence] = []
        for m in inlineRegex.matches(in: text, range: body) {
            if fences.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) { continue }
            if !NSLocationInRange(m.range.location, skipLine) {
                skipLine = ns.lineRange(for: NSRange(location: m.range.location, length: 0))
                skip = exclusions(text, in: NSIntersectionRange(skipLine, body))
            }
            if skip.contains(where: { NSLocationInRange(m.range.location, $0) }) { continue }
            var nr = m.range(at: 1)
            // a trailing `/` belongs to the sentence ("#a/"), not the tag
            while nr.length > 0, ns.character(at: NSMaxRange(nr) - 1) == 47 { nr.length -= 1 }
            let name = ns.substring(with: nr)
            guard nr.length > 0, TagName.normalize(name) != nil else { continue }
            out.append(TagOccurrence(name: name, range: nr, inFrontmatter: false))
        }
        return out
    }

    /// Tags under `tags:` / `tag:` in the frontmatter: inline lists, block lists and
    /// space- or comma-separated scalars, quoted or not, with or without `#`.
    public static func frontmatter(_ text: String, parsed: Frontmatter? = nil) -> [TagOccurrence] {
        guard text.hasPrefix("---") else { return [] }
        let ns = text as NSString
        let fm = parsed ?? Frontmatter.parse(text)
        guard fm.lineCount > 0 else { return [] }
        var out: [TagOccurrence] = []
        var inTags = false
        var lineStart = 0
        var lineNo = 0
        while lineStart < fm.bodyOffset, lineNo < fm.lineCount {
            let lr = ns.lineRange(for: NSRange(location: lineStart, length: 0))
            var content = lr
            while content.length > 0, [10, 13].contains(ns.character(at: NSMaxRange(content) - 1)) { content.length -= 1 }
            defer { lineStart = NSMaxRange(lr); lineNo += 1 }
            if lineNo == 0 || lineNo == fm.lineCount - 1 { continue }
            let line = ns.substring(with: content)
            let first = line.first
            if let first, first != " ", first != "\t", first != "-", first != "#" {
                inTags = false
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                guard key == "tags" || key == "tag" else { continue }
                inTags = true
                let off = line.utf16.distance(from: line.utf16.startIndex, to: line.index(after: colon).samePosition(in: line.utf16)!)
                out += tokens(ns, from: content.location + off, to: NSMaxRange(content))
            } else if inTags {
                let t = line.trimmingCharacters(in: .whitespaces)
                guard t.hasPrefix("-") else { continue }
                let dash = (line as NSString).range(of: "-")
                out += tokens(ns, from: content.location + dash.location + 1, to: NSMaxRange(content))
            }
        }
        return out
    }

    /// Tag-shaped tokens between `from` and `to`, splitting on spaces, commas, brackets and quotes.
    static func tokens(_ ns: NSString, from: Int, to: Int) -> [TagOccurrence] {
        var out: [TagOccurrence] = []
        var i = from
        func isSep(_ c: unichar) -> Bool { [32, 9, 44, 91, 93, 34, 39].contains(c) }
        while i < to {
            let c = ns.character(at: i)
            if isSep(c) { i += 1; continue }
            // a YAML comment: ` # ...` (a `#` followed by a space, or after a space when it's alone)
            if c == 35, i + 1 >= to || [32, 9].contains(ns.character(at: i + 1)) { break }
            var j = i
            while j < to, !isSep(ns.character(at: j)) { j += 1 }
            var r = NSRange(location: i, length: j - i)
            while r.length > 0, ns.character(at: r.location) == 35 { r.location += 1; r.length -= 1 }
            while r.length > 0, ns.character(at: NSMaxRange(r) - 1) == 47 { r.length -= 1 }
            if r.length > 0 {
                let name = ns.substring(with: r)
                if TagName.normalize(name) != nil { out.append(TagOccurrence(name: name, range: r, inFrontmatter: true)) }
            }
            i = j
        }
        return out
    }

    /// Every tag in a note, frontmatter first, deduplicated case-insensitively (first spelling wins).
    public static func all(_ text: String, code: [NSRange]? = nil, frontmatter parsed: Frontmatter? = nil) -> [TagOccurrence] {
        let fm = parsed ?? Frontmatter.parse(text)
        return frontmatter(text, parsed: fm) + inline(text, code: code, bodyOffset: fm.bodyOffset)
    }

    /// Unique normalized tag names in a note.
    public static func names(_ text: String, code: [NSRange]? = nil, frontmatter parsed: Frontmatter? = nil) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for o in all(text, code: code, frontmatter: parsed) {
            guard let n = TagName.normalize(o.name), seen.insert(n.lowercased()).inserted else { continue }
            out.append(n)
        }
        return out
    }
}

/// A node in the tag tree.
public struct TagNode: Identifiable, Hashable, Sendable {
    public var id: String { key }
    /// The last segment, as most often spelled.
    public var name: String
    /// The full path (`parent/child`), as most often spelled.
    public var path: String
    /// Lowercased full path.
    public var key: String
    /// Notes tagged with exactly this tag.
    public var ownCount: Int
    /// Notes tagged with this tag or any descendant (each note once).
    public var totalCount: Int
    public var children: [TagNode]
    public var depth: Int { key.split(separator: "/").count - 1 }
}

/// The vault's tags as a tree.
public struct TagTree: Sendable {
    public enum Sort: String, Sendable, CaseIterable { case name, count }
    public var roots: [TagNode]
    /// Lowercased path -> every note path in that subtree / tagged exactly.
    public private(set) var subtreeNotes: [String: Set<String>] = [:]
    public private(set) var exactNotes: [String: Set<String>] = [:]
    /// Lowercased path -> display path.
    public private(set) var display: [String: String] = [:]

    public init(roots: [TagNode] = []) { self.roots = roots }

    /// Build from `tag -> note paths` (VaultSnapshot.tags). Case variants merge.
    public init(tags: [String: Set<String>], sort: Sort = .name) {
        var exact: [String: Set<String>] = [:]
        var spellings: [String: [String: Int]] = [:]   // key -> spelling of the full path -> notes
        for (raw, notes) in tags {
            guard let n = TagName.normalize(raw) else { continue }
            let k = n.lowercased()
            exact[k, default: []].formUnion(notes)
            spellings[k, default: [:]][n, default: 0] += notes.count
        }
        // the spelling of each node: the most-used full spelling, else the one implied by children
        var shown: [String: String] = [:]
        func best(_ m: [String: Int]) -> String {
            m.max { a, b in a.value == b.value ? a.key > b.key : a.value < b.value }!.key
        }
        for (k, m) in spellings { shown[k] = best(m) }
        var subtree: [String: Set<String>] = [:]
        var children: [String: Set<String>] = [:]
        var roots = Set<String>()
        var segmentVotes: [String: [String: Int]] = [:]  // implicit parent key -> spelling votes
        for (k, notes) in exact {
            let segs = TagName.segments(shown[k] ?? k)
            var cur = "", curKey = ""
            for (i, s) in segs.enumerated() {
                let parentKey = curKey
                cur = cur.isEmpty ? s : cur + "/" + s
                curKey = cur.lowercased()
                subtree[curKey, default: []].formUnion(notes)
                if i == 0 { roots.insert(curKey) } else { children[parentKey, default: []].insert(curKey) }
                if exact[curKey] == nil { segmentVotes[curKey, default: [:]][cur, default: 0] += notes.count }
            }
        }
        for (k, votes) in segmentVotes where exact[k] == nil { shown[k] = best(votes) }
        func build(_ k: String) -> TagNode {
            let p = shown[k] ?? k
            let kids = (children[k] ?? []).map(build)
            return TagNode(name: TagName.leaf(p), path: p, key: k, ownCount: exact[k]?.count ?? 0,
                           totalCount: subtree[k]?.count ?? 0, children: kids)
        }
        self.roots = roots.map(build)
        self.subtreeNotes = subtree
        self.exactNotes = exact
        self.display = shown
        self.roots = Self.sorted(self.roots, by: sort)
    }

    public static func sorted(_ nodes: [TagNode], by sort: Sort) -> [TagNode] {
        nodes.map { var n = $0; n.children = sorted(n.children, by: sort); return n }.sorted { a, b in
            switch sort {
            case .name: break
            case .count: if a.totalCount != b.totalCount { return a.totalCount > b.totalCount }
            }
            let c = a.name.localizedStandardCompare(b.name)
            return c == .orderedSame ? a.key < b.key : c == .orderedAscending
        }
    }
    public func sorted(by sort: Sort) -> TagTree { var t = self; t.roots = Self.sorted(roots, by: sort); return t }

    /// Notes for a tag: with its descendants (Obsidian's `tag:#parent`), or only exactly.
    public func notes(for tag: String, exact: Bool = false) -> Set<String> {
        let k = TagName.key(tag)
        return (exact ? exactNotes[k] : subtreeNotes[k]) ?? []
    }

    public func node(_ tag: String) -> TagNode? {
        let k = TagName.key(tag)
        var level = roots
        var cur = ""
        for s in k.split(separator: "/") {
            cur = cur.isEmpty ? String(s) : cur + "/" + s
            guard let n = level.first(where: { $0.key == cur }) else { return nil }
            if cur == k { return n }
            level = n.children
        }
        return nil
    }

    public func contains(_ tag: String) -> Bool { subtreeNotes[TagName.key(tag)] != nil }
    public var count: Int { subtreeNotes.count }

    /// Only nodes whose path matches `query` (every word, case-insensitive), with their ancestors.
    /// `expand` is every ancestor that has to open to show a match.
    public func filtered(_ query: String) -> (tree: TagTree, expand: Set<String>) {
        let words = query.lowercased().split(whereSeparator: { $0 == " " }).map { $0.hasPrefix("#") ? String($0.dropFirst()) : String($0) }.filter { !$0.isEmpty }
        guard !words.isEmpty else { return (self, []) }
        var expand = Set<String>()
        func keep(_ n: TagNode) -> TagNode? {
            let hit = words.allSatisfy { n.key.contains($0) }
            let kids = n.children.compactMap(keep)
            if hit { var m = n; m.children = kids.isEmpty ? n.children : kids; if !kids.isEmpty { expand.insert(n.key) }; return m }
            guard !kids.isEmpty else { return nil }
            expand.insert(n.key)
            var m = n; m.children = kids; return m
        }
        var t = self
        t.roots = roots.compactMap(keep)
        return (t, expand)
    }

    /// One visible row of the tree.
    public struct Row: Identifiable, Hashable, Sendable {
        public var id: String { node.key }
        public var node: TagNode
        public var depth: Int
        public var expanded: Bool
        public var hasChildren: Bool { !node.children.isEmpty }
    }

    /// The rows a tree view shows: roots, plus the children of every expanded node.
    public func rows(expanded: Set<String>) -> [Row] {
        var out: [Row] = []
        func walk(_ nodes: [TagNode], _ d: Int) {
            for n in nodes {
                let open = expanded.contains(n.key) && !n.children.isEmpty
                out.append(Row(node: n, depth: d, expanded: open))
                if open { walk(n.children, d + 1) }
            }
        }
        walk(roots, 0)
        return out
    }

    /// Every key with children under (and including) `tag`: what ⌥-clicking a disclosure opens.
    public func subtreeKeys(_ tag: String) -> Set<String> {
        guard let n = node(tag) else { return [] }
        var out = Set<String>()
        func walk(_ n: TagNode) { if !n.children.isEmpty { out.insert(n.key); n.children.forEach(walk) } }
        walk(n)
        return out
    }

    /// Every path in the tree, display spelling, with its subtree count: completion's word list.
    public var allPaths: [(path: String, count: Int, hasChildren: Bool, own: Int)] {
        var out: [(String, Int, Bool, Int)] = []
        func walk(_ ns: [TagNode]) { for n in ns { out.append((n.path, n.totalCount, !n.children.isEmpty, n.ownCount)); walk(n.children) } }
        walk(roots)
        return out
    }
}

/// Rename or move a tag and its whole subtree across the vault.
public enum TagRename {
    public struct LineChange: Equatable, Sendable {
        public var line: Int        // 0-based
        public var before: String
        public var after: String
    }
    public struct FileChange: Equatable, Sendable {
        public var path: String
        public var before: String
        public var after: String
        public var count: Int
        public var lines: [LineChange]
    }
    public struct Plan: Equatable, Sendable {
        public var from: String
        public var to: String
        public var changes: [FileChange]
        /// Distinct old tags that move (`a`, `a/b`, ...) -> their new names.
        public var renames: [(String, String)]
        public var occurrences: Int { changes.reduce(0) { $0 + $1.count } }
        /// Whether the new name already exists, so the tags merge.
        public var merges: Bool
        public static func == (a: Plan, b: Plan) -> Bool {
            a.from == b.from && a.to == b.to && a.changes == b.changes && a.merges == b.merges
                && a.renames.map { $0.0 + "→" + $0.1 } == b.renames.map { $0.0 + "→" + $0.1 }
        }
    }

    /// `text` with every `old` (and `old/...`) tag renamed to `new`, inline and in frontmatter.
    public static func rewrite(_ text: String, from old: String, to new: String) -> (text: String, count: Int, lines: [LineChange], renames: [(String, String)]) {
        guard let new = TagName.normalize(new), TagName.normalize(old) != nil else { return (text, 0, [], []) }
        let ns = text as NSString
        var hits: [(NSRange, String)] = []
        var renames: [(String, String)] = []
        for o in TagScanner.all(text) {
            guard let n = TagName.normalize(o.name), let moved = TagName.moved(n, from: old, to: new) else { continue }
            if moved == o.name { continue }
            hits.append((o.range, moved))
            if !renames.contains(where: { $0.0 == n }) { renames.append((n, moved)) }
        }
        guard !hits.isEmpty else { return (text, 0, [], []) }
        hits.sort { $0.0.location < $1.0.location }
        // one pass: line numbers and before/after for each touched line
        var lines: [LineChange] = []
        var lineNo = 0, scanned = 0
        var i = 0
        while i < hits.count {
            let lr = ns.lineRange(for: NSRange(location: hits[i].0.location, length: 0))
            while scanned < lr.location { if ns.character(at: scanned) == 10 { lineNo += 1 }; scanned += 1 }
            var content = lr
            while content.length > 0, [10, 13].contains(ns.character(at: NSMaxRange(content) - 1)) { content.length -= 1 }
            let after = NSMutableString(string: ns.substring(with: content))
            var j = i
            while j < hits.count, NSLocationInRange(hits[j].0.location, lr) { j += 1 }
            for (r, s) in hits[i..<j].reversed() { after.replaceCharacters(in: NSRange(location: r.location - content.location, length: r.length), with: s) }
            lines.append(LineChange(line: lineNo, before: ns.substring(with: content), after: after as String))
            i = j
        }
        let out = NSMutableString(string: text)
        for (r, s) in hits.reversed() { out.replaceCharacters(in: r, with: s) }
        return (out as String, hits.count, lines, renames)
    }

    /// The rename across `texts` (path -> contents), without writing anything.
    public static func plan(texts: [String: String], from old: String, to new: String, existing: TagTree? = nil) -> Plan {
        let target = TagName.normalize(new) ?? new
        var changes: [FileChange] = []
        var renames: [(String, String)] = []
        for path in texts.keys.sorted() {
            let t = texts[path]!
            guard t.range(of: TagName.leaf(old), options: .caseInsensitive) != nil else { continue }
            let r = rewrite(t, from: old, to: target)
            guard r.count > 0 else { continue }
            changes.append(FileChange(path: path, before: t, after: r.text, count: r.count, lines: r.lines))
            for x in r.renames where !renames.contains(where: { $0.0.lowercased() == x.0.lowercased() }) { renames.append(x) }
        }
        renames.sort { $0.0.lowercased() < $1.0.lowercased() }
        let merges = existing.map { t in t.contains(target) && TagName.key(target) != TagName.key(old) } ?? false
        return Plan(from: old, to: target, changes: changes, renames: renames, merges: merges)
    }
}

/// Completion for `#tags` in the editor, by path segment.
public enum TagCompletion {
    public struct Context: Equatable, Sendable {
        /// UTF-16 offset in the line where the tag text starts (after `#`, or the frontmatter token).
        public var queryStart: Int
        /// End of the tag text the caret is in (an accept replaces `queryStart..<replaceEnd`).
        public var replaceEnd: Int
        public var query: String
        public var inFrontmatter: Bool
    }

    static func isTagChar(_ c: unichar) -> Bool {
        guard let u = UnicodeScalar(c) else { return true }   // surrogate halves: emoji
        if u == "/" { return true }
        return TagName.isValidBody(String(u)) || CharacterSet.decimalDigits.contains(u)
    }

    /// The tag being typed at `caret` in `line`, if any. `#` must not follow a word character,
    /// `/`, `&` or `#`, and at the start of a line it needs a character after it (`#` alone may be
    /// a heading in the making).
    public static func context(line: String, caret: Int) -> Context? {
        let ns = line as NSString
        guard caret > 0, caret <= ns.length else { return nil }
        var i = caret
        while i > 0, isTagChar(ns.character(at: i - 1)) { i -= 1 }
        guard i > 0, ns.character(at: i - 1) == 35 else { return nil }
        let hash = i - 1
        if hash > 0 {
            let p = ns.character(at: hash - 1)
            if let u = UnicodeScalar(p), CharacterSet.alphanumerics.contains(u) || u == "_" || u == "/" || u == "&" || u == "#" || u == "`" { return nil }
        }
        let query = ns.substring(with: NSRange(location: i, length: caret - i))
        if query.isEmpty {
            let before = ns.substring(to: hash).trimmingCharacters(in: .whitespaces)
            if before.isEmpty { return nil }
        }
        // inside a [[link]], a `](target)` or inline code: not a tag
        let head = ns.substring(to: hash)
        if let open = head.range(of: "[[", options: .backwards), head[open.upperBound...].range(of: "]]") == nil { return nil }
        if head.filter({ $0 == "`" }).count % 2 == 1 { return nil }
        if head.hasSuffix("](") || head.hasSuffix("(") && head.dropLast().hasSuffix("]") { return nil }
        if let last = head.split(separator: " ").last, last.contains("://") { return nil }
        var end = caret
        while end < ns.length, isTagChar(ns.character(at: end)) { end += 1 }
        return Context(queryStart: i, replaceEnd: end, query: query, inFrontmatter: false)
    }

    /// The tag token being typed in a frontmatter `tags:` value (`text` is the whole note).
    public static func frontmatterContext(text: String, caret: Int) -> (context: Context, lineStart: Int)? {
        guard text.hasPrefix("---") else { return nil }
        let ns0 = text as NSString
        // cheap: a closing `---` before the caret means the caret is in the body (no full parse per keystroke)
        guard caret <= ns0.length else { return nil }
        let head = NSRange(location: 3, length: max(0, caret - 3))
        if ns0.range(of: "\n---", range: head).location != NSNotFound || ns0.range(of: "\n...", range: head).location != NSNotFound { return nil }
        let fm = Frontmatter.parse(text)
        guard fm.lineCount > 0, caret < fm.bodyOffset else { return nil }
        let ns = text as NSString
        let lr = ns.lineRange(for: NSRange(location: caret, length: 0))
        guard lr.location > 0 else { return nil }
        var line = ns.substring(with: lr)
        while line.hasSuffix("\n") || line.hasSuffix("\r") { line.removeLast() }
        let col = caret - lr.location
        let lns = line as NSString
        guard col <= lns.length else { return nil }
        // which key owns this line?
        var owner: String?
        if let f = line.first, f != " ", f != "\t", f != "-" {
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let off = line.utf16.distance(from: line.utf16.startIndex, to: colon.samePosition(in: line.utf16)!)
            guard col > off else { return nil }
            owner = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
        } else {
            guard line.trimmingCharacters(in: .whitespaces).hasPrefix("-") else { return nil }
            var p = lr.location
            while p > 0 {
                let prev = ns.lineRange(for: NSRange(location: p - 1, length: 0))
                let l = ns.substring(with: prev)
                if let f = l.first, f != " ", f != "\t", f != "-", f != "\n" {
                    if let c = l.firstIndex(of: ":") { owner = String(l[..<c]).trimmingCharacters(in: .whitespaces).lowercased() }
                    break
                }
                p = prev.location
            }
        }
        guard owner == "tags" || owner == "tag" else { return nil }
        var i = col
        while i > 0, isTagChar(lns.character(at: i - 1)) { i -= 1 }
        let start = i   // a `#` before the token stays; completion fills in after it
        var end = col
        while end < lns.length, isTagChar(lns.character(at: end)) { end += 1 }
        let q = lns.substring(with: NSRange(location: start, length: col - start))
        return (Context(queryStart: start, replaceEnd: end, query: q, inFrontmatter: true), lr.location)
    }

    public struct Suggestion: Equatable, Sendable {
        public var path: String          // the full tag to insert
        public var count: Int            // notes in its subtree
        public var hasChildren: Bool
        public var own: Int              // notes tagged with exactly this
        public var exact: Bool
        /// UTF-16 offsets in `path` that matched, for bolding.
        public var hits: [Int]
    }

    /// Suggestions for `query`. Typing `pro` offers top-level tags starting with `pro` (and
    /// deeper tags whose segment starts with it); `projects/` offers the children of `projects`;
    /// `projects/ac` the children starting with `ac`. Most-used first, exact match on top.
    public static func suggestions(_ query: String, paths: [(path: String, count: Int, hasChildren: Bool, own: Int)], limit: Int = 10) -> [Suggestion] {
        let q = query.lowercased()
        let parent: String, seg: String
        if let slash = q.lastIndex(of: "/") { parent = String(q[..<slash]); seg = String(q[q.index(after: slash)...]) }
        else { parent = ""; seg = q }
        var primary: [Suggestion] = [], secondary: [Suggestion] = []
        for p in paths {
            let k = p.path.lowercased()
            let par = TagName.parent(k) ?? ""
            let leaf = TagName.leaf(k)
            if par == parent && leaf.hasPrefix(seg) {
                let hitStart = parent.isEmpty ? 0 : parent.utf16.count + 1
                primary.append(Suggestion(path: p.path, count: p.count, hasChildren: p.hasChildren, own: p.own, exact: !q.isEmpty && k == q,
                                          hits: Array(hitStart..<(hitStart + seg.utf16.count))))
            } else if !q.isEmpty, parent.isEmpty, !seg.isEmpty, let r = k.range(of: "/" + seg) {
                let at = k.utf16.distance(from: k.utf16.startIndex, to: r.lowerBound.samePosition(in: k.utf16)!) + 1
                secondary.append(Suggestion(path: p.path, count: p.count, hasChildren: p.hasChildren, own: p.own, exact: false, hits: Array(at..<(at + seg.utf16.count))))
            }
        }
        func order(_ a: Suggestion, _ b: Suggestion) -> Bool {
            if a.exact != b.exact { return a.exact }
            if a.count != b.count { return a.count > b.count }
            return a.path.localizedStandardCompare(b.path) == .orderedAscending
        }
        let out = primary.sorted(by: order) + secondary.sorted(by: order)
        if out.count == 1, out[0].exact, !out[0].hasChildren { return [] }   // nothing left to complete
        return Array(out.prefix(limit))
    }

    /// What an accept writes: the path, and `/` to keep going when the tag is only a parent.
    public static func insertText(_ s: Suggestion) -> String {
        s.hasChildren && s.own == 0 ? s.path + "/" : s.path
    }
}
