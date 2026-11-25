import Foundation

/// Block- and word-level diffs of two Markdown notes, for a rendered (reader-style) preview.
/// Tables, fenced code, and mermaid stay atomic (the whole block is inserted or deleted).
/// Other blocks that only changed in place are word-diffed.
extension NoteDiff {
    public enum BlockKind: Equatable, Sendable {
        case frontmatter
        case heading(Int)
        case paragraph
        case listItem
        case task
        case blockquote
        case code(String)      // info-string language, possibly empty
        case mermaid
        case table
        case thematicBreak
        case html
        case blank

        /// No useful inline diff — show the whole block as added or removed.
        public var isAtomic: Bool {
            switch self {
            case .code, .mermaid, .table, .frontmatter, .thematicBreak, .html, .blank: return true
            default: return false
            }
        }

        public var name: String {
            switch self {
            case .frontmatter: return "frontmatter"
            case .heading: return "heading"
            case .paragraph: return "paragraph"
            case .listItem: return "listItem"
            case .task: return "task"
            case .blockquote: return "blockquote"
            case .code: return "code"
            case .mermaid: return "mermaid"
            case .table: return "table"
            case .thematicBreak: return "thematicBreak"
            case .html: return "html"
            case .blank: return "blank"
            }
        }
    }

    public enum SpanOp: String, Equatable, Sendable {
        case same, insert, delete
    }

    public struct Span: Equatable, Sendable {
        public var op: SpanOp
        public var text: String
        public init(op: SpanOp, text: String) { self.op = op; self.text = text }
    }

    public enum BlockOp: String, Equatable, Sendable {
        case equal, insert, delete, change, collapsed
    }

    /// One block in a rich diff: unchanged Markdown, a whole block added or removed, or an inline change.
    public struct RichBlock: Equatable, Sendable {
        public var op: BlockOp
        public var kind: BlockKind
        public var text: String
        public var spans: [Span]
        /// For `.collapsed` placeholders: how many source lines are hidden, and the segment index to expand.
        public var hiddenCount: Int
        public var segmentIndex: Int
        public init(op: BlockOp, kind: BlockKind, text: String, spans: [Span] = [], hiddenCount: Int = 0, segmentIndex: Int = 0) {
            self.op = op; self.kind = kind; self.text = text; self.spans = spans
            self.hiddenCount = hiddenCount; self.segmentIndex = segmentIndex
        }

        public var isChange: Bool { op != .equal && op != .collapsed }
    }

    /// A rendered-friendly diff of `old` (historical) against `new` (current).
    public static func rich(old: String, new: String) -> [RichBlock] {
        let a = splitMDBlocks(old)
        let b = splitMDBlocks(new)
        let rows = myers(a.map(\.text), b.map(\.text))
        var oi = 0, ni = 0
        var pendingDel: [MDBlock] = []
        var pendingIns: [MDBlock] = []
        var out: [RichBlock] = []
        func flush() {
            out += coalesce(pendingDel, pendingIns)
            pendingDel = []
            pendingIns = []
        }
        for row in rows {
            switch row {
            case .same:
                flush()
                if oi < a.count { out.append(RichBlock(op: .equal, kind: a[oi].kind, text: a[oi].text)) }
                oi += 1; ni += 1
            case .delete:
                if oi < a.count { pendingDel.append(a[oi]) }
                oi += 1
            case .insert:
                if ni < b.count { pendingIns.append(b[ni]) }
                ni += 1
            }
        }
        flush()
        return out
    }

    public static func richHasChanges(_ blocks: [RichBlock]) -> Bool {
        blocks.contains(where: \.isChange)
    }

    /// JSON-ready dictionaries for the reader payload (`payload.diff`).
    public static func richPayload(_ blocks: [RichBlock]) -> [[String: Any]] {
        blocks.map { b in
            var d: [String: Any] = ["op": b.op.rawValue, "kind": b.kind.name, "markdown": b.text]
            if case .heading(let level) = b.kind { d["level"] = level }
            if case .code(let lang) = b.kind { d["lang"] = lang }
            if b.op == .change {
                d["spans"] = b.spans.map { ["op": $0.op.rawValue, "text": $0.text] }
                d["inner"] = innerMarkdown(b)
            }
            if b.op == .collapsed {
                d["count"] = b.hiddenCount
                d["index"] = b.segmentIndex
            }
            return d
        }
    }

    // MARK: - Coalesce

    static func coalesce(_ dels: [MDBlock], _ inss: [MDBlock]) -> [RichBlock] {
        if dels.isEmpty { return inss.map { RichBlock(op: .insert, kind: $0.kind, text: $0.text) } }
        if inss.isEmpty { return dels.map { RichBlock(op: .delete, kind: $0.kind, text: $0.text) } }
        var used = Array(repeating: false, count: inss.count)
        var out: [RichBlock] = []
        for d in dels {
            if d.kind.isAtomic {
                out.append(RichBlock(op: .delete, kind: d.kind, text: d.text))
                continue
            }
            if let j = bestMatch(d, in: inss, used: used) {
                used[j] = true
                out.append(changed(from: d, to: inss[j]))
            } else {
                out.append(RichBlock(op: .delete, kind: d.kind, text: d.text))
            }
        }
        for (j, ins) in inss.enumerated() where !used[j] {
            out.append(RichBlock(op: .insert, kind: ins.kind, text: ins.text))
        }
        return out
    }

    static func bestMatch(_ d: MDBlock, in inss: [MDBlock], used: [Bool]) -> Int? {
        var best: (Int, Double)?
        for (j, ins) in inss.enumerated() where !used[j] {
            let s = similarity(d, ins)
            if s >= 0.4, best == nil || s > best!.1 { best = (j, s) }
        }
        return best?.0
    }

    static func similarity(_ a: MDBlock, _ b: MDBlock) -> Double {
        if a.kind.isAtomic || b.kind.isAtomic { return 0 }
        if !kindsCompatible(a.kind, b.kind) { return 0 }
        let wa = wordTokens(innerText(a))
        let wb = wordTokens(innerText(b))
        if wa.isEmpty && wb.isEmpty { return 1 }
        if wa.isEmpty || wb.isEmpty { return 0 }
        // Shared-word fraction of the longer side (LCS), so "Hello world" vs
        // "Hello there" still pairs (½) while unrelated short headings do not.
        let same = myers(wa, wb).reduce(0) { n, row in
            if case .same = row { return n + 1 }
            return n
        }
        return Double(same) / Double(max(wa.count, wb.count))
    }

    static func kindsCompatible(_ a: BlockKind, _ b: BlockKind) -> Bool {
        if a == b { return true }
        if case .heading = a, case .heading = b { return true }
        switch (a, b) {
        case (.listItem, .task), (.task, .listItem): return true
        case (.paragraph, .listItem), (.listItem, .paragraph): return true
        case (.paragraph, .task), (.task, .paragraph): return true
        default: return false
        }
    }

    static func changed(from a: MDBlock, to b: MDBlock) -> RichBlock {
        let kind = b.kind
        let before = innerText(a)
        let after = innerText(b)
        // Word-diff the visible inner text; the destination block's marks (heading level, list bullet) win.
        let spans = wordSpans(old: before, new: after)
        return RichBlock(op: .change, kind: kind, text: b.text, spans: spans)
    }

    /// Heading / list marker stripped, trailing newline stripped — the text to word-diff and to put in `<h*>`/`<li>`.
    static func innerText(_ b: MDBlock) -> String {
        innerText(b.text, kind: b.kind)
    }

    static func innerText(_ text: String, kind: BlockKind) -> String {
        var s = text
        if s.hasSuffix("\n") { s.removeLast() }
        switch kind {
        case .heading:
            if let r = s.range(of: #"^#{1,6}[ \t]+"#, options: .regularExpression) {
                s.removeSubrange(r)
            }
            if let r = s.range(of: #"[ \t]+#+\s*$"#, options: .regularExpression) {
                s.removeSubrange(r)
            }
            return s
        case .listItem, .task:
            if let r = s.range(of: #"^[ \t]*([-*+]|\d{1,9}[.)])[ \t]+"#, options: .regularExpression) {
                s.removeSubrange(r)
            }
            return s
        case .blockquote:
            let lines = s.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
                var l = String(line)
                if l.hasPrefix(">") {
                    l.removeFirst()
                    if l.hasPrefix(" ") { l.removeFirst() }
                }
                return l
            }
            return lines.joined(separator: "\n")
        default:
            return s
        }
    }

    static func innerMarkdown(_ b: RichBlock) -> String {
        innerText(b.text, kind: b.kind)
    }

    static func trailingNewline(_ s: String) -> String { s.hasSuffix("\n") ? "\n" : "" }

    static func wordSpans(old: String, new: String) -> [Span] {
        let a = tokenize(old)
        let b = tokenize(new)
        return myers(a, b).map { row in
            switch row {
            case .same(let t): return Span(op: .same, text: t)
            case .insert(let t): return Span(op: .insert, text: t)
            case .delete(let t): return Span(op: .delete, text: t)
            }
        }
    }

    /// Words, whitespace runs, and single punctuation / markup characters, so `**foo**` diffs the word and keeps the marks.
    public static func tokenize(_ s: String) -> [String] {
        var out: [String] = []
        var i = s.startIndex
        while i < s.endIndex {
            if s[i].isWhitespace {
                var j = i
                while j < s.endIndex && s[j].isWhitespace { j = s.index(after: j) }
                out.append(String(s[i..<j]))
                i = j
            } else if s[i].isLetter || s[i].isNumber {
                var j = i
                while j < s.endIndex && (s[j].isLetter || s[j].isNumber || s[j] == "'" || s[j] == "\u{2019}") {
                    j = s.index(after: j)
                }
                out.append(String(s[i..<j]))
                i = j
            } else {
                out.append(String(s[i]))
                i = s.index(after: i)
            }
        }
        return out
    }

    static func wordTokens(_ s: String) -> [String] {
        tokenize(s).filter { t in t.contains { $0.isLetter || $0.isNumber } }.map { $0.lowercased() }
    }

    // MARK: - Block split

    struct MDBlock: Equatable {
        var kind: BlockKind
        var text: String
    }

    /// The document as equal-op blocks (structure tests).
    public static func documentBlocks(_ source: String) -> [RichBlock] {
        splitMDBlocks(source).map { RichBlock(op: .equal, kind: $0.kind, text: $0.text) }
    }

    static func splitMDBlocks(_ source: String) -> [MDBlock] {
        if source.isEmpty { return [] }
        let lines = splitLines(source)
        var out: [MDBlock] = []
        var i = 0
        // Opening YAML frontmatter.
        if i < lines.count, isFenceDelim(lines[i], mark: "---") {
            var j = i + 1
            while j < lines.count, !isFenceDelim(lines[j], mark: "---") && !isFenceDelim(lines[j], mark: "...") { j += 1 }
            if j < lines.count {
                out.append(MDBlock(kind: .frontmatter, text: joined(lines[i...j], sourceHasTrailing: source.hasSuffix("\n") || j + 1 < lines.count)))
                i = j + 1
            }
        }
        while i < lines.count {
            let line = lines[i]
            if line.isEmpty {
                var j = i
                while j < lines.count, lines[j].isEmpty { j += 1 }
                out.append(MDBlock(kind: .blank, text: joined(lines[i..<j], sourceHasTrailing: source.hasSuffix("\n") || j < lines.count)))
                i = j
                continue
            }
            if let fence = fenceOpen(line) {
                var j = i + 1
                while j < lines.count, !fenceClose(lines[j], fence) { j += 1 }
                if j < lines.count { j += 1 }
                let text = joined(lines[i..<j], sourceHasTrailing: source.hasSuffix("\n") || j < lines.count)
                let lang = fence.lang.lowercased()
                let kind: BlockKind = lang == "mermaid" ? .mermaid : .code(fence.lang)
                out.append(MDBlock(kind: kind, text: text))
                i = j
                continue
            }
            if isThematicBreak(line) {
                out.append(MDBlock(kind: .thematicBreak, text: joined(lines[i...i], sourceHasTrailing: source.hasSuffix("\n") || i + 1 < lines.count)))
                i += 1
                continue
            }
            if headingLevel(line) != nil {
                let level = headingLevel(line)!
                out.append(MDBlock(kind: .heading(level), text: joined(lines[i...i], sourceHasTrailing: source.hasSuffix("\n") || i + 1 < lines.count)))
                i += 1
                continue
            }
            if isTableStart(lines, i) {
                var j = i + 1
                while j < lines.count, looksLikeTableRow(lines[j]) { j += 1 }
                out.append(MDBlock(kind: .table, text: joined(lines[i..<j], sourceHasTrailing: source.hasSuffix("\n") || j < lines.count)))
                i = j
                continue
            }
            if isListItem(line) {
                let (end, task) = listItemEnd(lines, i)
                let kind: BlockKind = task ? .task : .listItem
                out.append(MDBlock(kind: kind, text: joined(lines[i..<end], sourceHasTrailing: source.hasSuffix("\n") || end < lines.count)))
                i = end
                continue
            }
            if isBlockquote(line) {
                var j = i + 1
                while j < lines.count, isBlockquote(lines[j]) { j += 1 }
                out.append(MDBlock(kind: .blockquote, text: joined(lines[i..<j], sourceHasTrailing: source.hasSuffix("\n") || j < lines.count)))
                i = j
                continue
            }
            if isHTMLStart(line) {
                var j = i + 1
                while j < lines.count, !lines[j].isEmpty { j += 1 }
                out.append(MDBlock(kind: .html, text: joined(lines[i..<j], sourceHasTrailing: source.hasSuffix("\n") || j < lines.count)))
                i = j
                continue
            }
            // Paragraph: until a blank line or the start of another block.
            var j = i + 1
            while j < lines.count, !lines[j].isEmpty, !startsNewBlock(lines, j) { j += 1 }
            out.append(MDBlock(kind: .paragraph, text: joined(lines[i..<j], sourceHasTrailing: source.hasSuffix("\n") || j < lines.count)))
            i = j
        }
        return out
    }

    static func joined(_ slice: ArraySlice<String>, sourceHasTrailing: Bool) -> String {
        if slice.isEmpty { return "" }
        let body = slice.joined(separator: "\n")
        // Reconstruct: every line but the last in the file keeps its trailing newline.
        // `splitLines` already dropped a final empty string after a trailing newline.
        return sourceHasTrailing ? body + "\n" : body
    }

    static func isFenceDelim(_ line: String, mark: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == mark
    }

    struct Fence {
        var mark: Character
        var count: Int
        var lang: String
    }

    static func fenceOpen(_ line: String) -> Fence? {
        let t = String(line.drop(while: { $0 == " " || $0 == "\t" }))
        // CommonMark allows up to 3 spaces of indent; we accept a short indent.
        let indent = line.count - t.count
        guard indent <= 3 else { return nil }
        guard let ch = t.first, ch == "`" || ch == "~" else { return nil }
        var n = 0
        var i = t.startIndex
        while i < t.endIndex, t[i] == ch { n += 1; i = t.index(after: i) }
        guard n >= 3 else { return nil }
        let info = String(t[i...]).trimmingCharacters(in: .whitespaces)
        // A closing fence of the same char in the info string is not an opener; info can't contain the mark for backticks.
        if ch == "`", info.contains("`") { return nil }
        let lang = String(info.split(whereSeparator: { $0.isWhitespace }).first ?? "")
        return Fence(mark: ch, count: n, lang: lang)
    }

    static func fenceClose(_ line: String, _ open: Fence) -> Bool {
        let t = String(line.drop(while: { $0 == " " || $0 == "\t" }))
        let indent = line.count - t.count
        guard indent <= 3 else { return false }
        guard t.first == open.mark else { return false }
        var n = 0
        var i = t.startIndex
        while i < t.endIndex, t[i] == open.mark { n += 1; i = t.index(after: i) }
        guard n >= open.count else { return false }
        return String(t[i...]).trimmingCharacters(in: .whitespaces).isEmpty
    }

    static func isThematicBreak(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.count >= 3 else { return false }
        let chars = Set(t.filter { !$0.isWhitespace })
        guard chars.count == 1, let c = chars.first, c == "-" || c == "*" || c == "_" else { return false }
        // Don't treat a YAML-style `---` that's already consumed as frontmatter; here it's a rule.
        // A heading underline is not detected because we don't support setext.
        return t.filter { $0 == c }.count >= 3
    }

    static func headingLevel(_ line: String) -> Int? {
        let t = String(line.drop(while: { $0 == " " || $0 == "\t" }))
        guard t.hasPrefix("#") else { return nil }
        var n = 0
        var i = t.startIndex
        while i < t.endIndex, t[i] == "#" { n += 1; i = t.index(after: i) }
        guard n >= 1, n <= 6 else { return nil }
        if i == t.endIndex { return n }
        guard t[i] == " " || t[i] == "\t" else { return nil }
        return n
    }

    static func looksLikeTableRow(_ line: String) -> Bool {
        !line.isEmpty && line.contains("|")
    }

    static func isTableSep(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("|") || t.contains("-") else { return false }
        var sawDash = false
        for ch in t {
            if ch == "-" { sawDash = true; continue }
            if ch == "|" || ch == ":" || ch.isWhitespace { continue }
            return false
        }
        return sawDash
    }

    static func isTableStart(_ lines: [String], _ i: Int) -> Bool {
        guard looksLikeTableRow(lines[i]) else { return false }
        guard i + 1 < lines.count else { return false }
        return isTableSep(lines[i + 1])
    }

    static func isListItem(_ line: String) -> Bool {
        listItemPrefixLength(line) != nil
    }

    static func listItemPrefixLength(_ line: String) -> Int? {
        let ns = line as NSString
        let pat = #"^([ \t]{0,3})([-*+]|\d{1,9}[.)])([ \t]+)"#
        guard let r = try? NSRegularExpression(pattern: pat) else { return nil }
        let whole = NSRange(location: 0, length: ns.length)
        guard let m = r.firstMatch(in: line, range: whole), m.range.location == 0 else { return nil }
        return m.range.length
    }

    static func isTaskItem(_ line: String) -> Bool {
        guard let n = listItemPrefixLength(line) else { return false }
        let rest = String(line.dropFirst(n))
        return rest.hasPrefix("[ ]") || rest.hasPrefix("[x]") || rest.hasPrefix("[X]")
    }

    /// End index (exclusive) of the list item starting at `i`, and whether it's a task.
    static func listItemEnd(_ lines: [String], _ i: Int) -> (Int, Bool) {
        let prefix = listItemPrefixLength(lines[i]) ?? 0
        let task = isTaskItem(lines[i])
        var j = i + 1
        while j < lines.count {
            let line = lines[j]
            if line.isEmpty {
                // A blank followed by an indented continuation still belongs to the item.
                if j + 1 < lines.count, isIndentedContinuation(lines[j + 1], prefix: prefix), !isListItem(lines[j + 1]) {
                    j += 1
                    continue
                }
                break
            }
            if isListItem(line) { break }
            if startsNewBlock(lines, j) && !isIndentedContinuation(line, prefix: prefix) { break }
            if isIndentedContinuation(line, prefix: prefix) || !startsNewBlock(lines, j) {
                j += 1
                continue
            }
            break
        }
        return (j, task)
    }

    static func isIndentedContinuation(_ line: String, prefix: Int) -> Bool {
        if line.isEmpty { return false }
        var n = 0
        for ch in line {
            if ch == " " { n += 1 }
            else if ch == "\t" { n += 4 }
            else { break }
        }
        return n >= max(prefix, 2)
    }

    static func isBlockquote(_ line: String) -> Bool {
        let t = String(line.drop(while: { $0 == " " || $0 == "\t" }))
        return t.hasPrefix(">")
    }

    static func isHTMLStart(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("<"), t.count >= 2 else { return false }
        let second = t[t.index(after: t.startIndex)]
        return second.isLetter || second == "!" || second == "/" || second == "?"
    }

    static func startsNewBlock(_ lines: [String], _ i: Int) -> Bool {
        let line = lines[i]
        if line.isEmpty { return true }
        if fenceOpen(line) != nil { return true }
        if isThematicBreak(line) { return true }
        if headingLevel(line) != nil { return true }
        if isTableStart(lines, i) { return true }
        if isListItem(line) { return true }
        if isBlockquote(line) { return true }
        if isHTMLStart(line) { return true }
        return false
    }

    // MARK: - Line numbers and collapsed context

    /// A diff line with 1-based numbers in the old and new sides (nil on the side that has no line).
    public struct NumberedLine: Equatable, Sendable {
        public var line: Line
        public var oldNumber: Int?
        public var newNumber: Int?
        public init(line: Line, oldNumber: Int?, newNumber: Int?) {
            self.line = line; self.oldNumber = oldNumber; self.newNumber = newNumber
        }
        public var isChange: Bool { line.isChange }
    }

    public static func numbered(_ rows: [Line]) -> [NumberedLine] {
        var o = 1, n = 1
        return rows.map { row in
            switch row {
            case .same:
                let item = NumberedLine(line: row, oldNumber: o, newNumber: n)
                o += 1; n += 1
                return item
            case .delete:
                let item = NumberedLine(line: row, oldNumber: o, newNumber: nil)
                o += 1
                return item
            case .insert:
                let item = NumberedLine(line: row, oldNumber: nil, newNumber: n)
                n += 1
                return item
            }
        }
    }

    /// A visible row, or a hidden stretch of unchanged rows that can be expanded.
    public enum CollapsedSegment<Element: Equatable>: Equatable {
        case visible(Element)
        case hunk(count: Int, items: [Element])
    }

    /// Keep `context` unchanged rows beside each change and collapse a longer stretch in the middle.
    /// A hidden run shorter than `minHidden` is left visible.
    public static func collapsed<Element: Equatable>(
        _ rows: [Element],
        isChange: (Element) -> Bool,
        context: Int = 3,
        minHidden: Int = 5
    ) -> [CollapsedSegment<Element>] {
        guard !rows.isEmpty else { return [] }
        let context = max(0, context)
        let minHidden = max(1, minHidden)
        var shown = Array(repeating: false, count: rows.count)
        var anyChange = false
        for i in rows.indices where isChange(rows[i]) {
            anyChange = true
            let lo = max(0, i - context)
            let hi = min(rows.count - 1, i + context)
            for j in lo...hi { shown[j] = true }
        }
        if !anyChange {
            if rows.count >= minHidden {
                return [.hunk(count: rows.count, items: rows)]
            }
            return rows.map { .visible($0) }
        }
        var out: [CollapsedSegment<Element>] = []
        var i = 0
        while i < rows.count {
            if shown[i] {
                out.append(.visible(rows[i]))
                i += 1
                continue
            }
            var j = i
            while j < rows.count, !shown[j] { j += 1 }
            let items = Array(rows[i..<j])
            if items.count >= minHidden {
                out.append(.hunk(count: items.count, items: items))
            } else {
                out.append(contentsOf: items.map { .visible($0) })
            }
            i = j
        }
        return out
    }

    /// How many source lines a rich-diff block occupies (for “Show N unchanged lines”).
    public static func lineCount(of block: RichBlock) -> Int {
        max(1, splitLines(block.text).count)
    }
}
