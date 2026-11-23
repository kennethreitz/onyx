import Foundation

/// Return (and Tab) behaviour in Markdown lists: continue the marker, split an item,
/// or end / outdent an empty one. Pure text in, `TextEdit` out, so the editor and the
/// tests share one implementation. Ranges are UTF-16, like NSTextView.
public enum ListContinue {

    /// The edit Return should apply, or `nil` for a plain newline (not a list, a
    /// multi-line selection, or a caret inside a fenced code block or frontmatter).
    public static func newline(_ text: String, _ sel: NSRange) -> TextEdit? {
        let ns = text as NSString
        let sel = EditCommands.clamp(sel, ns.length)
        if opaque(text, sel) { return nil }
        guard let span = lineSpan(ns, sel) else { return nil }
        guard let item = parse(span.line) else { return nil }
        let prefixEnd = span.start + item.prefixLength
        let kept: String
        let rest: String
        if NSMaxRange(sel) <= prefixEnd {
            kept = ""
            rest = ns.substring(with: NSRange(location: prefixEnd, length: span.end - prefixEnd))
        } else {
            let keepEnd = max(prefixEnd, min(sel.location, span.end))
            kept = ns.substring(with: NSRange(location: prefixEnd, length: keepEnd - prefixEnd))
            let restStart = max(prefixEnd, NSMaxRange(sel))
            rest = restStart < span.end ? ns.substring(with: NSRange(location: restStart, length: span.end - restStart)) : ""
        }
        let empty = kept.trimmingCharacters(in: .whitespaces).isEmpty
            && rest.trimmingCharacters(in: .whitespaces).isEmpty
        if empty {
            let replacement: String
            if item.indent.isEmpty {
                replacement = item.quote
            } else {
                replacement = item.quote + outdent(item.indent) + item.marker
            }
            return TextEdit(
                range: NSRange(location: span.start, length: span.end - span.start),
                replacement: replacement,
                selection: NSRange(location: span.start + len(replacement), length: 0)
            )
        }
        let next = item.quote + item.indent + item.nextMarker
        let replacement = kept + "\n" + next + rest
        return TextEdit(
            range: NSRange(location: prefixEnd, length: span.end - prefixEnd),
            replacement: replacement,
            selection: NSRange(location: prefixEnd + len(kept) + 1 + len(next), length: 0)
        )
    }

    /// True when every non-blank selected line is a list item, and the selection
    /// isn't inside a fence or frontmatter. Tab / Shift-Tab use this to indent.
    public static func isListSelection(_ text: String, _ sel: NSRange) -> Bool {
        let ns = text as NSString
        let sel = EditCommands.clamp(sel, ns.length)
        if opaque(text, sel) { return false }
        let L = EditCommands.Lines(text)
        let (a, b) = L.span(sel)
        var found = false
        for i in a...b {
            let line = stripEnding(L.lines[i])
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            guard parse(line) != nil else { return false }
            found = true
        }
        return found
    }

    // MARK: Line

    /// The single line under `sel`, without its line break. Nil if the selection
    /// crosses a line break.
    static func lineSpan(_ ns: NSString, _ sel: NSRange) -> (start: Int, end: Int, line: String)? {
        let lr = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        var end = NSMaxRange(lr)
        if end > lr.location, ns.character(at: end - 1) == 10 { end -= 1 }
        if end > lr.location, ns.character(at: end - 1) == 13 { end -= 1 }
        if NSMaxRange(sel) > end { return nil }
        let line = ns.substring(with: NSRange(location: lr.location, length: end - lr.location))
        return (lr.location, end, line)
    }

    static func stripEnding(_ line: String) -> String {
        var s = line
        if s.hasSuffix("\r\n") { s.removeLast(2) }
        else if s.hasSuffix("\n") || s.hasSuffix("\r") { s.removeLast() }
        return s
    }

    // MARK: Parse

    struct Item {
        var quote: String
        var indent: String
        var marker: String
        var nextMarker: String
        var prefixLength: Int
    }

    static func parse(_ line: String) -> Item? {
        var i = line.startIndex
        var quote = ""
        while i < line.endIndex, line[i] == ">" {
            quote.append(">")
            i = line.index(after: i)
            if i < line.endIndex, line[i] == " " {
                quote.append(" ")
                i = line.index(after: i)
            }
        }
        var indent = ""
        while i < line.endIndex, line[i] == " " || line[i] == "\t" {
            indent.append(line[i])
            i = line.index(after: i)
        }
        let rest = line[i...]
        guard let (marker, next) = marker(rest) else { return nil }
        return Item(quote: quote, indent: indent, marker: marker, nextMarker: next,
                    prefixLength: len(quote) + len(indent) + len(marker))
    }

    /// The current marker and the one Return should write on the next line.
    static func marker(_ rest: Substring) -> (String, String)? {
        let s = String(rest)
        // Tasks first, so `- [ ] ` isn't taken as a plain bullet.
        if let m = s.firstMatch(of: #/^([-*+]) \[[^\]]\] /#) {
            let bullet = String(m.1)
            return (String(s[m.range]), "\(bullet) [ ] ")
        }
        if let m = s.firstMatch(of: #/^([-*+]) /#) {
            return (String(s[m.range]), String(s[m.range]))
        }
        if let m = s.firstMatch(of: #/^(\d+)([.)]) /#) {
            let n = Int(m.1) ?? 0
            let delim = String(m.2)
            return (String(s[m.range]), "\(n + 1)\(delim) ")
        }
        return nil
    }

    static func outdent(_ indent: String) -> String {
        if indent.hasPrefix("\t") { return String(indent.dropFirst()) }
        let spaces = indent.prefix(while: { $0 == " " }).count
        return String(indent.dropFirst(min(4, max(spaces, 1))))
    }

    /// Caret or selection inside YAML frontmatter or a fenced code block.
    static func opaque(_ text: String, _ sel: NSRange) -> Bool {
        if sel.location < Frontmatter.parse(text).bodyOffset { return true }
        let n = (text as NSString).length
        for r in NoteParser.codeRanges(text) {
            if sel.length == 0 {
                if insideFence(r, caret: sel.location, length: n, text: text) { return true }
            } else if NSIntersectionRange(r, sel).length > 0 {
                return true
            }
        }
        return false
    }

    /// A caret at EOF is still inside an unclosed fence, and still on a closing
    /// fence line when the file has no trailing newline.
    static func insideFence(_ r: NSRange, caret loc: Int, length n: Int, text: String) -> Bool {
        if loc >= r.location && loc < NSMaxRange(r) { return true }
        guard loc == n, NSMaxRange(r) == n, loc >= r.location else { return false }
        if !closesFence(text, r) { return true }
        return !text.hasSuffix("\n") && !text.hasSuffix("\r")
    }

    static func closesFence(_ text: String, _ r: NSRange) -> Bool {
        let ns = text as NSString
        var end = NSMaxRange(r)
        if end > r.location, ns.character(at: end - 1) == 10 { end -= 1 }
        if end > r.location, ns.character(at: end - 1) == 13 { end -= 1 }
        guard end > r.location else { return false }
        let lr = ns.lineRange(for: NSRange(location: end - 1, length: 0))
        var lineEnd = NSMaxRange(lr)
        if lineEnd > lr.location, ns.character(at: lineEnd - 1) == 10 { lineEnd -= 1 }
        if lineEnd > lr.location, ns.character(at: lineEnd - 1) == 13 { lineEnd -= 1 }
        let line = ns.substring(with: NSRange(location: lr.location, length: max(0, lineEnd - lr.location)))
        return NoteParser.fenceRegex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }

    static func len(_ s: String) -> Int { (s as NSString).length }
}
