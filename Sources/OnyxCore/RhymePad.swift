import Foundation

/// Port of obsidian-rhymepad's pure half: the /api/analyze response, the
/// masking of non-verse text, and response → flat styled segments.
public enum RhymePad {
    public static let colorCount = 16
    public struct Token: Decodable, Sendable { public var l: Int; public var s: Int; public var e: Int; public var g: Int; public var end: Bool?; public var ph: Bool?; public var slant: Bool?; public var str: Double?; public var rs: Int? }
    public struct Group: Decodable, Sendable { public var id: Int; public var color: Int; public var slant: Bool?; public var sound: String?; public var strength: Double? }
    public struct Span: Decodable, Sendable { public var l: Int; public var s: Int; public var e: Int; public var g: Int? }
    public struct Analysis: Decodable, Sendable { public var lines: [String]; public var tokens: [Token]; public var groups: [Group]; public var open: [Span]?; public var near: [Span]? }

    public struct Segment: Sendable, Equatable {
        public var line: Int; public var start: Int; public var end: Int
        public var color: Int?; public var alpha: Double; public var tail: Bool; public var tailAlpha: Double
        public var near: Bool; public var open: Bool; public var title: String
    }

    /// Blank out frontmatter, fenced code, $$ / %% blocks and inline code, keeping offsets.
    public static func mask(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        var i = 0
        if let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" {
            var j = 1
            while j < lines.count && !["---", "..."].contains(lines[j].trimmingCharacters(in: .whitespaces)) { j += 1 }
            if j < lines.count { for k in 0...j { lines[k] = "" }; i = j + 1 }
        }
        var fence: String? = nil
        var block: String? = nil
        let fenceRe = try! NSRegularExpression(pattern: #"^ {0,3}(`{3,}|~{3,})"#)
        let codeRe = try! NSRegularExpression(pattern: #"(`+)([^`]|[^`][\s\S]*?[^`])\1(?!`)"#)
        while i < lines.count {
            let line = lines[i]
            let ns = line as NSString
            let fm = fenceRe.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))
            if let f = fence {
                lines[i] = ""
                if let fm { let m = ns.substring(with: fm.range(at: 1)); if m.first == f.first && m.count >= f.count { fence = nil } }
                i += 1; continue
            }
            if let b = block { lines[i] = ""; if line.contains(b) { block = nil }; i += 1; continue }
            if let fm { fence = ns.substring(with: fm.range(at: 1)); lines[i] = ""; i += 1; continue }
            let t = line.trimmingCharacters(in: .whitespaces)
            for b in ["$$", "%%"] where t.hasPrefix(b) && (t == b || !t.dropFirst(2).contains(b)) { block = b; break }
            if block != nil { lines[i] = ""; i += 1; continue }
            let m = NSMutableString(string: line)
            for r in codeRe.matches(in: line, range: NSRange(location: 0, length: ns.length)).reversed() {
                m.replaceCharacters(in: r.range, with: String(repeating: " ", count: r.range.length))
            }
            lines[i] = m as String
            i += 1
        }
        return lines.joined(separator: "\n")
    }

    public static func segments(_ a: Analysis, docLines: [String], unanswered: Bool = true, nearMiss: Bool = true) -> [Segment] {
        var groups: [Int: Group] = [:]
        for g in a.groups { groups[g.id] = g }
        var out: [Segment] = []
        for (i, line) in docLines.enumerated() {
            guard i < a.lines.count, a.lines[i] == line else { continue }
            let len = (line as NSString).length
            let toks = a.tokens.filter { $0.l == i && $0.e <= len && $0.s < $0.e && groups[$0.g] != nil }
            for t in toks where t.ph != true {
                let g = groups[t.g]!
                let str = t.str ?? g.strength ?? 1
                let base: Double = t.end == true ? 34 : 19
                let color = ((g.color % colorCount) + colorCount) % colorCount
                let title = "\(g.sound.map { "/\($0)/" } ?? "rhyme") · \(t.end == true ? "end rhyme" : "internal") · strength \(String(format: "%.2f", str))"
                let alpha = base * (0.4 + 0.6 * str) / 100
                if let rs = t.rs, rs > t.s, rs < t.e {
                    out.append(Segment(line: i, start: t.s, end: rs, color: color, alpha: alpha, tail: false, tailAlpha: 0, near: false, open: false, title: title))
                    out.append(Segment(line: i, start: rs, end: t.e, color: color, alpha: alpha, tail: true, tailAlpha: 0.42 * str, near: false, open: false, title: title))
                } else {
                    out.append(Segment(line: i, start: t.s, end: t.e, color: color, alpha: alpha, tail: false, tailAlpha: 0, near: false, open: false, title: title))
                }
            }
            for t in toks where t.ph == true && !toks.contains(where: { $0.ph != true && $0.s <= t.s && t.e <= $0.e }) {
                let g = groups[t.g]!
                let alpha = (t.end == true ? 24.0 : 14.0) * (0.4 + 0.6 * (t.str ?? 1)) / 100
                out.append(Segment(line: i, start: t.s, end: t.e, color: ((g.color % colorCount) + colorCount) % colorCount, alpha: alpha, tail: false, tailAlpha: 0, near: false, open: false, title: "phrase rhyme"))
            }
            if nearMiss { for n in (a.near ?? []) where n.l == i && n.e <= len {
                out.append(Segment(line: i, start: n.s, end: n.e, color: nil, alpha: 0, tail: false, tailAlpha: 0, near: true, open: false, title: "near-miss — one sound from rhyming"))
            } }
            if unanswered { for o in (a.open ?? []) where o.l == i && o.e <= len && !toks.contains(where: { $0.s < o.e && o.s < $0.e }) {
                out.append(Segment(line: i, start: o.s, end: o.e, color: nil, alpha: 0.18, tail: false, tailAlpha: 0, near: false, open: true, title: "unanswered ending"))
            } }
        }
        return out
    }

    /// Light-mode palette from rhymepad's styles.css (dark mode uses the brighter set).
    public static let lightPalette: [UInt32] = [0xd9622a, 0x1f7fcc, 0x2f9e57, 0xb8479a, 0xc79a10, 0x7650d6, 0xd43a3a, 0x1a9e93,
                                                0x8a9e14, 0xd93a72, 0x4563dd, 0x5aae22, 0x189e9e, 0xc27326, 0x9563d1, 0x2b9a4c]
    public static let darkPalette: [UInt32] = [0xe8814a, 0x4ea3e8, 0x6fd08c, 0xd46fb8, 0xe8c54a, 0x9b7ce8, 0xe85a5a, 0x46cabf,
                                               0xc0d44e, 0xee5d8f, 0x6f8bf2, 0x8fe85a, 0x5ad8d8, 0xe0985a, 0xb88ce8, 0x56c878]
}
