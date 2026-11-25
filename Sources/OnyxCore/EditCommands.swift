import Foundation

/// One text change for the editor: replace `range` (UTF-16) with `replacement`, then select `selection`.
public struct TextEdit: Equatable, Sendable {
    public var range: NSRange
    public var replacement: String
    public var selection: NSRange

    public init(range: NSRange, replacement: String, selection: NSRange) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }

    /// The text after the edit (tests and previews).
    public func applied(to text: String) -> String {
        (text as NSString).replacingCharacters(in: range, with: replacement)
    }
}

/// Line prefixes the editing commands toggle.
public enum LineStyle: Sendable {
    case bullet, numbered, checklist, quote
}

/// Pure Markdown editing transforms behind the Format commands (bold, lists, headings,
/// line moves…). Everything works on UTF-16 offsets, the way NSTextView counts.
public enum EditCommands {

    // MARK: Inline wrapping

    /// Toggle `open…close` around the selection (`**` bold, `*` italic, `~~`, `==`, `` ` ``, `%%`).
    /// A selection that already has the markers inside or just outside loses them; an empty
    /// selection between an empty pair removes the pair, otherwise inserts one with the caret inside.
    /// `also` are alternate markers that unwrap the same way (`_` for italic, `__` for bold);
    /// a new wrap always uses `open`.
    public static func toggleWrap(_ text: String, _ sel: NSRange, open: String, close: String? = nil, also: [String] = []) -> TextEdit {
        let close = close ?? open
        if let e = unwrap(text, sel, open: open, close: close) { return e }
        for alt in also {
            if let e = unwrap(text, sel, open: alt, close: alt) { return e }
        }
        let ns = text as NSString
        let sel = clamp(sel, ns.length)
        let s = ns.substring(with: sel)
        let o = (open as NSString).length
        return TextEdit(range: sel, replacement: open + s + close, selection: NSRange(location: sel.location + o, length: sel.length))
    }

    /// Wrap or unwrap with `*`, and unwrap `_…_` too. A second press inside an empty
    /// `*|*` or `_|_` pair removes it (the caret stays put).
    public static func toggleItalic(_ text: String, _ sel: NSRange) -> TextEdit {
        toggleWrap(text, sel, open: "*", also: ["_"])
    }

    /// Wrap or unwrap with `**`, and unwrap `__…__` too.
    public static func toggleBold(_ text: String, _ sel: NSRange) -> TextEdit {
        toggleWrap(text, sel, open: "**", also: ["__"])
    }

    static func unwrap(_ text: String, _ sel: NSRange, open: String, close: String) -> TextEdit? {
        let ns = text as NSString
        let o = (open as NSString).length, c = (close as NSString).length
        let sel = clamp(sel, ns.length)
        let s = ns.substring(with: sel)
        if sel.length >= o + c, s.hasPrefix(open), s.hasSuffix(close) {
            let inner = (s as NSString).substring(with: NSRange(location: o, length: sel.length - o - c))
            return TextEdit(range: sel, replacement: inner, selection: NSRange(location: sel.location, length: (inner as NSString).length))
        }
        if sel.location >= o, NSMaxRange(sel) + c <= ns.length,
           ns.substring(with: NSRange(location: sel.location - o, length: o)) == open,
           ns.substring(with: NSRange(location: NSMaxRange(sel), length: c)) == close,
           !isHalfOfDouble(ns, sel, open) {
            let outer = NSRange(location: sel.location - o, length: sel.length + o + c)
            return TextEdit(range: outer, replacement: s, selection: NSRange(location: outer.location, length: sel.length))
        }
        return nil
    }

    /// `**x**` around a selection is bold, not italic: don't let `*` (or `_`) strip half of it.
    private static func isHalfOfDouble(_ ns: NSString, _ sel: NSRange, _ m: String) -> Bool {
        (m as NSString).length == 1
            && sel.location >= 2 && NSMaxRange(sel) + 2 <= ns.length
            && ns.substring(with: NSRange(location: sel.location - 2, length: 2)) == m + m
            && ns.substring(with: NSRange(location: NSMaxRange(sel), length: 2)) == m + m
    }

    /// `[[selection]]`, or `[[]]` with the caret inside.
    public static func insertWikilink(_ text: String, _ sel: NSRange) -> TextEdit {
        toggleWrap(text, sel, open: "[[", close: "]]")
    }

    /// `[selection](|)`: the caret lands in the URL. With nothing selected, `[|]()`.
    public static func insertMarkdownLink(_ text: String, _ sel: NSRange) -> TextEdit {
        let ns = text as NSString
        let sel = clamp(sel, ns.length)
        let s = ns.substring(with: sel)
        let rep = "[\(s)]()"
        let caret = sel.length == 0 ? sel.location + 1 : sel.location + (rep as NSString).length - 1
        return TextEdit(range: sel, replacement: rep, selection: NSRange(location: caret, length: 0))
    }

    /// Replace the selection with `s`, caret after it.
    public static func insert(_ text: String, _ sel: NSRange, _ s: String) -> TextEdit {
        let sel = clamp(sel, (text as NSString).length)
        return TextEdit(range: sel, replacement: s, selection: NSRange(location: sel.location + (s as NSString).length, length: 0))
    }

    // MARK: Blocks

    /// Insert `block` on its own line(s) at the selection. `caret` is the UTF-16 offset in
    /// `block` where the caret goes (nil = end).
    public static func insertBlock(_ text: String, _ sel: NSRange, _ block: String, caret: Int? = nil) -> TextEdit {
        let ns = text as NSString
        let sel = clamp(sel, ns.length)
        let before = sel.location > 0 && ns.character(at: sel.location - 1) != 10 ? "\n" : ""
        let end = NSMaxRange(sel)
        let after = end < ns.length && ns.character(at: end) != 10 ? "\n" : ""
        let rep = before + block + after
        let at = sel.location + (before as NSString).length + (caret ?? (block as NSString).length)
        return TextEdit(range: sel, replacement: rep, selection: NSRange(location: at, length: 0))
    }

    public static func horizontalRule(_ text: String, _ sel: NSRange) -> TextEdit {
        insertBlock(text, sel, "---\n")
    }

    /// A fenced code block around the selection, or an empty one with the caret inside.
    public static func codeBlock(_ text: String, _ sel: NSRange) -> TextEdit {
        let s = (text as NSString).substring(with: clamp(sel, (text as NSString).length))
        if s.isEmpty { return insertBlock(text, sel, "```\n\n```", caret: 4) }
        let block = "```\n" + s + (s.hasSuffix("\n") ? "" : "\n") + "```"
        return insertBlock(text, sel, block)
    }

    /// `> [!note]` with the selection (if any) quoted beneath it.
    public static func callout(_ text: String, _ sel: NSRange, type: String = "note") -> TextEdit {
        let s = (text as NSString).substring(with: clamp(sel, (text as NSString).length))
        let head = "> [!\(type)]\n"
        let body = s.isEmpty ? "> " : s.components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n")
        return insertBlock(text, sel, head + body)
    }

    /// A 2×2 Markdown table; the caret lands in the first header cell.
    public static func table(_ text: String, _ sel: NSRange) -> TextEdit {
        insertBlock(text, sel, "|  |  |\n| --- | --- |\n|  |  |\n", caret: 2)
    }

    // MARK: Line prefixes

    /// Toggle a list, checklist, or quote prefix on every selected line. If every non-blank
    /// line already has it, remove it; otherwise set it (replacing another list marker).
    public static func toggleLines(_ text: String, _ sel: NSRange, _ style: LineStyle) -> TextEdit {
        mapLines(text, sel) { lines in
            let body = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let all = !body.isEmpty && body.allSatisfy { has(style, $0) }
            var n = 0
            return lines.map { line in
                if line.trimmingCharacters(in: .whitespaces).isEmpty, lines.count > 1 { return line }
                if all { return remove(style, line) }
                if has(style, line) { return line }
                n += 1
                return add(style, line, number: n)
            }
        }
    }

    /// Obsidian's ⌘L: plain text → `- [ ] `, unchecked → checked, checked → unchecked.
    public static func cycleCheckbox(_ text: String, _ sel: NSRange) -> TextEdit {
        mapLines(text, sel) { lines in
            lines.map { line in
                let (indent, rest) = splitIndent(line)
                if let m = rest.firstMatch(of: #/^[-*+] \[ \] /#) { return indent + "- [x] " + rest[m.range.upperBound...] }
                if let m = rest.firstMatch(of: #/^[-*+] \[[^\]]\] /#) { return indent + "- [ ] " + rest[m.range.upperBound...] }
                if lines.count > 1, rest.isEmpty { return line }
                return indent + "- [ ] " + stripMarker(rest)
            }
        }
    }

    /// Make each selected line a level-`level` heading; a line already at that level goes back to text.
    public static func heading(_ text: String, _ sel: NSRange, level: Int) -> TextEdit {
        let level = max(1, min(6, level))
        return mapLines(text, sel) { lines in
            let current = lines.map { line -> Int in
                guard let m = line.firstMatch(of: #/^(#{1,6}) /#) else { return 0 }
                return m.1.count
            }
            let unset = current.allSatisfy { $0 == level }
            return lines.map { line in
                let stripped = line.replacing(#/^#{1,6} /#, with: "", maxReplacements: 1)
                return unset ? stripped : String(repeating: "#", count: level) + " " + stripped
            }
        }
    }

    /// Indent each selected line by a tab.
    public static func indent(_ text: String, _ sel: NSRange) -> TextEdit {
        mapLines(text, sel) { $0.map { "\t" + $0 } }
    }

    /// Remove one tab (or up to four spaces) from each selected line.
    public static func outdent(_ text: String, _ sel: NSRange) -> TextEdit {
        mapLines(text, sel) { lines in
            lines.map { line in
                if line.hasPrefix("\t") { return String(line.dropFirst()) }
                let spaces = line.prefix(while: { $0 == " " }).count
                return String(line.dropFirst(min(4, spaces)))
            }
        }
    }

    // MARK: Whole lines

    /// Swap the selected lines with the line above (`up`) or below. Nil at the edge.
    public static func moveLines(_ text: String, _ sel: NSRange, up: Bool) -> TextEdit? {
        let L = Lines(text), (a, b) = L.span(sel)
        if up {
            guard a > 0 else { return nil }
            let block = Array(L.lines[a...b]), prev = L.lines[a - 1]
            let rep = (block + [prev]).joined(separator: "\n")
            let shift = -(len(prev) + 1)
            return TextEdit(range: L.range(a - 1, b), replacement: rep, selection: NSRange(location: sel.location + shift, length: sel.length))
        } else {
            guard b < L.lines.count - 1 else { return nil }
            let block = Array(L.lines[a...b]), next = L.lines[b + 1]
            let rep = ([next] + block).joined(separator: "\n")
            return TextEdit(range: L.range(a, b + 1), replacement: rep, selection: NSRange(location: sel.location + len(next) + 1, length: sel.length))
        }
    }

    /// Duplicate the selected lines below themselves; the selection moves to the copy.
    public static func duplicateLines(_ text: String, _ sel: NSRange) -> TextEdit {
        let L = Lines(text), (a, b) = L.span(sel)
        let block = L.lines[a...b].joined(separator: "\n")
        let r = L.range(a, b)
        return TextEdit(range: r, replacement: block + "\n" + block, selection: NSRange(location: sel.location + len(block) + 1, length: sel.length))
    }

    /// Delete the selected lines (and their line break).
    public static func deleteLines(_ text: String, _ sel: NSRange) -> TextEdit {
        let L = Lines(text), (a, b) = L.span(sel)
        let r: NSRange
        if b < L.lines.count - 1 {
            r = NSRange(location: L.starts[a], length: L.starts[b + 1] - L.starts[a])
        } else if a > 0 {
            let start = L.starts[a] - 1
            r = NSRange(location: start, length: L.length - start)
        } else {
            r = NSRange(location: 0, length: L.length)
        }
        let caret = a > 0 && b == L.lines.count - 1 ? L.starts[a - 1] : r.location
        return TextEdit(range: r, replacement: "", selection: NSRange(location: caret, length: 0))
    }

    // MARK: Helpers

    /// Rewrite the selected lines with `f`. A selection on one line moves with the edit;
    /// several lines end up selected as a block.
    static func mapLines(_ text: String, _ sel: NSRange, _ f: ([String]) -> [String]) -> TextEdit {
        let L = Lines(text), (a, b) = L.span(sel)
        let old = Array(L.lines[a...b])
        let new = f(old)
        let rep = new.joined(separator: "\n")
        let r = L.range(a, b)
        if a == b {
            let delta = len(rep) - r.length
            let start = L.starts[a]
            // the caret keeps its place in the text; prefixes change at the start of the line
            let loc = max(start, min(start + len(rep), sel.location + delta))
            let end = max(loc, min(start + len(rep), NSMaxRange(sel) + delta))
            return TextEdit(range: r, replacement: rep, selection: NSRange(location: loc, length: sel.length == 0 ? 0 : end - loc))
        }
        return TextEdit(range: r, replacement: rep, selection: NSRange(location: r.location, length: len(rep)))
    }

    static func splitIndent(_ line: String) -> (String, Substring) {
        let i = line.prefix(while: { $0 == " " || $0 == "\t" })
        return (String(i), line[i.endIndex...])
    }

    static func stripMarker(_ rest: Substring) -> Substring {
        if let m = rest.firstMatch(of: #/^([-*+] \[[^\]]\] |[-*+] |\d+[.)] )/#) { return rest[m.range.upperBound...] }
        return rest
    }

    static func has(_ style: LineStyle, _ line: String) -> Bool {
        if style == .quote { return line.hasPrefix(">") }
        let (_, rest) = splitIndent(line)
        switch style {
        case .checklist: return rest.firstMatch(of: #/^[-*+] \[[^\]]\] /#) != nil
        case .bullet: return rest.firstMatch(of: #/^[-*+] /#) != nil && rest.firstMatch(of: #/^[-*+] \[[^\]]\] /#) == nil
        case .numbered: return rest.firstMatch(of: #/^\d+[.)] /#) != nil
        case .quote: return false
        }
    }

    static func remove(_ style: LineStyle, _ line: String) -> String {
        if style == .quote { return line.replacing(#/^> ?/#, with: "", maxReplacements: 1) }
        let (indent, rest) = splitIndent(line)
        return indent + stripMarker(rest)
    }

    static func add(_ style: LineStyle, _ line: String, number: Int) -> String {
        if style == .quote { return "> " + line }
        let (indent, rest) = splitIndent(line)
        let marker: String
        switch style {
        case .bullet: marker = "- "
        case .numbered: marker = "\(number). "
        case .checklist: marker = "- [ ] "
        case .quote: marker = ""
        }
        return indent + marker + stripMarker(rest)
    }

    static func len(_ s: String) -> Int { (s as NSString).length }
    static func len(_ s: Substring) -> Int { (String(s) as NSString).length }

    static func clamp(_ r: NSRange, _ n: Int) -> NSRange {
        let loc = max(0, min(r.location == NSNotFound ? n : r.location, n))
        return NSRange(location: loc, length: max(0, min(r.length, n - loc)))
    }

    /// The text split on `\n`, with each line's UTF-16 start.
    struct Lines {
        let lines: [String]
        let starts: [Int]
        let length: Int
        init(_ text: String) {
            lines = text.components(separatedBy: "\n")
            var s: [Int] = [], at = 0
            for l in lines { s.append(at); at += (l as NSString).length + 1 }
            starts = s
            length = (text as NSString).length
        }
        func index(at loc: Int) -> Int {
            var lo = 0, hi = starts.count - 1
            while lo < hi { let mid = (lo + hi + 1) / 2; if starts[mid] <= loc { lo = mid } else { hi = mid - 1 } }
            return lo
        }
        /// First and last line the selection touches (a selection ending at a line start excludes that line).
        func span(_ sel: NSRange) -> (Int, Int) {
            let s = EditCommands.clamp(sel, length)
            let a = index(at: s.location)
            let endLoc = s.length > 0 ? NSMaxRange(s) - 1 : s.location
            return (a, max(a, index(at: endLoc)))
        }
        /// Lines a…b without the final line break.
        func range(_ a: Int, _ b: Int) -> NSRange {
            NSRange(location: starts[a], length: starts[b] + (lines[b] as NSString).length - starts[a])
        }
    }
}
