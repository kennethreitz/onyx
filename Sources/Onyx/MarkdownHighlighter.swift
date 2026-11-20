import AppKit
import OnyxCore

/// Source-mode styling in the spirit of Reitz Mono: one honest monospace,
/// heading sizes from the LaTeX scale, syntax kept visible but faint.
struct MarkdownHighlighter {
    static let wiki = try! NSRegularExpression(pattern: #"(!?\[\[)([^\[\]\n]+?)(\]\])"#)
    static let mdLink = try! NSRegularExpression(pattern: #"(!?\[)([^\]\n]*)(\]\()([^)\n]*)(\))"#)
    static let bold = try! NSRegularExpression(pattern: #"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    static let italic = try! NSRegularExpression(pattern: #"(?<![\*\w])(\*|_)(?=[^\s\*])(.+?)(?<=[^\s\*])\1(?![\*\w])"#)
    static let highlight = try! NSRegularExpression(pattern: #"(==)(?=\S)(.+?)(?<=\S)(==)"#)
    static let mark = try! NSRegularExpression(pattern: #"<mark class=\"hltr-(\w+)\">(.+?)</mark>"#)
    static let code = try! NSRegularExpression(pattern: #"(`+)([^`\n]|[^`\n][^\n]*?[^`\n])\1"#)
    static let tag = try! NSRegularExpression(pattern: #"(?<![\w/&#])#[A-Za-z0-9_\-/]*[A-Za-z_\-/][A-Za-z0-9_\-/]*"#)
    static let comment = try! NSRegularExpression(pattern: #"%%[\s\S]*?%%"#)
    static let strike = try! NSRegularExpression(pattern: #"(~~)(.+?)(~~)"#)
    static let url = try! NSRegularExpression(pattern: #"https?://[^\s)>\]]+"#)
    static let footnote = try! NSRegularExpression(pattern: #"\[\^[^\]]+\]"#)

    var lineHeight: CGFloat { (Theme.editorSize * Theme.editorLineHeight).rounded() }

    func baseParagraph(indent: CGFloat = 0) -> NSMutableParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.minimumLineHeight = lineHeight
        p.maximumLineHeight = lineHeight
        p.headIndent = indent
        return p
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: Theme.editorFont(), .foregroundColor: Theme.ink, .paragraphStyle: baseParagraph(),
         .kern: -0.14, .ligature: 0, .baselineOffset: (lineHeight - Theme.editorSize * 1.3) / 2]
    }

    func apply(to ts: NSTextStorage) {
        let s = ts.string
        let ns = s as NSString
        let full = NSRange(location: 0, length: ns.length)
        ts.beginEditing()
        ts.setAttributes(baseAttributes, range: full)
        let fm = Frontmatter.parse(s)
        if fm.bodyOffset > 0 {
            ts.addAttributes([.foregroundColor: Theme.faint], range: NSRange(location: 0, length: fm.bodyOffset))
        }
        let codeBlocks = NoteParser.codeRanges(s)
        func skip(_ r: NSRange) -> Bool {
            r.location < fm.bodyOffset || codeBlocks.contains { NSIntersectionRange($0, r).length > 0 || NSLocationInRange(r.location, $0) }
        }
        for r in codeBlocks { ts.addAttributes([.foregroundColor: Theme.muted, .backgroundColor: Theme.paperAlt], range: r) }

        for f in InlineFields.parse(s) where !f.isFrontmatter {
            let r = NSRange(location: f.keyRange.location, length: f.keyRange.length + 2)
            ts.addAttributes([.foregroundColor: Theme.muted, .backgroundColor: Theme.paperAlt], range: r)
        }

        // Line-level: headings, quotes, lists, rules, tasks
        var loc = fm.bodyOffset
        while loc < ns.length {
            let lr = ns.lineRange(for: NSRange(location: loc, length: 0))
            defer { loc = NSMaxRange(lr) }
            if lr.length == 0 { break }
            if skip(NSRange(location: lr.location, length: 0)) { continue }
            let line = ns.substring(with: lr)
            if line.hasPrefix("#") {
                var level = 0
                for ch in line { if ch == "#" { level += 1 } else { break } }
                if level <= 6, line.dropFirst(level).hasPrefix(" ") {
                    let scale: [CGFloat] = [1.44, 1.2, 1.1, 1, 1, 1]
                    let size = (Theme.editorSize * scale[level - 1]).rounded()
                    let p = baseParagraph(); p.minimumLineHeight = max(lineHeight, size * 1.6); p.maximumLineHeight = p.minimumLineHeight
                    if level <= 2 { p.paragraphSpacingBefore = lineHeight * 0.35 }
                    ts.addAttributes([.font: Theme.editorFont(size, bold: true), .paragraphStyle: p], range: lr)
                    ts.addAttributes([.foregroundColor: Theme.faint], range: NSRange(location: lr.location, length: level))
                    continue
                }
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(">") {
                ts.addAttributes([.foregroundColor: Theme.muted], range: lr)
                if let gt = line.firstIndex(of: ">") {
                    let off = line.utf16.distance(from: line.utf16.startIndex, to: gt.samePosition(in: line.utf16)!)
                    ts.addAttributes([.foregroundColor: Theme.faint], range: NSRange(location: lr.location + off, length: 1))
                }
                if let c = trimmed.range(of: #"^>\s*\[![\w-]+\][+-]?"#, options: .regularExpression) {
                    let len = trimmed.utf16.distance(from: c.lowerBound, to: c.upperBound)
                    let start = line.utf16.count - line.drop(while: { $0 == " " }).utf16.count
                    ts.addAttributes([.font: Theme.editorFont(bold: true), .foregroundColor: Theme.ink], range: NSRange(location: lr.location + start, length: len))
                }
            }
            if trimmed == "---" || trimmed == "***" || trimmed == "___" { ts.addAttributes([.foregroundColor: Theme.faint], range: lr) }
            if let m = line.range(of: #"^\s*([-*+]|\d+[.)])\s"#, options: .regularExpression) {
                let len = line.utf16.distance(from: m.lowerBound, to: m.upperBound)
                ts.addAttributes([.foregroundColor: Theme.faint], range: NSRange(location: lr.location, length: len))
                // hanging indent for wrapped list lines
                let p = baseParagraph(indent: CGFloat(len) * Theme.editorFont().advancement(forGlyph: 0).width.nonZero(8.4))
                ts.addAttributes([.paragraphStyle: p], range: lr)
                let rest = line[m.upperBound...]
                if rest.hasPrefix("[x]") || rest.hasPrefix("[X]") {
                    ts.addAttributes([.foregroundColor: Theme.faint], range: NSRange(location: lr.location + len, length: lr.length - len))
                } else if rest.hasPrefix("[ ]") {
                    ts.addAttributes([.foregroundColor: Theme.muted], range: NSRange(location: lr.location + len, length: 3))
                }
            }
        }

        func each(_ re: NSRegularExpression, _ body: (NSTextCheckingResult) -> Void) {
            for m in re.matches(in: s, range: NSRange(location: fm.bodyOffset, length: ns.length - fm.bodyOffset)) where !skip(m.range) { body(m) }
        }
        let faint: [NSAttributedString.Key: Any] = [.foregroundColor: Theme.faint]
        each(Self.bold) { m in
            ts.addAttributes([.font: Theme.editorFont(currentSize(ts, m.range.location), bold: true)], range: m.range)
            ts.addAttributes(faint, range: NSRange(location: m.range.location, length: 2))
            ts.addAttributes(faint, range: NSRange(location: NSMaxRange(m.range) - 2, length: 2))
        }
        each(Self.italic) { m in
            ts.addAttributes([.font: Theme.editorFont(currentSize(ts, m.range.location), italic: true)], range: m.range)
            ts.addAttributes(faint, range: NSRange(location: m.range.location, length: 1))
            ts.addAttributes(faint, range: NSRange(location: NSMaxRange(m.range) - 1, length: 1))
        }
        each(Self.strike) { m in ts.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: Theme.muted], range: m.range(at: 2)) }
        each(Self.highlight) { m in
            ts.addAttributes([.backgroundColor: Theme.highlight], range: m.range(at: 2))
            ts.addAttributes(faint, range: m.range(at: 1)); ts.addAttributes(faint, range: m.range(at: 3))
        }
        each(Self.mark) { m in
            let name = (s as NSString).substring(with: m.range(at: 1)).lowercased()
            let hex = Theme.highlighters.first { $0.0.lowercased() == name }?.1 ?? 0xFFF3A3
            ts.addAttributes(faint, range: m.range)
            ts.addAttributes([.backgroundColor: NSColor(hex: hex, alpha: 0.55), .foregroundColor: Theme.ink], range: m.range(at: 2))
        }
        each(Self.code) { m in ts.addAttributes([.foregroundColor: Theme.muted, .backgroundColor: Theme.paperAlt], range: m.range) }
        each(Self.url) { m in ts.addAttributes([.foregroundColor: Theme.muted, .underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: Theme.border], range: m.range) }
        each(Self.mdLink) { m in
            ts.addAttributes(faint, range: m.range)
            ts.addAttributes([.foregroundColor: Theme.ink, .underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: Theme.faint], range: m.range(at: 2))
        }
        each(Self.wiki) { m in
            ts.addAttributes(faint, range: m.range(at: 1)); ts.addAttributes(faint, range: m.range(at: 3))
            let inner = m.range(at: 2)
            let innerStr = ns.substring(with: inner)
            var visible = inner
            if let bar = innerStr.range(of: "|") {
                let off = innerStr.utf16.distance(from: innerStr.utf16.startIndex, to: bar.lowerBound.samePosition(in: innerStr.utf16)!)
                ts.addAttributes(faint, range: NSRange(location: inner.location, length: off + 1))
                visible = NSRange(location: inner.location + off + 1, length: inner.length - off - 1)
            }
            ts.addAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: Theme.faint, .cursor: NSCursor.pointingHand], range: visible)
        }
        each(Self.tag) { m in ts.addAttributes([.foregroundColor: Theme.muted], range: m.range) }
        each(Self.footnote) { m in ts.addAttributes([.foregroundColor: Theme.faint], range: m.range) }
        for m in Self.comment.matches(in: s, range: full) { ts.addAttributes([.foregroundColor: Theme.faint], range: m.range) }
        ts.endEditing()
    }

    private func currentSize(_ ts: NSTextStorage, _ loc: Int) -> CGFloat {
        (ts.attribute(.font, at: loc, effectiveRange: nil) as? NSFont)?.pointSize ?? Theme.editorSize
    }
}

extension CGFloat { func nonZero(_ d: CGFloat) -> CGFloat { self > 0 ? self : d } }
