import Foundation

/// Dataview fields with exact UTF-16 source ranges. Relation fields accept bare note names;
/// other keys only turn explicit wikilinks into graph links (numbers/prose stay values).
public struct InlineField: Sendable {
    public var key: String
    public var value: String
    public var range: NSRange
    public var valueRange: NSRange
    public var keyRange: NSRange
    public var links: [WikiLink]
    public var isFrontmatter: Bool
    public var kind: String { Self.kind(key) }
    public static func kind(_ key: String) -> String {
        key.lowercased().filter { $0.isLetter || $0.isNumber }
    }
    public static func isRelation(_ key: String) -> Bool {
        ["partof", "related", "relatesto", "correspondsto"].contains(kind(key))
    }
    public var label: String { kind == "partof" ? "Part of" : (["related", "relatesto"].contains(kind) ? "Related" : key) }
}

public enum InlineFields {
    static let line = try! NSRegularExpression(pattern: #"^\s*(?:[-*]\s+)?([\p{L}][\p{L}\p{N}_ -]*?)::[ \t]*(.+?)\s*$"#)
    static let wrapped = try! NSRegularExpression(pattern: #"[\[(]([\p{L}][\p{L}\p{N}_ -]*?)::[ \t]*((?:\[\[[^\n]*?\]\]|[^\]\)\n])+)[\])]"#)
    static let yaml = try! NSRegularExpression(pattern: #"^([\p{L}][\p{L}\p{N}_ -]*?):[ \t]*(.*)$"#)
    static let list = try! NSRegularExpression(pattern: #"^\s+-[ \t]+(.+?)\s*$"#)
    static let code = try! NSRegularExpression(pattern: #"`+[^`\n]*`+|%%[\s\S]*?%%|<!--[\s\S]*?-->"#)

    /// `lines` limits which lines are read (the editor restyling one paragraph); fences,
    /// comments and frontmatter are still found in the whole text.
    public static func parse(_ text: String, lines: NSRange? = nil) -> [InlineField] {
        let ns = text as NSString, fm = Frontmatter.parse(text)
        let stop = lines.map(NSMaxRange) ?? ns.length
        let u = Array(text.utf16)
        let all = NoteParser.lineRanges(u)
        // Found only once a body line could hold a field.
        lazy var excluded = NoteParser.codeRanges(text, utf16: u, lines: all) + code.matches(in: text, range: NSRange(location: 0, length: ns.length)).map(\.range)
        /// Body fields always contain "::"; lines without it are skipped uncopied.
        func hasFieldMarker(_ lr: NSRange) -> Bool {
            var i = lr.location
            let end = NSMaxRange(lr) - 1
            while i < end { if u[i] == 58 && u[i + 1] == 58 { return true }; i += 1 }
            return false
        }
        var fields: [InlineField] = [], offset = 0
        var yamlKey: (String, NSRange)?
        // Frontmatter list items need the key above them, so a range inside it starts from the top.
        if let lines, lines.location >= fm.bodyOffset { offset = lines.location }
        func add(_ key: String, _ kr: NSRange, _ vr: NSRange, _ range: NSRange, _ front: Bool) {
            let ls = values(ns.substring(with: vr), offset: vr.location, key: key)
            // Only relation properties (or explicit link-valued properties) are special in YAML.
            if front && ls.isEmpty { return }
            fields.append(InlineField(key: key, value: ns.substring(with: vr), range: range, valueRange: vr, keyRange: kr, links: ls, isFrontmatter: front))
        }
        for lr in all where NSMaxRange(lr) > offset {
            if lr.location >= stop { break }
            if lr.location >= fm.bodyOffset && !hasFieldMarker(lr) { continue }
            let s = ns.substring(with: lr).trimmingCharacters(in: .newlines), len = (s as NSString).length
            let local = s as NSString
            func global(_ r: NSRange) -> NSRange { NSRange(location: lr.location + r.location, length: r.length) }
            if lr.location > 0 && lr.location < fm.bodyOffset {
                if let m = yaml.firstMatch(in: s, range: NSRange(location: 0, length: len)) {
                    let key = local.substring(with: m.range(at: 1)), kr = global(m.range(at: 1))
                    yamlKey = (key, kr)
                    if m.range(at: 2).length > 0 { add(key, kr, global(m.range(at: 2)), global(m.range), true) }
                } else if let (key, kr) = yamlKey, let m = list.firstMatch(in: s, range: NSRange(location: 0, length: len)) {
                    add(key, kr, global(m.range(at: 1)), global(m.range), true)
                }
            } else if lr.location >= fm.bodyOffset {
                let matches: [NSTextCheckingResult]
                if let m = line.firstMatch(in: s, range: NSRange(location: 0, length: len)) { matches = [m] }
                else { matches = wrapped.matches(in: s, range: NSRange(location: 0, length: len)) }
                for m in matches {
                    let r = global(m.range)
                    guard !excluded.contains(where: { NSIntersectionRange($0, r).length > 0 }) else { continue }
                    add(local.substring(with: m.range(at: 1)), global(m.range(at: 1)), global(m.range(at: 2)), r, false)
                }
            }
        }
        return fields
    }

    /// UTF-16 safe: surrogate halves (emoji) are never whitespace.
    static func space(_ c: unichar) -> Bool { c == 32 || c == 9 || c == 10 || c == 13 || c == 0xA0 || c == 0x3000 }

    /// Split commas outside wiki/quoted values. Trim syntax, preserving exact ranges for rename.
    public static func values(_ value: String, offset: Int = 0, key: String) -> [WikiLink] {
        let ns = value as NSString
        var start = 0, end = ns.length
        func trim() {
            while start < end && space(ns.character(at: start)) { start += 1 }
            while end > start && space(ns.character(at: end - 1)) { end -= 1 }
        }
        trim()
        if end - start >= 2, ns.character(at: start) == 91, ns.character(at: start + 1) != 91, ns.character(at: end - 1) == 93 { start += 1; end -= 1 }
        var segments: [NSRange] = [], seg = start, i = start, wiki = false, quote: unichar = 0
        while i < end {
            let c = ns.character(at: i), next = i + 1 < end ? ns.character(at: i + 1) : 0
            if c == 91 && next == 91 { wiki = true; i += 2; continue }
            if c == 93 && next == 93 { wiki = false; i += 2; continue }
            if !wiki {
                if (c == 34 || c == 39) && (i == seg || quote != 0) { quote = quote == c ? 0 : (quote == 0 ? c : quote) }
                if c == 44 && quote == 0 { segments.append(NSRange(location: seg, length: i - seg)); seg = i + 1 }
            }
            i += 1
        }
        segments.append(NSRange(location: seg, length: end - seg))
        var links: [WikiLink] = []
        for r in segments {
            var a = r.location, b = NSMaxRange(r)
            while a < b && space(ns.character(at: a)) { a += 1 }
            while b > a && space(ns.character(at: b - 1)) { b -= 1 }
            if b - a >= 2, [34, 39].contains(ns.character(at: a)), ns.character(at: a) == ns.character(at: b - 1) { a += 1; b -= 1 }
            guard b > a else { continue }
            let s = ns.substring(with: NSRange(location: a, length: b - a))
            let explicit = NoteParser.parseWikiLinks(s)
            if !explicit.isEmpty {
                for var l in explicit { l.range.location += offset + a; l.fieldKey = key; links.append(l) }
            } else if InlineField.isRelation(key) {
                var l = NoteParser.makeLink(inner: s, embed: false, range: NSRange(location: offset + a, length: b - a))
                guard !l.target.isEmpty, !["null", "~", "[]"].contains(l.target) else { continue }
                l.fieldKey = key; l.isBare = true; links.append(l)
            }
        }
        return links
    }
}
