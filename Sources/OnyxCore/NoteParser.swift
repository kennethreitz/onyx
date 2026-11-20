import Foundation

public struct WikiLink: Hashable, Sendable {
    public var target: String      // note name or path, without #heading
    public var heading: String?    // #heading or #^block
    public var alias: String?
    public var isEmbed: Bool
    public var range: NSRange      // range of the whole [[...]] in the source

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
    public var markdownLinks: [String]
    public var tags: [String]
    public var headings: [Heading]
    public var wordCount: Int
}

public enum NoteParser {
    static let wikiRegex = try! NSRegularExpression(pattern: #"(!?)\[\[([^\[\]\n]+?)\]\]"#)
    static let tagRegex = try! NSRegularExpression(pattern: #"(?<![\w/&#])#([A-Za-z0-9_\-/]*[A-Za-z_\-/][A-Za-z0-9_\-/]*)"#)
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

    /// Ranges (UTF-16) of fenced code blocks and frontmatter, which never contain links or tags.
    public static func codeRanges(_ text: String) -> [NSRange] {
        let ns = text as NSString
        var out: [NSRange] = []
        var loc = 0
        var fenceStart = -1
        var fenceMarker = ""
        while loc < ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
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
            loc = NSMaxRange(lineRange)
            if lineRange.length == 0 { break }
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

        let links = parseWikiLinks(text, in: body).filter { !inCode($0.range) }
        let mdLinks = mdLinkRegex.matches(in: text, range: body).filter { !inCode($0.range) }.map {
            ns.substring(with: $0.range(at: 1)).removingPercentEncoding ?? ns.substring(with: $0.range(at: 1))
        }
        var tags = Set<String>()
        for m in tagRegex.matches(in: text, range: body) where !inCode(m.range) {
            // skip headings: "# " never matches because tag needs a non-space char after '#'
            tags.insert(ns.substring(with: m.range(at: 1)))
        }
        if let t = fm["tags"] ?? fm["tag"] {
            for s in t.strings { for part in s.split(whereSeparator: { $0 == " " || $0 == "," }) {
                let clean = part.hasPrefix("#") ? String(part.dropFirst()) : String(part)
                if !clean.isEmpty { tags.insert(clean) }
            } }
        }
        let headings = parseHeadings(text, skipping: code, from: fm.bodyOffset)
        let words = countWords(ns.substring(with: body))
        return NoteSummary(frontmatter: fm, links: links, markdownLinks: mdLinks, tags: tags.sorted(), headings: headings, wordCount: words)
    }

    public static func parseHeadings(_ text: String, skipping code: [NSRange]? = nil, from start: Int = 0) -> [Heading] {
        let ns = text as NSString
        let code = code ?? codeRanges(text)
        var out: [Heading] = []
        var loc = 0
        var lineNo = 0
        while loc < ns.length {
            let lr = ns.lineRange(for: NSRange(location: loc, length: 0))
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
            lineNo += 1
            loc = NSMaxRange(lr)
            if lr.length == 0 { break }
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
