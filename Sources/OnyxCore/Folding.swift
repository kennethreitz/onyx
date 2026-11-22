import Foundation

/// A view of source, never a replacement for it. All offsets are UTF-16 (TextKit / NSString).
public struct FoldRegion: Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case heading, list }
    public var kind: Kind
    public var level: Int
    public var line: Int
    public var header: NSRange
    public var hidden: NSRange
    public var anchor: FoldAnchor
}

public struct FoldAnchor: Hashable, Codable, Sendable {
    public var signature: String
    public var occurrence: Int
    public init(signature: String, occurrence: Int) { self.signature = signature; self.occurrence = occurrence }
}

/// Conservative Markdown folding: ATX + single-line setext headings, and indented list
/// children. Fences and frontmatter are opaque. No regex rescans of suffixes or quadratic
/// search for the next heading: ranges are closed with stacks in one pass.
public enum MarkdownFolds {
    private struct Line {
        var range: NSRange; var contentEnd: Int; var text: String; var indent: Int
        var blank: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty }
    }
    private static let atx = try! NSRegularExpression(pattern: #"^ {0,3}(#{1,6})(?:[ \t]+|$)"#)
    private static let list = try! NSRegularExpression(pattern: #"^[ \t]*([-+*]|[0-9]{1,9}[.)])[ \t]+\S"#)
    private static let fence = try! NSRegularExpression(pattern: #"^ {0,3}(`{3,}|~{3,})(.*)$"#)
    private static let setext = try! NSRegularExpression(pattern: #"^ {0,3}(=+|-+)[ \t]*$"#)

    public static func regions(in text: String) -> [FoldRegion] {
        let ns = text as NSString, fm = Frontmatter.parse(text)
        var lines: [Line] = [], loc = 0
        while loc < ns.length {
            let r = ns.lineRange(for: NSRange(location: loc, length: 0))
            let s = ns.substring(with: r).trimmingCharacters(in: .newlines)
            var indent = 0
            for ch in s { if ch == " " { indent += 1 } else if ch == "\t" { indent += 4 - indent % 4 } else { break } }
            lines.append(Line(range: r, contentEnd: r.location + s.utf16.count, text: s, indent: indent))
            loc = NSMaxRange(r)
        }
        guard !lines.isEmpty else { return [] }
        var opaque = Array(repeating: false, count: lines.count)
        var marker: Character?, markerCount = 0
        for i in lines.indices {
            let l = lines[i]
            if l.range.location < fm.bodyOffset { opaque[i] = true; continue }
            let n = l.text as NSString
            if let m = fence.firstMatch(in: l.text, range: NSRange(location: 0, length: n.length)) {
                let run = n.substring(with: m.range(at: 1)), rest = n.substring(with: m.range(at: 2))
                if marker == nil {
                    if run.first == "`" && rest.contains("`") { continue }
                    marker = run.first; markerCount = run.count; opaque[i] = true
                } else if run.first == marker && run.count >= markerCount && rest.trimmingCharacters(in: .whitespaces).isEmpty {
                    opaque[i] = true; marker = nil
                } else { opaque[i] = true }
            } else if marker != nil { opaque[i] = true }
        }
        struct H { var i: Int; var end: Int; var level: Int }
        var headings: [H] = [], underline = Set<Int>()
        for i in lines.indices where !opaque[i] && !underline.contains(i) {
            let l = lines[i], n = l.text as NSString
            if let m = atx.firstMatch(in: l.text, range: NSRange(location: 0, length: n.length)) {
                headings.append(H(i: i, end: i, level: m.range(at: 1).length))
            } else if i + 1 < lines.count, !opaque[i + 1], !l.blank, l.indent < 4,
                      !l.text.trimmingCharacters(in: .whitespaces).hasPrefix(">"),
                      list.firstMatch(in: l.text, range: NSRange(location: 0, length: n.length)) == nil,
                      let m = setext.firstMatch(in: lines[i + 1].text, range: NSRange(location: 0, length: lines[i + 1].text.utf16.count)) {
                let run = (lines[i + 1].text as NSString).substring(with: m.range(at: 1))
                // A thematic break isn't the first half of a setext heading.
                let t = l.text.trimmingCharacters(in: .whitespaces)
                if !["---", "***", "___"].contains(t) {
                    headings.append(H(i: i, end: i + 1, level: run.first == "=" ? 1 : 2)); underline.insert(i + 1)
                }
            }
        }
        var result: [FoldRegion] = []
        func append(_ kind: FoldRegion.Kind, _ i: Int, _ headerEnd: Int, _ end: Int, _ level: Int) {
            // Don't offer a disclosure for an empty / blank-only section.
            let first = headerEnd + 1
            guard first < end, let last = (first..<end).last(where: { !lines[$0].blank }) else { return }
            // Trailing blank lines stay visible: the page keeps its rhythm between sections.
            let start = lines[headerEnd].contentEnd, stop = lines[last].contentEnd
            guard stop > start else { return }
            let hr = NSRange(location: lines[i].range.location, length: lines[headerEnd].contentEnd - lines[i].range.location)
            let signature = kind.rawValue + ":" + ns.substring(with: hr).trimmingCharacters(in: .whitespaces)
            result.append(FoldRegion(kind: kind, level: level, line: i, header: hr,
                                     hidden: NSRange(location: start, length: stop - start),
                                     anchor: FoldAnchor(signature: signature, occurrence: 0)))
        }
        var stack: [H] = []
        for h in headings {
            while let p = stack.last, p.level >= h.level { _ = stack.popLast(); append(.heading, p.i, p.end, h.i, p.level) }
            stack.append(h)
        }
        for p in stack { append(.heading, p.i, p.end, lines.count, p.level) }

        // A list disclosure is offered only if it has an actual nested list item. Loose
        // lists and indented continuation paragraphs belong to the parent; unindented
        // lazy continuations deliberately end it rather than hide surprising prose.
        struct L { var i: Int; var indent: Int; var child: Bool }
        var lists: [L] = []
        let headingLines = Set(headings.map(\.i))
        for i in lines.indices {
            let l = lines[i]
            if l.blank { continue }
            let match = !opaque[i] && !underline.contains(i) && !headingLines.contains(i)
                && list.firstMatch(in: l.text, range: NSRange(location: 0, length: l.text.utf16.count)) != nil
            while let p = lists.last, l.indent <= p.indent {
                _ = lists.popLast(); if p.child { append(.list, p.i, p.i, i, p.indent) }
            }
            if match {
                if !lists.isEmpty { lists[lists.count - 1].child = true }
                lists.append(L(i: i, indent: l.indent, child: false))
            }
        }
        for p in lists where p.child { append(.list, p.i, p.i, lines.count, p.indent) }
        result.sort { $0.header.location < $1.header.location }
        var occurrences: [String: Int] = [:]
        for i in result.indices {
            let s = result[i].anchor.signature, n = occurrences[s, default: 0]
            result[i].anchor.occurrence = n; occurrences[s] = n + 1
        }
        return result
    }
}

/// Fold identity across ordinary edits: offsets are mapped through the actual storage edit,
/// not guessed from a diff. A changed heading stays folded; a deleted heading is discarded.
public enum FoldEdits {
    /// `edit` and `delta` are NSTextStorage's editedRange / changeInLength (new coordinates).
    public static func remap(_ folded: [FoldRegion], edit: NSRange, delta: Int, into regions: [FoldRegion]) -> Set<FoldAnchor> {
        let loc = edit.location, oldLength = max(0, edit.length - delta), oldEnd = loc + oldLength
        let at = Dictionary(regions.map { ($0.header.location, $0) }, uniquingKeysWith: { a, _ in a })
        var out = Set<FoldAnchor>()
        for f in folded {
            let a = f.header.location
            var candidates: [Int]
            if a < loc {
                candidates = [a]
            } else if a == loc {
                // Replaced the whole header line, terminator included: the heading is gone.
                if oldLength > 0, oldEnd > NSMaxRange(f.header) { continue }
                candidates = [loc + edit.length, loc]   // a newline typed before it, or a heading edit
            } else if a < oldEnd {
                continue   // the newline before it was deleted: merged into another line
            } else {
                candidates = [a + delta]
            }
            if let r = candidates.compactMap({ at[$0] }).first(where: { $0.kind == f.kind }) { out.insert(r.anchor) }
        }
        return out
    }
}

/// Local UI state only; no writes to the vault, no effect on sync or document undo.
public final class FoldStore {
    private let defaults: UserDefaults
    private let key: String
    private var notes: [String: [FoldAnchor]]
    public init(vault: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults; key = "onyx.folds." + vault
        notes = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([String: [FoldAnchor]].self, from: $0) } ?? [:]
    }
    public func anchors(for path: String) -> Set<FoldAnchor> { Set(notes[path] ?? []) }
    public func set(_ anchors: Set<FoldAnchor>, for path: String) {
        let a = anchors.sorted { ($0.signature, $0.occurrence) < ($1.signature, $1.occurrence) }
        guard (notes[path] ?? []) != a else { return }
        notes[path] = a.isEmpty ? nil : a
        persist()
    }
    public func remapPaths(_ map: [String: String]) {
        let previous = notes
        for (from, to) in map where from != to { if let a = previous[from] { notes[from] = nil; notes[to] = a } }
        persist()
    }
    private func persist() { if let data = try? JSONEncoder().encode(notes) { defaults.set(data, forKey: key) } }
}

/// Where carets may live while text is folded. Folded text is never a valid caret target:
/// navigation steps over it, and programmatic selection (Find, outline, links, undo) opens it.
public enum FoldSelection {
    public enum Intent: Sendable { case keyboard, mouse, programmatic }
    public struct Result: Equatable, Sendable {
        public var range: NSRange
        public var reveal: [Int]
    }

    /// Union of the hidden ranges, sorted and merged (nested folds collapse to their parent).
    public static func merge(_ ranges: [NSRange]) -> [NSRange] {
        var out: [NSRange] = []
        for r in ranges.sorted(by: { $0.location < $1.location }) where r.length > 0 {
            if let last = out.last, r.location <= NSMaxRange(last) {
                out[out.count - 1].length = max(NSMaxRange(last), NSMaxRange(r)) - last.location
            } else { out.append(r) }
        }
        return out
    }

    /// The merged hidden range a caret position would be inside: after the header's last
    /// visible character, up to and including the end of the hidden run (which renders at
    /// the same spot, so a caret there would type into folded text).
    public static func container(of p: Int, in hidden: [NSRange]) -> NSRange? {
        var lo = 0, hi = hidden.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2, h = hidden[mid]
            if p <= h.location { hi = mid - 1 } else if p > NSMaxRange(h) { lo = mid + 1 } else { return h }
        }
        return nil
    }

    /// `nextLine(end)` is the first visible character after a hidden run's line terminator.
    public static func adjust(_ r: NSRange, previous: NSRange?, hidden: [NSRange], intent: Intent, nextLine: (Int) -> Int) -> Result {
        guard !hidden.isEmpty else { return Result(range: r, reveal: []) }
        let start = r.location, end = NSMaxRange(r)
        let hs = container(of: start, in: hidden)
        let he = r.length == 0 ? hs : container(of: end, in: hidden).flatMap { end < NSMaxRange($0) ? $0 : nil }
        guard hs != nil || he != nil else { return Result(range: r, reveal: []) }
        switch intent {
        case .programmatic:
            return Result(range: r, reveal: [hs.map { _ in start }, he.map { _ in end }].compactMap { $0 })
        case .mouse:
            let s = hs.map(\.location) ?? start
            let e = r.length == 0 ? s : (he.map { NSMaxRange($0) } ?? end)
            return Result(range: NSRange(location: s, length: max(0, e - s)), reveal: [])
        case .keyboard:
            if r.length == 0, let h = hs {
                let prev = previous.map { $0.length == 0 ? $0.location : NSMaxRange($0) } ?? h.location
                // Only a step from the visible header end into the fold walks over it; landing at
                // the end of the hidden run (↑/↓, ⌘→) or stepping back from below stays on the header.
                if start < NSMaxRange(h), prev <= h.location {
                    let next = nextLine(NSMaxRange(h))   // a fold at EOF has no line after it
                    return Result(range: NSRange(location: next > NSMaxRange(h) ? next : h.location, length: 0), reveal: [])
                }
                return Result(range: NSRange(location: h.location, length: 0), reveal: [])
            }
            let s = hs.map(\.location) ?? start
            let e = he.map { NSMaxRange($0) } ?? end
            return Result(range: NSRange(location: s, length: max(0, e - s)), reveal: [])
        }
    }
}
