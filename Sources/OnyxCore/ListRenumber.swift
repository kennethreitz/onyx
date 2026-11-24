import Foundation

/// Renumber a contiguous ordered list after an edit: Return, indent / outdent,
/// delete-line, or a nearby deletion. Pure text in, `TextEdit` out, so it
/// composes with `ListContinue` and `EditCommands` as one undo step. Ranges
/// are UTF-16, like NSTextView.
public enum ListRenumber {

    /// Apply `edit`, then fix numbered items in the lists that touch it.
    /// Returns `edit` unchanged when the numbers are already right.
    public static func applying(_ edit: TextEdit, to text: String) -> TextEdit {
        let after = edit.applied(to: text)
        let n = (after as NSString).length
        let start = max(0, edit.range.location - 1)
        let end = min(n, edit.range.location + ListContinue.len(edit.replacement))
        let cover = NSRange(location: start, length: max(0, end - start))
        let origin = Origin(before: text, edit: edit)
        guard let fix = rewrite(after, covering: cover, selection: edit.selection, origin: origin) else { return edit }
        return coalesce(from: text, to: fix.applied(to: after), selection: fix.selection)
    }

    /// A follow-up edit that only changes markers, for Backspace / Delete / cut
    /// after the deletion has already been applied. Nil when nothing needs fixing.
    /// Pass `from:` (the text before the deletion) so a list that lost its first
    /// item can keep the original starting number.
    public static func afterChange(_ text: String, selection: NSRange, from before: String? = nil) -> TextEdit? {
        let sel = EditCommands.clamp(selection, (text as NSString).length)
        var origin: Origin?
        var coverStart = max(0, sel.location - 1)
        var coverEnd = NSMaxRange(sel)
        if let before, before != text {
            let edit = coalesce(from: before, to: text, selection: sel)
            origin = Origin(before: before, edit: edit)
            coverStart = max(0, edit.range.location - 1)
            coverEnd = min((text as NSString).length, edit.range.location + ListContinue.len(edit.replacement))
        }
        let cover = NSRange(location: coverStart, length: max(0, coverEnd - coverStart))
        return rewrite(text, covering: cover, selection: sel, origin: origin)
    }

    // MARK: Rewrite

    static func rewrite(_ text: String, covering: NSRange, selection: NSRange, origin: Origin? = nil) -> TextEdit? {
        let (final, sel) = renumbered(text, covering: covering, selection: selection, origin: origin)
        if final == text { return nil }
        return coalesce(from: text, to: final, selection: sel)
    }

    static func renumbered(_ text: String, covering: NSRange, selection: NSRange, origin: Origin? = nil) -> (String, NSRange) {
        let L = EditCommands.Lines(text)
        guard !L.lines.isEmpty else { return (text, selection) }
        let (a, b0) = L.span(covering)
        let b = extend(from: a, through: b0, in: L, text: text)
        var seen = Set<Int>()
        var changes: [Change] = []
        for i in a...b {
            collect(line: i, in: L, text: text, seen: &seen, changes: &changes, origin: origin)
        }
        guard !changes.isEmpty else { return (text, selection) }
        return apply(changes, to: text, selection: selection)
    }

    /// After indenting the first item of a list, the siblings left behind sit
    /// just after the edited block and would otherwise be missed.
    static func extend(from a: Int, through b: Int, in L: EditCommands.Lines, text: String) -> Int {
        var floor: (quote: String, indent: String)?
        for i in a...b {
            guard !opaque(text, L, i) else { continue }
            let line = info(L.lines[i])
            if let f = floor {
                if !deeper(line, than: f) { floor = (line.quote, line.indent) }
            } else {
                floor = (line.quote, line.indent)
            }
        }
        var end = b
        var i = b + 1
        while i < L.lines.count {
            if isBlank(L.lines[i]) { break }
            if opaque(text, L, i) { break }
            let line = info(L.lines[i])
            if let f = floor, deeper(line, than: f) { i += 1; continue }
            if line.number != nil, floor == nil || !deeper(line, than: floor!) {
                end = i
                i += 1
                continue
            }
            break
        }
        return end
    }

    static func collect(line i: Int, in L: EditCommands.Lines, text: String,
                        seen: inout Set<Int>, changes: inout [Change], origin: Origin?) {
        guard numbered(L.lines[i]) != nil, !opaque(text, L, i) else { return }
        guard let items = list(containing: i, in: L, text: text), let first = items.first else { return }
        if seen.contains(first) { return }
        seen.insert(first)
        var n = startNumber(items, in: L, text: text, origin: origin)
        for j in items {
            guard let cur = numbered(L.lines[j]) else { continue }
            if cur.number != n {
                let prefix = ListContinue.len(cur.quote) + ListContinue.len(cur.indent)
                changes.append(Change(
                    markerStart: L.starts[j] + prefix,
                    oldLen: ListContinue.len(cur.marker),
                    newMarker: "\(n)\(cur.delimiter) "
                ))
            }
            n += 1
        }
    }

    /// Same-level numbered items of the contiguous list that contains `i`.
    /// A blank line, a fence, frontmatter, a shallower line, or a same-indent
    /// non-numbered line ends the list. Deeper lines (nested items or
    /// continuations) are skipped. The first item's number is the start of
    /// the sequence.
    static func list(containing i: Int, in L: EditCommands.Lines, text: String) -> [Int]? {
        guard let seed = numbered(L.lines[i]), !opaque(text, L, i) else { return nil }
        var lo = i
        back: while lo > 0 {
            switch classify(L.lines[lo - 1], seed, text: text, line: lo - 1, L: L) {
            case .item, .skip: lo -= 1
            case .blank, .stop: break back
            }
        }
        var items: [Int] = []
        var j = lo
        while j < L.lines.count {
            switch classify(L.lines[j], seed, text: text, line: j, L: L) {
            case .item: items.append(j); j += 1
            case .skip: j += 1
            case .blank, .stop: j = L.lines.count
            }
        }
        return items.isEmpty ? nil : items
    }

    // MARK: Starting number

    struct Origin {
        var before: String
        var edit: TextEdit
    }

    /// The list's original start, when a remaining item was already at this
    /// indent before the edit. If every item just arrived from a shallower
    /// indent (a newly nested list), start at 1.
    static func startNumber(_ items: [Int], in L: EditCommands.Lines, text: String, origin: Origin?) -> Int {
        guard let first = items.first, let seed = numbered(L.lines[first]) else { return 1 }
        guard let origin else { return seed.number }
        for j in items {
            guard let cur = numbered(L.lines[j]) else { continue }
            guard let prior = priorInfo(lineStart: L.starts[j], after: text, origin: origin) else { continue }
            guard prior.quote == cur.quote, prior.indent == cur.indent else { continue }
            let oldL = EditCommands.Lines(origin.before)
            guard let oldLoc = mapBack(L.starts[j], origin) else { return cur.number }
            let oldIdx = oldL.index(at: min(oldLoc, max(0, oldL.length)))
            if let oldItems = list(containing: oldIdx, in: oldL, text: origin.before),
               let n = numbered(oldL.lines[oldItems[0]]) {
                return n.number
            }
            return cur.number
        }
        return 1
    }

    /// Quote and indent of the corresponding pre-edit line, if this line existed then.
    static func priorInfo(lineStart: Int, after: String, origin: Origin) -> Info? {
        let s = origin.edit.range.location
        let newLen = ListContinue.len(origin.edit.replacement)
        if lineStart < s || lineStart >= s + newLen {
            guard let oldLoc = mapBack(lineStart, origin) else { return nil }
            let L = EditCommands.Lines(origin.before)
            guard !L.lines.isEmpty else { return nil }
            return info(L.lines[L.index(at: min(max(0, oldLoc), L.length))])
        }
        let newL = EditCommands.Lines(origin.edit.replacement)
        let oldL = EditCommands.Lines((origin.before as NSString).substring(with: origin.edit.range))
        let idx = newL.index(at: max(0, lineStart - s))
        if newL.lines.count == oldL.lines.count, idx < oldL.lines.count {
            return info(oldL.lines[idx])
        }
        if oldL.lines.count >= 1, idx == 0 {
            return info(oldL.lines[0])
        }
        return nil
    }

    /// Map a location in the post-edit text back into `origin.before`. Nil when
    /// the location sits inside inserted text that has no pre-edit counterpart.
    static func mapBack(_ afterLoc: Int, _ origin: Origin) -> Int? {
        let s = origin.edit.range.location
        let newLen = ListContinue.len(origin.edit.replacement)
        let oldLen = origin.edit.range.length
        if afterLoc < s { return afterLoc }
        if afterLoc >= s + newLen { return afterLoc - newLen + oldLen }
        if newLen == 0 { return s }
        // Inside the replacement: map by line index when the line counts match
        // (indent / outdent), otherwise pin to the start of the old range.
        let newL = EditCommands.Lines(origin.edit.replacement)
        let oldBlock = (origin.before as NSString).substring(with: origin.edit.range)
        let oldL = EditCommands.Lines(oldBlock)
        let idx = newL.index(at: max(0, afterLoc - s))
        if newL.lines.count == oldL.lines.count, idx < oldL.starts.count {
            return s + oldL.starts[idx]
        }
        if idx == 0 { return s }
        return nil
    }

    // MARK: Line

    struct Numbered {
        var quote: String
        var indent: String
        var number: Int
        var delimiter: String
        var marker: String
    }

    struct Info {
        var quote: String
        var indent: String
        var number: Int?
        var delimiter: String
        var marker: String
    }

    struct Change {
        var markerStart: Int
        var oldLen: Int
        var newMarker: String
    }

    enum Kind { case item, skip, blank, stop }

    static func info(_ line: String) -> Info {
        let raw = ListContinue.stripEnding(line)
        let lead = ListContinue.lead(raw)
        if let n = numbered(raw) {
            return Info(quote: n.quote, indent: n.indent, number: n.number,
                        delimiter: n.delimiter, marker: n.marker)
        }
        return Info(quote: lead.quote, indent: lead.indent, number: nil, delimiter: "", marker: "")
    }

    static func numbered(_ line: String) -> Numbered? {
        let raw = ListContinue.stripEnding(line)
        guard let item = ListContinue.parse(raw) else { return nil }
        guard let m = item.marker.firstMatch(of: #/^(\d+)([.)]) $/#) else { return nil }
        return Numbered(quote: item.quote, indent: item.indent, number: Int(m.1) ?? 0,
                        delimiter: String(m.2), marker: item.marker)
    }

    static func classify(_ line: String, _ seed: Numbered, text: String, line i: Int, L: EditCommands.Lines) -> Kind {
        if isBlank(line) { return .blank }
        if opaque(text, L, i) { return .stop }
        let line = info(line)
        if line.quote != seed.quote { return .stop }
        if line.indent == seed.indent {
            return line.number != nil ? .item : .stop
        }
        if line.indent.hasPrefix(seed.indent) { return .skip }
        return .stop
    }

    static func deeper(_ line: Info, than floor: (quote: String, indent: String)) -> Bool {
        line.quote == floor.quote && line.indent.hasPrefix(floor.indent) && line.indent != floor.indent
    }

    /// A line with no content past its quote prefix and whitespace. Those
    /// break a list, so two ordered lists separated by a blank stay independent.
    static func isBlank(_ line: String) -> Bool {
        let lead = ListContinue.lead(ListContinue.stripEnding(line))
        return lead.rest.trimmingCharacters(in: .whitespaces).isEmpty
    }

    static func opaque(_ text: String, _ L: EditCommands.Lines, _ i: Int) -> Bool {
        ListContinue.opaque(text, NSRange(location: L.starts[i], length: 0))
    }

    // MARK: Apply

    static func apply(_ changes: [Change], to text: String, selection: NSRange) -> (String, NSRange) {
        let changes = changes.sorted { $0.markerStart < $1.markerStart }
        let ns = text as NSString
        var parts: [String] = []
        var cursor = 0
        for c in changes {
            if c.markerStart > cursor {
                parts.append(ns.substring(with: NSRange(location: cursor, length: c.markerStart - cursor)))
            }
            parts.append(c.newMarker)
            cursor = c.markerStart + c.oldLen
        }
        if cursor < ns.length {
            parts.append(ns.substring(from: cursor))
        }
        let final = parts.joined()
        let loc = map(selection.location, changes)
        let end = map(NSMaxRange(selection), changes)
        let n = (final as NSString).length
        let a = max(0, min(loc, n))
        let b = max(a, min(end, n))
        return (final, NSRange(location: a, length: b - a))
    }

    /// Map a caret in the original text past marker-width changes. A caret
    /// inside a rewritten marker lands at the end of the new one (start of the item text).
    static func map(_ pos: Int, _ changes: [Change]) -> Int {
        var delta = 0
        for c in changes {
            let newLen = ListContinue.len(c.newMarker)
            if pos <= c.markerStart { return pos + delta }
            if pos >= c.markerStart + c.oldLen {
                delta += newLen - c.oldLen
            } else {
                return c.markerStart + delta + newLen
            }
        }
        return pos + delta
    }

    /// Smallest replacement that turns `text` into `final`, with `selection`
    /// already in the new coordinates.
    static func coalesce(from text: String, to final: String, selection: NSRange) -> TextEdit {
        let a = text as NSString, b = final as NSString
        var i = 0
        while i < a.length, i < b.length, a.character(at: i) == b.character(at: i) { i += 1 }
        var ta = a.length, tb = b.length
        while ta > i, tb > i, a.character(at: ta - 1) == b.character(at: tb - 1) {
            ta -= 1
            tb -= 1
        }
        let range = NSRange(location: i, length: ta - i)
        let replacement = b.substring(with: NSRange(location: i, length: tb - i))
        return TextEdit(range: range, replacement: replacement, selection: selection)
    }
}
