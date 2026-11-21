import Foundation

/// One Markdown lint rule: a pure text transform with a stable id and a default.
public struct LintRule: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var description: String
    public var defaultOn: Bool

    /// Apply this rule alone. Options and clock are explicit for deterministic tests.
    public func transform(_ text: String, config: LinterConfig = .default, now: Date = Date()) -> String {
        var one = config; one.enabled = [id]
        return Linter.lint(text, config: one, now: now)
    }
}

/// Which rules run, plus the few rule options. Persisted by the app in UserDefaults.
public struct LinterConfig: Equatable, Sendable {
    public var enabled: Set<String>
    /// Trailing whitespace: keep a run of 2+ spaces after text as exactly two (a Markdown hard break).
    public var preserveLineBreaks: Bool
    /// The bullet every unordered list item gets: "-", "*" or "+".
    public var listMarker: String
    /// The frontmatter key the timestamp rule owns ("updated", "modified", …).
    public var timestampKey: String

    public init(enabled: Set<String> = Linter.defaultEnabled, preserveLineBreaks: Bool = true,
                listMarker: String = "-", timestampKey: String = "updated") {
        self.enabled = enabled
        self.preserveLineBreaks = preserveLineBreaks
        self.listMarker = ["-", "*", "+"].contains(listMarker) ? listMarker : "-"
        self.timestampKey = timestampKey.trimmingCharacters(in: .whitespaces).isEmpty ? "updated" : timestampKey.trimmingCharacters(in: .whitespaces)
    }

    public static let `default` = LinterConfig()
    public static func only(_ ids: String...) -> LinterConfig { LinterConfig(enabled: Set(ids)) }
    public func on(_ id: String) -> Bool { enabled.contains(id) }

    /// Read from UserDefaults (`onyx.lint.rule.<id>`, `onyx.lint.preserveBreaks`, `onyx.lint.listMarker`, `onyx.lint.timestampKey`).
    public static func load(_ d: UserDefaults = .standard) -> LinterConfig {
        var on = Set<String>()
        for r in Linter.rules where (d.object(forKey: LinterKeys.rule(r.id)) as? Bool ?? r.defaultOn) { on.insert(r.id) }
        return LinterConfig(enabled: on,
                            preserveLineBreaks: d.object(forKey: LinterKeys.preserveBreaks) as? Bool ?? true,
                            listMarker: d.string(forKey: LinterKeys.listMarker) ?? "-",
                            timestampKey: d.string(forKey: LinterKeys.timestampKey) ?? "updated")
    }
}

public enum LinterKeys {
    public static func rule(_ id: String) -> String { "onyx.lint.rule.\(id)" }
    public static let preserveBreaks = "onyx.lint.preserveBreaks"
    public static let listMarker = "onyx.lint.listMarker"
    public static let timestampKey = "onyx.lint.timestampKey"
    public static let onSave = "onyx.lint.onSave"
}

/// A Markdown linter in the spirit of Obsidian Linter. Every rule is conservative and idempotent
/// (lint(lint(x)) == lint(x)), and never edits fenced code, `$$` math, `%%` / `<!-- -->` comments,
/// callouts and blockquotes, inline-field lines (`key:: value`), or
/// frontmatter values. Rules only touch line prefixes (markers, `#`), line ends, and blank lines,
/// so inline code, `$math$` and `[[wikilinks]]` inside a line are never rewritten.
public enum Linter {
    public static let rules: [LintRule] = [
        LintRule(id: "trailing-whitespace", name: "Trim trailing whitespace",
                 description: "Remove spaces and tabs at the end of lines. Two-space hard line breaks can be kept.", defaultOn: true),
        LintRule(id: "blank-lines", name: "Collapse blank lines",
                 description: "Turn runs of two or more blank lines into one.", defaultOn: true),
        LintRule(id: "trailing-newline", name: "Single trailing newline",
                 description: "End the file with exactly one newline.", defaultOn: true),
        LintRule(id: "heading-blank-lines", name: "Blank lines around headings",
                 description: "Put an empty line before and after every heading.", defaultOn: true),
        LintRule(id: "heading-space", name: "Space after # in headings",
                 description: "##Heading becomes ## Heading. A single #word is a tag and is left alone.", defaultOn: true),
        LintRule(id: "list-marker", name: "Consistent list marker",
                 description: "Use one bullet (- by default) for every unordered list item.", defaultOn: true),
        LintRule(id: "code-blank-lines", name: "Blank lines around code blocks",
                 description: "Put an empty line before and after top-level fenced code blocks.", defaultOn: true),
        LintRule(id: "checkbox", name: "Normalize checkboxes",
                 description: "[] becomes [ ] and [X] becomes [x]. Custom statuses like [/] or [-] are kept.", defaultOn: true),
        LintRule(id: "heading-increment", name: "Heading increments",
                 description: "Never skip a heading level (# then ### becomes # then ##).", defaultOn: false),
        LintRule(id: "frontmatter-tidy", name: "Tidy frontmatter keys",
                 description: "Normalize top-level YAML key spacing to key: value. Values are not changed.", defaultOn: false),
        LintRule(id: "timestamp", name: "Updated timestamp",
                 description: "Set a frontmatter timestamp (updated: by default) when linting changes or saves a note.", defaultOn: false),
    ]
    public static let defaultEnabled: Set<String> = Set(rules.filter(\.defaultOn).map(\.id))
    public static func rule(_ id: String) -> LintRule? { rules.first { $0.id == id } }

    public static func timestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f.string(from: date)
    }

    /// Lint a whole note. `touched` says the note was edited (lint on save), which lets the
    /// timestamp rule stamp it even when no other rule changed anything.
    public static func lint(_ text: String, config: LinterConfig = .default, now: Date = Date(), touched: Bool = false) -> String {
        let crlf = text.contains("\r\n")
        let src = crlf ? text.replacingOccurrences(of: "\r\n", with: "\n") : text
        var (fm, body) = splitFrontmatter(src)
        if var f = fm, config.on("frontmatter-tidy") { f = tidyFrontmatter(f); fm = f }
        body = lintBody(body, config: config)
        var out = (fm ?? "") + body
        if config.on("timestamp"), touched || out != src {
            out = stamp(out, key: config.timestampKey, value: timestamp(now))
        }
        return crlf ? out.replacingOccurrences(of: "\n", with: "\r\n") : out
    }

    // MARK: Frontmatter

    /// The frontmatter block (both `---` lines and the newline after the closing one) and the body.
    static func splitFrontmatter(_ s: String) -> (String?, String) {
        guard s.hasPrefix("---\n") else { return (nil, s) }
        let ns = s as NSString
        var loc = 4
        while loc < ns.length {
            let lr = ns.lineRange(for: NSRange(location: loc, length: 0))
            let line = ns.substring(with: lr).trimmingCharacters(in: .newlines)
            if line.trimmingCharacters(in: .whitespaces) == "---" || line == "..." {
                let end = lr.location + lr.length
                var fm = ns.substring(to: end)
                if !fm.hasSuffix("\n") { fm += "\n" }
                return (fm, ns.substring(from: end))
            }
            loc = lr.location + max(lr.length, 1)
        }
        return (nil, s)
    }

    static let yamlKey = try! NSRegularExpression(pattern: #"^([A-Za-z0-9_][A-Za-z0-9_ .\-]*?)[ \t]*:(?!:)[ \t]*(.*)$"#)

    static func tidyFrontmatter(_ fm: String) -> String {
        var lines = fm.components(separatedBy: "\n")
        guard lines.count >= 3 else { return fm }
        for i in 1..<(lines.count - 2) {   // between the two delimiters
            let l = lines[i], ns = l as NSString
            guard let m = yamlKey.firstMatch(in: l, range: NSRange(location: 0, length: ns.length)) else { continue }
            let key = ns.substring(with: m.range(at: 1)), value = ns.substring(with: m.range(at: 2))
            if value.hasPrefix("//") { continue }   // a URL-ish scalar, not a key
            lines[i] = value.isEmpty ? "\(key):" : "\(key): \(value)"
        }
        return lines.joined(separator: "\n")
    }

    static func stamp(_ s: String, key: String, value: String) -> String {
        let (fm, body) = splitFrontmatter(s)
        let entry = "\(key): \(value)"
        guard let fm else { return "---\n\(entry)\n---\n" + body }
        var lines = fm.components(separatedBy: "\n")   // "---", ..., "---", ""
        let esc = NSRegularExpression.escapedPattern(for: key)
        let re = try! NSRegularExpression(pattern: "^\(esc)[ \\t]*:")
        if let i = lines.indices.dropFirst().dropLast(2).first(where: { re.firstMatch(in: lines[$0], range: NSRange(location: 0, length: (lines[$0] as NSString).length)) != nil }) {
            lines[i] = entry
            // drop an indented block value that belonged to the old entry
            while i + 1 < lines.count - 2, let f = lines[i + 1].first, f == " " || f == "\t" { lines.remove(at: i + 1) }
        } else {
            lines.insert(entry, at: lines.count - 2)
        }
        return lines.joined(separator: "\n") + body
    }

    // MARK: Body

    enum Kind { case prose, quote, field, code, fenceOpen, fenceClose, math, comment }
    struct Line { var text: String; var kind: Kind; var indent = 0 }

    static let fence = try! NSRegularExpression(pattern: #"^([ \t]*)(`{3,}|~{3,})(.*)$"#)
    static let heading = try! NSRegularExpression(pattern: #"^#{1,6}(?:[ \t]|$)"#)
    static let headingNoSpace = try! NSRegularExpression(pattern: #"^(#{2,6})([^#\s])"#)
    static let bullet = try! NSRegularExpression(pattern: #"^([ \t]*)[-*+]([ \t]+)"#)
    static let rule = try! NSRegularExpression(pattern: #"^[ \t]*([-*_])(?:[ \t]*\1){2,}[ \t]*$"#)
    static let emptyBox = try! NSRegularExpression(pattern: #"^([ \t]*(?:[-*+]|\d+[.)])[ \t]+)\[[ \t]*\](?=[ \t]|$)"#)
    static let upperBox = try! NSRegularExpression(pattern: #"^([ \t]*(?:[-*+]|\d+[.)])[ \t]+)\[X\](?=[ \t]|$)"#)

    static let ticks = try! NSRegularExpression(pattern: "`+")
    static let dollar = try! NSRegularExpression(pattern: #"(?<![\\$])\$(?!\$)"#)
    static let plusField = try! NSRegularExpression(pattern: #"^\s*\+\s+[\p{L}][\p{L}\p{N}_ -]*?::"#)

    static func m(_ re: NSRegularExpression, _ s: String) -> NSTextCheckingResult? {
        re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length))
    }
    static func sub(_ re: NSRegularExpression, _ s: String, _ tmpl: String) -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: tmpl)
    }
    static func count(_ needle: String, in s: String) -> Int { s.components(separatedBy: needle).count - 1 }

    /// Split into lines and mark the protected ones (code, math, comments, callouts, inline fields).
    static func classify(_ body: String) -> [Line] {
        var out: [Line] = []
        var fenceChar: Character? = nil, fenceLen = 0, fenceIndent = 0
        var inMath = false, commentEnd: String? = nil
        var inlineTicks: String? = nil, inlineMath = false
        for l in body.components(separatedBy: "\n") {
            // A span begun on a previous line takes precedence over apparent Markdown syntax.
            if inlineTicks != nil || inlineMath {
                if l.trimmingCharacters(in: .whitespaces).isEmpty { inlineTicks = nil; inlineMath = false }
                else {
                    let ns = l as NSString
                    if let mark = inlineTicks {
                        if ticks.matches(in: l, range: NSRange(location: 0, length: ns.length)).contains(where: { ns.substring(with: $0.range) == mark }) { inlineTicks = nil }
                    } else if dollar.numberOfMatches(in: l, range: NSRange(location: 0, length: ns.length)) % 2 == 1 { inlineMath = false }
                    out.append(Line(text: l, kind: .code)); continue
                }
            }
            if let c = fenceChar {
                if let r = m(fence, l) {
                    let ns = l as NSString, marks = ns.substring(with: r.range(at: 2)), rest = ns.substring(with: r.range(at: 3))
                    if marks.first == c, marks.count >= fenceLen, rest.trimmingCharacters(in: .whitespaces).isEmpty {
                        out.append(Line(text: l, kind: .fenceClose, indent: fenceIndent)); fenceChar = nil; continue
                    }
                }
                out.append(Line(text: l, kind: .code)); continue
            }
            if inMath {
                out.append(Line(text: l, kind: .math)); if l.contains("$$") { inMath = false }; continue
            }
            if let end = commentEnd {
                out.append(Line(text: l, kind: .comment)); if l.contains(end) { commentEnd = nil }; continue
            }
            if let r = m(fence, l) {
                let ns = l as NSString, marks = ns.substring(with: r.range(at: 2)), rest = ns.substring(with: r.range(at: 3))
                if !(marks.first == "`" && rest.contains("`")) {
                    fenceChar = marks.first; fenceLen = marks.count; fenceIndent = r.range(at: 1).length
                    out.append(Line(text: l, kind: .fenceOpen, indent: fenceIndent)); continue
                }
            }
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("$$") {
                if count("$$", in: t) < 2 { inMath = true }
                out.append(Line(text: l, kind: .math)); continue
            }
            if l.contains("%%") {
                if count("%%", in: l) % 2 == 1 { commentEnd = "%%" }
                out.append(Line(text: l, kind: .comment)); continue
            }
            if let r = l.range(of: "<!--") {
                if !l[r.upperBound...].contains("-->") { commentEnd = "-->" }
                out.append(Line(text: l, kind: .comment)); continue
            }
            if t.hasPrefix(">") { out.append(Line(text: l, kind: .quote)); continue }
            if t.isEmpty { inlineTicks = nil; inlineMath = false }   // spans never cross a paragraph break
            // Inline code or $math$ left open at a line end continues on the next line: protect those
            // lines whole. Closed spans inside a line are safe, since rules only edit line prefixes.
            let wasOpen = inlineTicks != nil || inlineMath
            let ns = l as NSString
            for run in ticks.matches(in: l, range: NSRange(location: 0, length: ns.length)) {
                let mark = ns.substring(with: run.range)
                if inlineTicks == mark { inlineTicks = nil } else if inlineTicks == nil { inlineTicks = mark }
            }
            if inlineTicks == nil, dollar.numberOfMatches(in: l, range: NSRange(location: 0, length: ns.length)) % 2 == 1 { inlineMath.toggle() }
            if wasOpen || inlineTicks != nil || inlineMath { out.append(Line(text: l, kind: .code)); continue }
            if m(InlineFields.line, l) != nil || m(plusField, l) != nil { out.append(Line(text: l, kind: .field)); continue }
            out.append(Line(text: l, kind: .prose))
        }
        return out
    }

    static func isBlank(_ l: Line) -> Bool { l.kind == .prose && l.text.allSatisfy { $0 == " " || $0 == "\t" } }
    static func isHeading(_ l: Line) -> Bool { l.kind == .prose && m(heading, l.text) != nil }

    static func trimTrailing(_ s: String, keepBreak: Bool) -> String {
        var end = s.endIndex
        while end > s.startIndex, let c = Optional(s[s.index(before: end)]), c == " " || c == "\t" { end = s.index(before: end) }
        let head = String(s[..<end])
        if keepBreak, !head.isEmpty, s[end...].hasPrefix("  ") { return head + "  " }
        return head
    }

    static func lintBody(_ body: String, config c: LinterConfig) -> String {
        if body.isEmpty { return body }
        let hadNewline = body.hasSuffix("\n")
        var lines = classify(hadNewline ? String(body.dropLast()) : body)

        // Line rules.
        var lastLevel = 0
        for i in lines.indices {
            var l = lines[i]
            if c.on("trailing-whitespace"), l.kind == .prose {
                l.text = trimTrailing(l.text, keepBreak: c.preserveLineBreaks)
            }
            if l.kind == .prose {
                if c.on("heading-space") { l.text = sub(headingNoSpace, l.text, "$1 $2") }
                if c.on("list-marker"), m(rule, l.text) == nil, let r = m(bullet, l.text) {
                    let ns = l.text as NSString
                    l.text = ns.substring(with: r.range(at: 1)) + c.listMarker + ns.substring(from: r.range(at: 1).length + 1)
                }
                if c.on("checkbox") {
                    l.text = sub(emptyBox, l.text, "$1[ ]")
                    l.text = sub(upperBox, l.text, "$1[x]")
                }
                if isHeading(l) {
                    let level = l.text.prefix { $0 == "#" }.count
                    if c.on("heading-increment"), lastLevel > 0, level > lastLevel + 1 {
                        l.text = String(repeating: "#", count: lastLevel + 1) + l.text.dropFirst(level)
                        lastLevel += 1
                    } else { lastLevel = level }
                }
            }
            lines[i] = l
        }

        // Structural rules: blank lines around headings and top-level fences, collapse runs.
        var out: [Line] = []
        var wantBlank = false
        for l in lines {
            let blank = isBlank(l)
            if wantBlank && !blank && !out.isEmpty && !isBlank(out[out.count - 1]) { out.append(Line(text: "", kind: .prose)) }
            wantBlank = false
            let head = c.on("heading-blank-lines") && isHeading(l)
            let open = c.on("code-blank-lines") && l.kind == .fenceOpen && l.indent == 0
            if (head || open), let last = out.last, !isBlank(last) { out.append(Line(text: "", kind: .prose)) }
            if blank, c.on("blank-lines"), let last = out.last, isBlank(last) { continue }
            out.append(l)
            if head || (c.on("code-blank-lines") && l.kind == .fenceClose && l.indent == 0) { wantBlank = true }
        }

        if c.on("trailing-newline") {
            while let last = out.last, isBlank(last) { out.removeLast() }
            if out.isEmpty { return "" }
            // Do not insert a final newline inside an unclosed protected block/span or a field.
            let last = out.last!.kind
            let protectedEnd = [.code, .math, .comment, .field, .quote, .fenceOpen].contains(last)
            return out.map(\.text).joined(separator: "\n") + ((hadNewline || !protectedEnd) ? "\n" : "")
        }
        return out.map(\.text).joined(separator: "\n") + (hadNewline ? "\n" : "")
    }

    // MARK: Cursor

    /// Where a caret (UTF-16 offset in `old`) lands in `new`: same line (matched through a line
    /// diff) and the same column, clamped to the line's length.
    public static func mapCursor(_ offset: Int, from old: String, to new: String) -> Int {
        let o = old.components(separatedBy: "\n"), n = new.components(separatedBy: "\n")
        var line = 0, col = 0, pos = 0
        for (i, s) in o.enumerated() {
            let len = (s as NSString).length
            if offset <= pos + len { line = i; col = offset - pos; break }
            pos += len + 1
            line = i; col = len
        }
        let diff = n.difference(from: o)
        var removed = Set<Int>(), inserted = Set<Int>()
        for ch in diff { switch ch { case .remove(let k, _, _): removed.insert(k); case .insert(let k, _, _): inserted.insert(k) } }
        let keptOld = o.indices.filter { !removed.contains($0) }, keptNew = n.indices.filter { !inserted.contains($0) }
        var target = 0
        if let k = keptOld.firstIndex(of: line) { target = keptNew[k] }
        else if let k = keptOld.lastIndex(where: { $0 < line }) { target = min(keptNew[k] + 1 + (line - keptOld[k] - 1), n.count - 1) }
        else { target = min(line, n.count - 1) }
        target = max(0, target)
        var out = 0
        for i in 0..<target { out += (n[i] as NSString).length + 1 }
        return out + min(col, (n[target] as NSString).length)
    }
}
