import Foundation

/// Obsidian's embed sizing: `![[img.png|300]]`, `![[img.png|300x200]]`, `![[img.png|alt|300]]`,
/// and in Markdown `![300](img.png)` / `![alt|300x200](img.png)`. The size is the last `|` segment
/// when it is `W` or `WxH`. The reader resizes by rewriting that segment on one exact occurrence.
public struct EmbedSize: Equatable, Sendable {
    public var width: Int
    public var height: Int?
    public init(width: Int, height: Int? = nil) { self.width = width; self.height = height }
}

public enum ImageSize {
    /// "300" → 300 wide, "300x200" → 300×200. Anything else is not a size.
    public static func parse(_ s: String) -> EmbedSize? {
        let t = s.trimmingCharacters(in: .whitespaces)
        let parts = t.split(separator: "x", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let w = Int(parts[0]), w > 0 else { return nil }
        if parts.count == 2 { guard let h = Int(parts[1]), h > 0 else { return nil }; return EmbedSize(width: w, height: h) }
        return EmbedSize(width: w)
    }

    /// Splits `alt|300` (Markdown alt text or a wikilink's text after the target) into the
    /// alt text and the size. `300` alone is a size with no alt.
    public static func split(_ label: String) -> (alt: String?, size: EmbedSize?) {
        if let bar = label.range(of: "|", options: .backwards) {
            var head = String(label[..<bar.lowerBound])
            if head.hasSuffix("\\") { head.removeLast() }   // `\|` inside a table cell
            if let s = parse(String(label[bar.upperBound...])) { return (head, s) }
            return (label, nil)
        }
        if let s = parse(label) { return (nil, s) }
        return (label.isEmpty ? nil : label, nil)
    }

    static let wiki = try! NSRegularExpression(pattern: #"!\[\[([^\[\]\n]+?)\]\]"#)
    static let markdown = try! NSRegularExpression(pattern: #"!\[([^\]\n]*)\]\(\s*(<[^>\n]+>|[^)\s]+)((?:\s+"[^"\n]*")?\s*)\)"#)
    static let masks = [try! NSRegularExpression(pattern: #"(`+)[^`\n][\s\S]*?\1"#), try! NSRegularExpression(pattern: #"%%[\s\S]*?%%"#)]

    /// The edit that sets (or with `width == nil` removes) the size on one embed. The embed is the
    /// `occurrence`-th one (0-based) of `kind` ("wiki" or "md") with `target` inside source lines
    /// `line ..< line + lines`, skipping code spans and `%%comments%%` the reader doesn't render.
    /// Wiki targets match case-insensitively without `#heading`; Markdown targets match the href.
    public static func edit(in text: String, line: Int, lines: Int, kind: String, target: String, occurrence: Int, width: Int?) -> (range: NSRange, replacement: String)? {
        let ns = text as NSString
        // UTF-16 offsets of the block's lines.
        var start = 0, l = 0
        while l < line {
            let r = ns.range(of: "\n", range: NSRange(location: start, length: ns.length - start))
            guard r.location != NSNotFound else { return nil }
            start = r.location + 1; l += 1
        }
        var end = start
        for _ in 0..<max(1, lines) {
            let r = ns.range(of: "\n", range: NSRange(location: end, length: ns.length - end))
            if r.location == NSNotFound { end = ns.length; break }
            end = r.location + 1
        }
        let span = NSRange(location: start, length: end - start)
        let masked = NSMutableString(string: ns.substring(with: span))
        for m in masks {
            for r in m.matches(in: masked as String, range: NSRange(location: 0, length: masked.length)) {
                masked.replaceCharacters(in: r.range, with: String(repeating: " ", count: r.range.length))
            }
        }
        let hay = masked as String, full = NSRange(location: 0, length: masked.length)
        var n = 0
        if kind == "wiki" {
            let want = target.trimmingCharacters(in: .whitespaces).lowercased()
            for m in wiki.matches(in: hay, range: full) {
                let innerR = m.range(at: 1), inner = ns.substring(with: NSRange(location: start + innerR.location, length: innerR.length))
                var t = inner.components(separatedBy: "|")[0]
                if t.hasSuffix("\\") { t.removeLast() }
                if let h = t.firstIndex(of: "#") { t = String(t[..<h]) }
                guard t.trimmingCharacters(in: .whitespaces).lowercased() == want else { continue }
                if n < occurrence { n += 1; continue }
                return (NSRange(location: start + innerR.location, length: innerR.length), resizedWiki(inner, width: width, table: inTable(ns, start + innerR.location)))
            }
        } else {
            for m in markdown.matches(in: hay, range: full) {
                var href = ns.substring(with: NSRange(location: start + m.range(at: 2).location, length: m.range(at: 2).length))
                if href.hasPrefix("<") { href = String(href.dropFirst().dropLast()) }
                guard href == target || href.removingPercentEncoding == target || href == target.removingPercentEncoding else { continue }
                if n < occurrence { n += 1; continue }
                let altR = NSRange(location: start + m.range(at: 1).location, length: m.range(at: 1).length)
                return (altR, resizedAlt(ns.substring(with: altR), width: width, table: inTable(ns, altR.location)))
            }
        }
        return nil
    }

    /// `edit` applied: the new note text, or nil when the embed isn't there.
    public static func resize(_ text: String, line: Int, lines: Int, kind: String, target: String, occurrence: Int, width: Int?) -> String? {
        guard let e = edit(in: text, line: line, lines: lines, kind: kind, target: target, occurrence: occurrence, width: width) else { return nil }
        return (text as NSString).replacingCharacters(in: e.range, with: e.replacement)
    }

    /// `img.png|alt|300` with a new width (nil drops the size).
    static func resizedWiki(_ inner: String, width: Int?, table: Bool = false) -> String {
        let sep = inner.contains("\\|") || table ? "\\|" : "|"
        var segs = inner.components(separatedBy: sep)
        if segs.count > 1, parse(segs[segs.count - 1]) != nil { segs.removeLast() }
        if let width { segs.append(String(width)) }
        return segs.joined(separator: sep)
    }

    /// Markdown alt text `alt|300` (or `300`) with a new width (nil drops the size).
    static func resizedAlt(_ alt: String, width: Int?, table: Bool = false) -> String {
        let base = split(alt).size == nil ? alt : (split(alt).alt ?? "")
        guard let width else { return base }
        return base.isEmpty ? String(width) : base + (table || alt.contains("\\|") ? "\\|" : "|") + String(width)
    }

    /// A `|` inside a table row must be escaped, or it splits the cell.
    static func inTable(_ ns: NSString, _ loc: Int) -> Bool {
        let lr = ns.lineRange(for: NSRange(location: loc, length: 0))
        return ns.substring(with: lr).trimmingCharacters(in: .whitespaces).hasPrefix("|")
    }
}
