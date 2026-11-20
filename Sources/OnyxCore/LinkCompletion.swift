import Foundation

/// The `[[…]]` suggestion popup's rules, kept free of AppKit so they can be tested.
/// The popup never edits text on its own: every keystroke goes into the note, it only
/// filters, and only an explicit accept (↩/⇥ on a highlighted row, or a click) replaces
/// the part being typed.
public enum LinkCompletion {
    public enum Part: Equatable, Sendable {
        case note                                 // [[Na|      → suggest notes
        case heading(note: String)                // [[Note#He| → suggest that note's headings
        case block                                // [[Note#^id → nothing to suggest, typing is free
        case alias                                // [[Note|Al  → free text
    }

    /// Where the caret sits inside an open wikilink on its line.
    public struct Context: Equatable, Sendable {
        /// UTF-16 offsets within the line: `queryStart..<caret` is what an accept replaces.
        public var queryStart: Int
        public var caret: Int
        public var query: String
        public var part: Part
        /// The `[[` (UTF-16 offset of the first bracket), identifying this link across keystrokes.
        public var open: Int
        public var embed: Bool                    // ![[…]]
    }

    /// `line` is the caret's line, `caret` a UTF-16 offset in it. Nil when the caret isn't
    /// inside `[[…` (no `]` between the brackets and the caret).
    public static func context(line: String, caret: Int) -> Context? {
        let u = Array(line.utf16)
        guard caret >= 2, caret <= u.count else { return nil }
        let lb: UInt16 = 0x5B, rb: UInt16 = 0x5D
        var i = caret - 1
        var open: Int?
        while i >= 1 {
            if u[i] == rb { return nil }                       // a closed link (or stray ]) before us
            if u[i] == lb && u[i - 1] == lb { open = i - 1; break }
            i -= 1
        }
        guard let open else { return nil }
        let start = open + 2
        let inner = String(utf16CodeUnits: Array(u[start..<caret]), count: caret - start)
        if inner.contains("\n") { return nil }
        let embed = open >= 1 && u[open - 1] == 0x21           // !
        if let bar = inner.firstIndex(of: "|") {
            let off = inner.utf16.distance(from: inner.startIndex, to: bar) + 1
            return Context(queryStart: start + off, caret: caret, query: String(inner[inner.index(after: bar)...]), part: .alias, open: open, embed: embed)
        }
        if let hash = inner.firstIndex(of: "#") {
            let note = String(inner[..<hash])
            let rest = inner[inner.index(after: hash)...]
            let off = inner.utf16.distance(from: inner.startIndex, to: hash) + 1
            if rest.hasPrefix("^") {
                return Context(queryStart: start + off, caret: caret, query: String(rest), part: .block, open: open, embed: embed)
            }
            return Context(queryStart: start + off, caret: caret, query: String(rest), part: .heading(note: note), open: open, embed: embed)
        }
        return Context(queryStart: start, caret: caret, query: inner, part: .note, open: open, embed: embed)
    }

    /// Nothing is highlighted until the arrow keys are used, unless the top match is exact.
    public static func defaultHighlight(topIsExact: Bool) -> Int? { topIsExact ? 0 : nil }

    /// ↓/↑ from the current highlight; nil means "nothing highlighted".
    public static func move(_ current: Int?, by d: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let c = current else { return d > 0 ? 0 : count - 1 }
        return min(max(c + d, 0), count - 1)
    }

    public enum KeyAction: Equatable, Sendable {
        case accept(Int)      // replace the query with row n
        case leave            // keep what was typed; step past the closing ]] (↩/⇥ with nothing highlighted)
        case dismiss          // Esc: close, change nothing
        case pass             // let the text view have it
    }
    public enum Key: Sendable { case returnKey, tab, escape, other }
    public static func action(for key: Key, highlighted: Int?) -> KeyAction {
        switch key {
        case .returnKey, .tab: return highlighted.map { .accept($0) } ?? .leave
        case .escape: return .dismiss
        case .other: return .pass
        }
    }

    /// The text a note suggestion inserts: its name, or its vault path (no .md) when another
    /// note shares the name, as Obsidian does.
    public static func linkText(path: String, name: String, nameIsUnique: Bool) -> String {
        nameIsUnique ? name : (path.hasSuffix(".md") ? String(path.dropLast(3)) : path)
    }
}
