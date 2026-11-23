import Foundation

/// Format GitHub release notes for the update window: rewrite relative Markdown
/// links so they open the file at that tag on GitHub, and parse the body into
/// headings, lists, and paragraphs. Inline bold, italic, code, and links are
/// left as Markdown for `attributed(_:)`.
public enum ReleaseNotes {
    public static let defaultRepo = "kennethreitz/onyx"

    public enum Block: Equatable {
        case heading(level: Int, text: String)
        /// `depth` is 0 for a top-level item; `ordered` and `marker` describe `-`/`*` or `1.`.
        case listItem(depth: Int, ordered: Bool, marker: String, text: String)
        case paragraph(String)
        case rule
    }

    /// Rewrite relative Markdown destinations to `https://github.com/<repo>/blob/<tag>/<path>`.
    /// `#anchors` go to the release page. Absolute URLs, and anything inside
    /// inline code or fenced blocks, are left alone.
    public static func rewriteLinks(_ markdown: String, tag: String, repo: String = defaultRepo) -> String {
        let tag = normalizedTag(tag)
        let code = codeRanges(in: markdown)
        var out = ""
        var i = markdown.startIndex
        var c = 0
        while i < markdown.endIndex {
            while c < code.count && code[c].upperBound <= i { c += 1 }
            if c < code.count, code[c].contains(i) {
                out += markdown[i..<code[c].upperBound]
                i = code[c].upperBound
                c += 1
                continue
            }
            if markdown[i] == "[" || (markdown[i] == "!" && peek(markdown, i) == "[") {
                if let link = readLink(markdown, at: i) {
                    out += link.lead + absolutize(link.dest, tag: tag, repo: repo) + link.trail
                    i = link.end
                    continue
                }
            }
            if isLineStart(markdown, i), let def = readRefDef(markdown, at: i) {
                out += def.lead + absolutize(def.dest, tag: tag, repo: repo) + def.trail
                i = def.end
                continue
            }
            out.append(markdown[i])
            markdown.formIndex(after: &i)
        }
        return out
    }

    /// Turn a Markdown destination into an absolute GitHub URL when it is relative.
    public static func absolutize(_ dest: String, tag: String, repo: String = defaultRepo) -> String {
        let raw = dest.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return dest }
        let tag = normalizedTag(tag)
        if let url = URL(string: raw), let scheme = url.scheme, !scheme.isEmpty {
            return raw
        }
        if raw.hasPrefix("//") { return "https:" + raw }
        if raw.hasPrefix("#") {
            return "https://github.com/\(repo)/releases/tag/\(tag)\(raw)"
        }
        var rest = raw
        var fragment = ""
        var query = ""
        if let h = rest.firstIndex(of: "#") {
            fragment = String(rest[h...])
            rest = String(rest[..<h])
        }
        if let q = rest.firstIndex(of: "?") {
            query = String(rest[q...])
            rest = String(rest[..<q])
        }
        if rest.hasPrefix("./") { rest.removeFirst(2) }
        while rest.hasPrefix("/") { rest.removeFirst() }
        let decoded = rest.removingPercentEncoding ?? rest
        var parts: [String] = []
        for part in decoded.split(separator: "/", omittingEmptySubsequences: false).map(String.init) {
            if part.isEmpty || part == "." { continue }
            if part == ".." {
                if !parts.isEmpty { parts.removeLast() }
                continue
            }
            parts.append(part)
        }
        let encoded = parts.map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0 }.joined(separator: "/")
        return "https://github.com/\(repo)/blob/\(tag)/\(encoded)\(query)\(fragment)"
    }

    public static func normalizedTag(_ tag: String) -> String {
        Semver.parse(tag)?.tagged ?? tag
    }

    /// Parse Markdown into blocks. Headings become section labels; lists keep nest depth.
    public static func blocks(_ markdown: String) -> [Block] {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var out: [Block] = []
        var para: [String] = []
        func flush() {
            let t = para.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { out.append(.paragraph(t)) }
            para.removeAll()
        }
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flush()
                i += 1
                continue
            }
            if let h = heading(line) {
                flush()
                out.append(.heading(level: h.level, text: h.text))
                i += 1
                continue
            }
            if isRule(line) {
                flush()
                out.append(.rule)
                i += 1
                continue
            }
            if let item = listItem(line) {
                flush()
                var text = item.text
                i += 1
                while i < lines.count {
                    let next = lines[i]
                    if next.trimmingCharacters(in: .whitespaces).isEmpty { break }
                    if heading(next) != nil || isRule(next) || listItem(next) != nil { break }
                    let lead = leadingSpaces(next)
                    // A continuation is indented past the marker; otherwise it's a new paragraph.
                    if lead < item.indent + 2 { break }
                    text += " " + String(next.drop(while: { $0 == " " || $0 == "\t" }))
                    i += 1
                }
                out.append(.listItem(depth: item.depth, ordered: item.ordered, marker: item.marker, text: text))
                continue
            }
            para.append(line)
            i += 1
        }
        flush()
        return out
    }

    /// Rewrite relative links, then parse. This is what the update window displays.
    public static func blocks(from markdown: String, tag: String, repo: String = defaultRepo) -> [Block] {
        blocks(rewriteLinks(markdown, tag: tag, repo: repo))
    }

    /// Inline Markdown (bold, italic, code, links) as an `AttributedString`.
    public static func attributed(_ inlineMarkdown: String) -> AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        if let parsed = try? AttributedString(markdown: inlineMarkdown, options: opts) {
            return parsed
        }
        return AttributedString(inlineMarkdown)
    }

    // MARK: - Blocks

    static func heading(_ line: String) -> (level: Int, text: String)? {
        let t = line
        var i = t.startIndex
        var spaces = 0
        while i < t.endIndex, t[i] == " ", spaces < 3 {
            spaces += 1
            t.formIndex(after: &i)
        }
        var level = 0
        while i < t.endIndex, t[i] == "#", level < 6 {
            level += 1
            t.formIndex(after: &i)
        }
        guard level > 0, i < t.endIndex, t[i] == " " || t[i] == "\t" else { return nil }
        var text = String(t[i...]).trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("#") {
            text.removeLast()
            text = text.trimmingCharacters(in: .whitespaces)
        }
        guard !text.isEmpty else { return nil }
        return (level, text)
    }

    static func isRule(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.count >= 3 else { return false }
        let chars = Set(t.filter { $0 != " " && $0 != "\t" })
        return chars.count == 1 && (chars.contains("-") || chars.contains("*") || chars.contains("_"))
            && t.filter { $0 == "-" || $0 == "*" || $0 == "_" }.count >= 3
            && t.allSatisfy { $0 == "-" || $0 == "*" || $0 == "_" || $0 == " " || $0 == "\t" }
    }

    static func listItem(_ line: String) -> (indent: Int, depth: Int, ordered: Bool, marker: String, text: String)? {
        let indent = leadingSpaces(line)
        var i = line.index(line.startIndex, offsetBy: rawLeadCount(line))
        guard i < line.endIndex else { return nil }
        var ordered = false
        var marker = ""
        if line[i] == "-" || line[i] == "*" || line[i] == "+" {
            marker = String(line[i])
            line.formIndex(after: &i)
        } else if line[i].isNumber {
            var digits = ""
            while i < line.endIndex, line[i].isNumber {
                digits.append(line[i])
                line.formIndex(after: &i)
            }
            guard i < line.endIndex, line[i] == "." else { return nil }
            line.formIndex(after: &i)
            ordered = true
            marker = digits
        } else {
            return nil
        }
        guard i < line.endIndex, line[i] == " " || line[i] == "\t" else { return nil }
        let text = String(line[i...]).trimmingCharacters(in: .whitespaces)
        return (indent, indent / 2, ordered, marker, text)
    }

    static func leadingSpaces(_ line: String) -> Int {
        var n = 0
        for ch in line {
            if ch == " " { n += 1 }
            else if ch == "\t" { n += 4 }
            else { break }
        }
        return n
    }

    static func rawLeadCount(_ line: String) -> Int {
        var n = 0
        for ch in line {
            if ch == " " || ch == "\t" { n += 1 } else { break }
        }
        return n
    }

    // MARK: - Links and code

    struct Piece {
        var lead: String
        var dest: String
        var trail: String
        var end: String.Index
    }

    static func readLink(_ s: String, at start: String.Index) -> Piece? {
        var i = start
        var lead = ""
        if s[i] == "!" {
            lead.append("!")
            s.formIndex(after: &i)
        }
        guard i < s.endIndex, s[i] == "[" else { return nil }
        lead.append("[")
        s.formIndex(after: &i)
        var depth = 1
        var text = ""
        var escaped = false
        while i < s.endIndex {
            let ch = s[i]
            if escaped { text.append(ch); escaped = false; s.formIndex(after: &i); continue }
            if ch == "\\" { text.append(ch); escaped = true; s.formIndex(after: &i); continue }
            if ch == "[" { depth += 1; text.append(ch); s.formIndex(after: &i); continue }
            if ch == "]" {
                depth -= 1
                s.formIndex(after: &i)
                if depth == 0 { break }
                text.append("]")
                continue
            }
            if ch == "\n" { return nil }
            text.append(ch)
            s.formIndex(after: &i)
        }
        guard depth == 0 else { return nil }
        lead += text + "]"
        guard i < s.endIndex, s[i] == "(" else { return nil }
        lead.append("(")
        s.formIndex(after: &i)
        while i < s.endIndex, s[i] == " " || s[i] == "\t" || s[i] == "\n" {
            lead.append(s[i])
            s.formIndex(after: &i)
        }
        guard i < s.endIndex else { return nil }
        let angled = s[i] == "<"
        var dest = ""
        if angled {
            lead.append("<")
            s.formIndex(after: &i)
            while i < s.endIndex, s[i] != ">" {
                if s[i] == "\n" { return nil }
                dest.append(s[i])
                s.formIndex(after: &i)
            }
            guard i < s.endIndex, s[i] == ">" else { return nil }
            s.formIndex(after: &i)
        } else {
            var pdepth = 0
            while i < s.endIndex {
                let ch = s[i]
                if ch == "(" { pdepth += 1 }
                if ch == ")" {
                    if pdepth == 0 { break }
                    pdepth -= 1
                }
                if pdepth == 0 && (ch == " " || ch == "\t" || ch == "\n") { break }
                dest.append(ch)
                s.formIndex(after: &i)
            }
        }
        guard !dest.isEmpty else { return nil }
        var trail = angled ? ">" : ""
        while i < s.endIndex, s[i] == " " || s[i] == "\t" || s[i] == "\n" {
            trail.append(s[i])
            s.formIndex(after: &i)
        }
        if i < s.endIndex, s[i] == "\"" || s[i] == "'" || s[i] == "(" {
            let close: Character = s[i] == "(" ? ")" : s[i]
            trail.append(s[i])
            s.formIndex(after: &i)
            while i < s.endIndex, s[i] != close {
                if s[i] == "\n" { return nil }
                trail.append(s[i])
                s.formIndex(after: &i)
            }
            guard i < s.endIndex else { return nil }
            trail.append(s[i])
            s.formIndex(after: &i)
            while i < s.endIndex, s[i] == " " || s[i] == "\t" || s[i] == "\n" {
                trail.append(s[i])
                s.formIndex(after: &i)
            }
        }
        guard i < s.endIndex, s[i] == ")" else { return nil }
        trail.append(")")
        s.formIndex(after: &i)
        return Piece(lead: lead, dest: dest, trail: trail, end: i)
    }

    /// `[label]: dest` at the start of a line.
    static func readRefDef(_ s: String, at start: String.Index) -> Piece? {
        guard isLineStart(s, start), start < s.endIndex, s[start] == "[" else { return nil }
        var i = start
        var lead = "["
        s.formIndex(after: &i)
        var label = ""
        while i < s.endIndex, s[i] != "]" {
            if s[i] == "\n" { return nil }
            label.append(s[i])
            s.formIndex(after: &i)
        }
        guard i < s.endIndex, !label.isEmpty else { return nil }
        lead += label + "]"
        s.formIndex(after: &i)
        guard i < s.endIndex, s[i] == ":" else { return nil }
        lead.append(":")
        s.formIndex(after: &i)
        while i < s.endIndex, s[i] == " " || s[i] == "\t" {
            lead.append(s[i])
            s.formIndex(after: &i)
        }
        guard i < s.endIndex, s[i] != "\n" else { return nil }
        let angled = s[i] == "<"
        var dest = ""
        if angled {
            lead.append("<")
            s.formIndex(after: &i)
            while i < s.endIndex, s[i] != ">" {
                if s[i] == "\n" { return nil }
                dest.append(s[i])
                s.formIndex(after: &i)
            }
            guard i < s.endIndex else { return nil }
            s.formIndex(after: &i)
        } else {
            while i < s.endIndex, s[i] != " " && s[i] != "\t" && s[i] != "\n" {
                dest.append(s[i])
                s.formIndex(after: &i)
            }
        }
        guard !dest.isEmpty else { return nil }
        let trail = angled ? ">" : ""
        return Piece(lead: lead, dest: dest, trail: trail, end: i)
    }

    static func isLineStart(_ s: String, _ i: String.Index) -> Bool {
        i == s.startIndex || s[s.index(before: i)] == "\n"
    }

    static func peek(_ s: String, _ i: String.Index) -> Character? {
        let n = s.index(after: i)
        return n < s.endIndex ? s[n] : nil
    }

    static func codeRanges(in s: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var i = s.startIndex
        var lineStart = true
        while i < s.endIndex {
            if lineStart {
                var j = i
                var pad = 0
                while j < s.endIndex, s[j] == " ", pad < 3 {
                    pad += 1
                    s.formIndex(after: &j)
                }
                if j < s.endIndex, s[j] == "`" || s[j] == "~" {
                    let ch = s[j]
                    var k = j
                    var n = 0
                    while k < s.endIndex, s[k] == ch { n += 1; s.formIndex(after: &k) }
                    if n >= 3 {
                        // skip the rest of the opening line, then look for a matching close
                        while k < s.endIndex, s[k] != "\n" { s.formIndex(after: &k) }
                        if k < s.endIndex { s.formIndex(after: &k) } // past the newline
                        var close = k
                        var found: String.Index?
                        while close < s.endIndex {
                            let bol = close
                            var p = close
                            var cpad = 0
                            while p < s.endIndex, s[p] == " ", cpad < 3 {
                                cpad += 1
                                s.formIndex(after: &p)
                            }
                            var m = 0
                            while p < s.endIndex, s[p] == ch { m += 1; s.formIndex(after: &p) }
                            if m >= n {
                                while p < s.endIndex, s[p] == " " || s[p] == "\t" { s.formIndex(after: &p) }
                                if p == s.endIndex || s[p] == "\n" {
                                    found = p == s.endIndex ? p : s.index(after: p)
                                    break
                                }
                            }
                            while close < s.endIndex, s[close] != "\n" { s.formIndex(after: &close) }
                            if close < s.endIndex { s.formIndex(after: &close) }
                            _ = bol
                        }
                        let end = found ?? s.endIndex
                        ranges.append(i..<end)
                        i = end
                        lineStart = true
                        continue
                    }
                }
            }
            if s[i] == "`" {
                var k = i
                var n = 0
                while k < s.endIndex, s[k] == "`" { n += 1; s.formIndex(after: &k) }
                var j = k
                var run = 0
                var found: String.Index?
                while j < s.endIndex {
                    if s[j] == "`" {
                        run += 1
                        s.formIndex(after: &j)
                        if run == n {
                            let more = j < s.endIndex && s[j] == "`"
                            if !more { found = j; break }
                        }
                    } else {
                        run = 0
                        s.formIndex(after: &j)
                    }
                }
                if let end = found {
                    ranges.append(i..<end)
                    i = end
                    lineStart = false
                    continue
                }
            }
            lineStart = s[i] == "\n"
            s.formIndex(after: &i)
        }
        return ranges
    }
}
