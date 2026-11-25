import Foundation

public struct WikiLink: Hashable, Sendable {
    public var target: String      // note name or path, without #heading
    public var heading: String?    // #heading or #^block
    public var alias: String?
    public var isEmbed: Bool
    public var range: NSRange      // range of the whole [[...]] in the source

    public var fieldKey: String? = nil
    public var isBare: Bool = false

    /// Raw inner text, e.g. "Note#Heading|Alias"
    public var raw: String {
        var s = target
        if let h = heading { s += "#" + h }
        if let a = alias { s += "|" + a }
        return s
    }
}

public struct Heading: Hashable, Sendable {
    public var level: Int
    public var text: String
    public var line: Int
    public var offset: Int
}

public struct NoteSummary: Sendable {
    public var frontmatter: Frontmatter
    public var links: [WikiLink]
    public var fields: [InlineField]
    public var markdownLinks: [String]
    public var tags: [String]
    public var headings: [Heading]
    public var wordCount: Int
}

public enum NoteParser {
    static let wikiRegex = try! NSRegularExpression(pattern: #"(!?)\[\[([^\[\]\n]+?)\]\]"#)
    static let mdLinkRegex = try! NSRegularExpression(pattern: #"\]\(([^)\s]+\.md)\)"#)
    static let fenceRegex = try! NSRegularExpression(pattern: #"^ {0,3}(`{3,}|~{3,})"#)

    public static func parseWikiLinks(_ text: String, in range: NSRange? = nil) -> [WikiLink] {
        let ns = text as NSString
        let r = range ?? NSRange(location: 0, length: ns.length)
        return wikiRegex.matches(in: text, range: r).map { m in
            let inner = ns.substring(with: m.range(at: 2))
            return makeLink(inner: inner, embed: m.range(at: 1).length > 0, range: m.range)
        }
    }

    public static func makeLink(inner: String, embed: Bool, range: NSRange) -> WikiLink {
        var s = inner
        var alias: String? = nil
        if let bar = s.firstIndex(of: "|") {
            alias = String(s[s.index(after: bar)...])
            s = String(s[..<bar])
        }
        var heading: String? = nil
        if let hash = s.firstIndex(of: "#") {
            heading = String(s[s.index(after: hash)...])
            s = String(s[..<hash])
        }
        if s.hasSuffix("\\") { s.removeLast() } // [[a\|b]] inside tables
        return WikiLink(target: s.trimmingCharacters(in: .whitespaces), heading: heading, alias: alias, isEmbed: embed, range: range)
    }

    /// The UTF-16 ranges of every line, terminators included — exactly what repeated
    /// `NSString.lineRange(for:)` walks give, from one pass over a UTF-16 copy.
    public static func lineRanges(_ u: [UInt16]) -> [NSRange] {
        var out: [NSRange] = []
        var start = 0, i = 0
        let n = u.count
        while i < n {
            let c = u[i]
            if c == 10 || c == 13 || c == 0x85 || c == 0x2028 || c == 0x2029 {
                var end = i + 1
                if c == 13, end < n, u[end] == 10 { end += 1 }
                out.append(NSRange(location: start, length: end - start))
                start = end; i = end
            } else { i += 1 }
        }
        if start < n { out.append(NSRange(location: start, length: n - start)) }
        return out
    }

    /// Ranges (UTF-16) of fenced code blocks and frontmatter, which never contain links or tags.
    public static func codeRanges(_ text: String) -> [NSRange] {
        // No backtick or tilde anywhere: no fences.
        guard text.utf8.contains(where: { $0 == 0x60 || $0 == 0x7E }) else { return [] }
        return codeRanges(text, utf16: Array(text.utf16))
    }
    static func codeRanges(_ text: String, utf16 u: [UInt16], lines: [NSRange]? = nil) -> [NSRange] {
        let ns = text as NSString
        var out: [NSRange] = []
        var fenceStart = -1
        var fenceMarker = ""
        for lineRange in lines ?? lineRanges(u) {
            // Only a line starting with ` or ~ after at most three spaces can be a fence.
            var k = lineRange.location
            let end = NSMaxRange(lineRange)
            while k < end, k - lineRange.location < 3, u[k] == 32 { k += 1 }
            guard k < end, u[k] == 96 || u[k] == 126 else { continue }
            let line = ns.substring(with: lineRange)
            if let m = fenceRegex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                let marker = (line as NSString).substring(with: m.range(at: 1))
                if fenceStart < 0 {
                    fenceStart = lineRange.location; fenceMarker = marker
                } else if marker.first == fenceMarker.first && marker.count >= fenceMarker.count {
                    out.append(NSRange(location: fenceStart, length: NSMaxRange(lineRange) - fenceStart))
                    fenceStart = -1
                }
            }
        }
        if fenceStart >= 0 { out.append(NSRange(location: fenceStart, length: ns.length - fenceStart)) }
        return out
    }

    public static func summarize(_ text: String) -> NoteSummary {
        let fm = Frontmatter.parse(text)
        let ns = text as NSString
        let body = NSRange(location: fm.bodyOffset, length: ns.length - fm.bodyOffset)
        let code = codeRanges(text)
        func inCode(_ r: NSRange) -> Bool { code.contains { NSIntersectionRange($0, r).length > 0 } }

        let fields = InlineFields.parse(text)
        let fieldLinks = fields.flatMap(\.links)
        // Keep a field wikilink once, carrying its relationship kind.
        let links = parseWikiLinks(text, in: body).filter { l in
            !inCode(l.range) && !fieldLinks.contains { NSIntersectionRange($0.range, l.range).length > 0 }
        } + fieldLinks
        let mdLinks = mdLinkRegex.matches(in: text, range: body).filter { !inCode($0.range) }.map {
            ns.substring(with: $0.range(at: 1)).removingPercentEncoding ?? ns.substring(with: $0.range(at: 1))
        }
        // inline and frontmatter, hierarchical, case-insensitive; never in code, links or URLs
        let tags = TagScanner.names(text, code: code, frontmatter: fm)
        let headings = parseHeadings(text, skipping: code, from: fm.bodyOffset)
        let words = countWords(ns.substring(with: body))
        return NoteSummary(frontmatter: fm, links: links, fields: fields, markdownLinks: mdLinks, tags: tags.sorted(), headings: headings, wordCount: words)
    }

    public static func parseHeadings(_ text: String, skipping code: [NSRange]? = nil, from start: Int = 0) -> [Heading] {
        let ns = text as NSString
        let u = Array(text.utf16)
        let code = code ?? codeRanges(text)
        var out: [Heading] = []
        var lineNo = -1
        for lr in lineRanges(u) {
            lineNo += 1
            // Headings start with "#": other lines are skipped without being copied out.
            guard u[lr.location] == 35 else { continue }
            if lr.location >= start && !code.contains(where: { NSLocationInRange(lr.location, $0) }) {
                let line = ns.substring(with: lr).trimmingCharacters(in: .newlines)
                if line.hasPrefix("#") {
                    var level = 0
                    for ch in line { if ch == "#" { level += 1 } else { break } }
                    let rest = line.dropFirst(level)
                    if level <= 6, rest.hasPrefix(" ") {
                        let t = rest.trimmingCharacters(in: .whitespaces)
                        out.append(Heading(level: level, text: stripInline(t), line: lineNo, offset: lr.location))
                    }
                }
            }
        }
        return out
    }

    /// Strip the most common inline markdown for display (outline, titles).
    public static func stripInline(_ s: String) -> String {
        var t = s
        t = wikiRegex.stringByReplacingMatches(in: t, range: NSRange(location: 0, length: (t as NSString).length), withTemplate: "$2")
        t = t.replacingOccurrences(of: #"\|[^\]]*"#, with: "", options: .regularExpression)
        for m in ["**", "__", "==", "`", "*", "_"] { t = t.replacingOccurrences(of: m, with: "") }
        return t
    }

    public static func countWords(_ s: String) -> Int {
        var n = 0
        s.enumerateSubstrings(in: s.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in n += 1 }
        return n
    }
}
