import Foundation

/// Converts an article's HTML (usually Readability's output, serialized as XHTML by the
/// clipper) into clean Obsidian-flavoured Markdown: headings, emphasis, links, images,
/// nested lists and task lists, block quotes, fenced code with its language, GFM tables,
/// highlights, strikethrough, and YouTube embeds. Scripts, forms and chrome are dropped.
///
/// Images are hotlinked, never downloaded: `![alt](https://…)` with the absolute URL of the
/// largest `srcset` candidate (or a lazy-load attribute, or `src`). `data:` URIs, non-web
/// schemes, and tracking pixels are dropped.
public struct HTMLToMarkdown {
    public var baseURL: URL?

    public init(baseURL: URL? = nil) {
        self.baseURL = baseURL
    }

    // MARK: Entry points

    public func convert(_ html: String) -> String {
        guard let root = Self.parse(html) else { return Self.plainText(html) }
        let r = Renderer(owner: self)
        return r.finish(r.render(root))
    }

    /// Parse well-formed XHTML first (what XMLSerializer produces), then fall back to
    /// tidy-HTML parsing for tag soup.
    static func parse(_ html: String) -> XMLNode? {
        var trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // XMLDocument drops whitespace-only text between tags ("</b> <i>"); pin it with a marker
        // the renderer removes again.
        trimmed = trimmed.replacingOccurrences(of: #">(\s+)<"#, with: ">\u{E000}$1<", options: .regularExpression)
        if let d = try? XMLDocument(xmlString: "<onyx-root>" + trimmed + "</onyx-root>", options: [.nodePreserveWhitespace]),
           let r = d.rootElement() { return r }
        if let d = try? XMLDocument(xmlString: trimmed, options: [.documentTidyHTML, .nodePreserveWhitespace]),
           let r = d.rootElement() { return r }
        return nil
    }

    static func plainText(_ html: String) -> String {
        let noTags = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return noTags.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Helpers shared with tests

    /// Escape characters Markdown (and Onyx's math and wikilinks) would otherwise interpret.
    public static func escape(_ s: String, lineStart: Bool = true) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "\\", "*", "_", "`", "[", "]", "<", ">", "$", "|", "~", "=":
                // `=` and `~` only matter doubled; escaping the first of a pair is enough.
                if ch == "=" || ch == "~" {
                    if out.last == ch { out.removeLast(); out += "\\\(ch)\(ch)" } else { out.append(ch) }
                } else if ch == ">" || ch == "|" {
                    out.append(ch) // handled at line start / in tables
                } else {
                    out += "\\\(ch)"
                }
            default: out.append(ch)
            }
        }
        guard lineStart else { return out }
        // Line-start markers: headings, lists, quotes ("1. " becomes "1\\. ").
        let lead = out.prefix { $0 == " " }
        let rest = out.dropFirst(lead.count)
        if rest.range(of: #"^(#{1,6}\s|[-+]\s|>)"#, options: .regularExpression) != nil {
            out = String(lead) + "\\" + rest
        } else if let r = rest.range(of: #"^\d+[.)]\s"#, options: .regularExpression) {
            let digits = rest[r].prefix { $0.isNumber }
            out = String(lead) + digits + "\\" + rest.dropFirst(digits.count)
        }
        return out
    }

    /// The largest candidate in a `srcset` ("a.jpg 480w, b.jpg 1080w" → "b.jpg"); `data:`
    /// candidates are skipped.
    public static func bestFromSrcset(_ srcset: String) -> String? {
        var best: (String, Double)? = nil
        for part in srcset.split(separator: ",") {
            let bits = part.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            guard let u = bits.first, !u.lowercased().hasPrefix("data:") else { continue }
            var w = 1.0
            if bits.count > 1 {
                let d = bits[1]
                w = Double(d.dropLast()) ?? 1
                if d.hasSuffix("x") { w *= 1000 }
            }
            if best == nil || w > best!.1 { best = (String(u), w) }
        }
        return best?.0
    }

    /// Hosts and paths of well-known analytics beacons that pages embed as 1×1 images.
    static let trackerPatterns = ["google-analytics.com/", "googletagmanager.com/", "doubleclick.net/", "facebook.com/tr",
                                  "scorecardresearch.com/", "quantserve.com/", "pixel.wp.com/", "pixel.quantserve", "/b/ss/",
                                  "bat.bing.com/", "analytics.twitter.com/", "t.co/i/adsct", "ct.pinterest.com/", "px.ads.linkedin.com/",
                                  "/pixel.gif", "/pixel.png", "/spacer.gif", "/blank.gif", "/1x1.gif", "/1x1.png", "/transparent.gif"]

    /// A tracking pixel: 1–2px in either declared dimension, or a known beacon URL.
    static func isTrackingPixel(src: String, width: String?, height: String?) -> Bool {
        func px(_ v: String?) -> Double? { v.flatMap { Double($0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "px", with: "")) } }
        if let w = px(width), w <= 2 { return true }
        if let h = px(height), h <= 2 { return true }
        let l = src.lowercased()
        return trackerPatterns.contains { l.contains($0) }
    }

    func absolute(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return t }
        if t.hasPrefix("data:") || t.hasPrefix("#") || t.hasPrefix("mailto:") { return t }
        if let u = URL(string: t, relativeTo: baseURL)?.absoluteURL, u.scheme != nil { return u.absoluteString }
        if let enc = t.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
           let u = URL(string: enc, relativeTo: baseURL)?.absoluteURL, u.scheme != nil { return u.absoluteString }
        return t
    }

    /// A Markdown link destination: spaces and parentheses percent-encoded.
    static func destination(_ s: String) -> String {
        s.replacingOccurrences(of: " ", with: "%20").replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29")
    }

    /// YouTube video id from an embed / watch URL.
    public static func youTubeID(_ url: String) -> String? {
        guard let u = URLComponents(string: url), let host = u.host?.lowercased() else { return nil }
        if host.hasSuffix("youtube.com") || host.hasSuffix("youtube-nocookie.com") {
            if u.path.hasPrefix("/embed/") { let id = u.path.dropFirst(7).split(separator: "/").first.map(String.init); return id?.isEmpty == false ? id : nil }
            if u.path == "/watch" { return u.queryItems?.first { $0.name == "v" }?.value }
        }
        if host == "youtu.be" { let id = String(u.path.dropFirst()); return id.isEmpty ? nil : id }
        return nil
    }
}

// MARK: - Renderer

private final class Renderer {
    let owner: HTMLToMarkdown
    var codeBlocks: [String] = []
    var preDepth = 0
    var marks: [String: Int] = [:]

    init(owner: HTMLToMarkdown) { self.owner = owner }

    static let dropped: Set<String> = ["script", "style", "noscript", "template", "head", "title", "meta", "link",
                                       "button", "input", "select", "textarea", "option", "svg", "canvas", "form",
                                       "nav", "object", "embed", "map", "dialog", "source", "track", "audio"]
    static let blocks: Set<String> = ["p", "div", "section", "article", "main", "header", "footer", "aside", "figure",
                                      "details", "summary", "address", "center", "body", "html", "hgroup", "dl", "fieldset", "caption"]

    func children(_ n: XMLNode) -> String {
        var out = ""
        for c in n.children ?? [] {
            if c.kind == .text, preDepth == 0 {
                // List/heading markers only need escaping where the text starts a line.
                let atLineStart = out.isEmpty || out.hasSuffix("\n")
                let s = (c.stringValue ?? "").replacingOccurrences(of: "\u{E000}", with: "")
                out += HTMLToMarkdown.escape(collapse(s), lineStart: atLineStart)
            } else {
                out += render(c)
            }
        }
        return out
    }

    func name(_ n: XMLNode) -> String { (n.localName ?? n.name ?? "").lowercased() }

    func attr(_ n: XMLNode, _ key: String) -> String? {
        guard let e = n as? XMLElement else { return nil }
        for a in e.attributes ?? [] where (a.localName ?? a.name ?? "").lowercased() == key {
            if let v = a.stringValue, !v.isEmpty { return v }
        }
        return nil
    }

    func elements(_ n: XMLNode, _ names: Set<String>) -> [XMLNode] {
        (n.children ?? []).filter { $0.kind == .element && names.contains(name($0)) }
    }

    func descendants(_ n: XMLNode, _ names: Set<String>) -> [XMLNode] {
        var out: [XMLNode] = []
        for c in n.children ?? [] where c.kind == .element {
            if names.contains(name(c)) { out.append(c) }
            out += descendants(c, names)
        }
        return out
    }

    func collapse(_ s: String) -> String {
        s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    func render(_ n: XMLNode) -> String {
        switch n.kind {
        case .text:
            let s = (n.stringValue ?? "").replacingOccurrences(of: "\u{E000}", with: "")
            return preDepth > 0 ? s : HTMLToMarkdown.escape(collapse(s))
        case .element:
            return element(n)
        case .document:
            return children(n)
        default:
            return ""
        }
    }

    /// Wrap inline content in a marker, keeping edge whitespace outside it.
    func wrap(_ n: XMLNode, _ mark: String) -> String {
        // Nested emphasis of the same kind (<i> inside <cite>) would close the outer one early.
        if marks[mark, default: 0] > 0 { return children(n) }
        marks[mark, default: 0] += 1
        let inner = children(n)
        marks[mark, default: 0] -= 1
        let t = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return inner }
        let lead = inner.hasPrefix(" ") || inner.hasPrefix("\n") ? " " : ""
        let trail = inner.hasSuffix(" ") || inner.hasSuffix("\n") ? " " : ""
        return lead + mark + t + mark + trail
    }

    func oneLine(_ s: String) -> String {
        s.replacingOccurrences(of: "\\s*\n\\s*", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    func element(_ n: XMLNode) -> String {
        let tag = name(n)
        if Renderer.dropped.contains(tag) { return "" }
        if attr(n, "hidden") != nil || (attr(n, "aria-hidden") == "true" && tag != "span") { return "" }
        switch tag {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(tag.dropFirst()) ?? 1
            let text = oneLine(children(n))
            guard !text.isEmpty else { return "" }
            return "\n\n" + String(repeating: "#", count: level) + " " + text + "\n\n"
        case "br":
            return preDepth > 0 ? "\n" : "\n"
        case "hr":
            return "\n\n---\n\n"
        case "strong", "b":
            return wrap(n, "**")
        case "em", "i", "cite", "dfn", "var":
            return wrap(n, "*")
        case "del", "s", "strike":
            return wrap(n, "~~")
        case "mark":
            return wrap(n, "==")
        case "code", "kbd", "samp", "tt":
            if preDepth > 0 { return children(n) }
            let raw = collapse((n.stringValue ?? "").replacingOccurrences(of: "\u{E000}", with: ""))
            let t = raw.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { return raw }
            var fence = "`"
            while t.contains(fence) { fence += "`" }
            let pad = t.hasPrefix("`") || t.hasSuffix("`") ? " " : ""
            return (raw.hasPrefix(" ") ? " " : "") + fence + pad + t + pad + fence + (raw.hasSuffix(" ") ? " " : "")
        case "pre":
            return pre(n)
        case "blockquote":
            let inner = finishFragment(children(n))
            guard !inner.isEmpty else { return "" }
            let quoted = inner.split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.isEmpty ? ">" : "> " + $0 }.joined(separator: "\n")
            return "\n\n" + quoted + "\n\n"
        case "q":
            return "“" + children(n) + "”"
        case "ul", "ol", "menu":
            return list(n, ordered: tag == "ol")
        case "li":
            return "\n\n- " + oneLine(children(n)) + "\n\n"
        case "a":
            return link(n)
        case "img":
            return img(n)
        case "picture":
            guard let i = descendants(n, ["img"]).first else { return "" }
            // <source srcset> candidates (often the large or modern-format ones) compete with the img's.
            let sets = descendants(n, ["source"]).compactMap { attr($0, "srcset") ?? attr($0, "data-srcset") }
            return img(i, extraSrcsets: sets)
        case "iframe", "video":
            let src = owner.absolute(attr(n, "src") ?? attr(n, "data-src") ?? "")
            if let id = HTMLToMarkdown.youTubeID(src) { return "\n\n![](https://www.youtube.com/watch?v=\(id))\n\n" }
            if tag == "video", !src.isEmpty, !src.hasPrefix("blob:") { return "\n\n[Video](\(HTMLToMarkdown.destination(src)))\n\n" }
            return ""
        case "figcaption":
            let t = oneLine(children(n))
            return t.isEmpty ? "" : "\n\n*" + t.trimmingCharacters(in: CharacterSet(charactersIn: "*")) + "*\n\n"
        case "table":
            return table(n)
        case "dt":
            let t = oneLine(children(n))
            return t.isEmpty ? "" : "\n\n**" + t + "**\n"
        case "dd":
            return "\n" + oneLine(children(n)) + "\n\n"
        default:
            let inner = children(n)
            if Renderer.blocks.contains(tag) { return "\n\n" + inner + "\n\n" }
            return inner
        }
    }

    func pre(_ n: XMLNode) -> String {
        var lang = attr(n, "data-onyx-lang") ?? ""
        if lang.isEmpty {
            let classes = [attr(n, "class")] + descendants(n, ["code"]).map { attr($0, "class") }
            for c in classes.compactMap({ $0 }) {
                for cls in c.split(separator: " ") {
                    for p in ["language-", "lang-", "highlight-source-", "brush:"] where cls.lowercased().hasPrefix(p) {
                        lang = String(cls.dropFirst(p.count))
                    }
                    if !lang.isEmpty { break }
                }
                if !lang.isEmpty { break }
            }
        }
        lang = lang.filter { $0.isLetter || $0.isNumber || "+-#_.".contains($0) }
        preDepth += 1
        var body = children(n)
        preDepth -= 1
        body = body.replacingOccurrences(of: "\r\n", with: "\n")
        while body.hasSuffix("\n") { body.removeLast() }
        while body.hasPrefix("\n") { body.removeFirst() }
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        var fence = "```"
        while body.contains(fence) { fence += "`" }
        codeBlocks.append(fence + lang + "\n" + body + "\n" + fence)
        return "\n\n\u{1}\(codeBlocks.count - 1)\u{1}\n\n"
    }

    func list(_ n: XMLNode, ordered: Bool) -> String {
        var number = Int(attr(n, "start") ?? "") ?? 1
        var items: [String] = []
        for li in n.children ?? [] {
            if li.kind == .element, ["ul", "ol"].contains(name(li)) {
                // Malformed nesting: a list directly inside a list belongs to the previous item.
                let nested = finishFragment(list(li, ordered: name(li) == "ol"))
                if !nested.isEmpty {
                    let ind = nested.split(separator: "\n", omittingEmptySubsequences: false).map { $0.isEmpty ? "" : "    " + $0 }.joined(separator: "\n")
                    if items.isEmpty { items.append(ind) } else { items[items.count - 1] += "\n" + ind }
                }
                continue
            }
            guard li.kind == .element, name(li) == "li" else { continue }
            var marker = ordered ? "\(number). " : "- "
            number += 1
            // Task lists: a leading checkbox.
            if let box = descendants(li, ["input"]).first, attr(box, "type")?.lowercased() == "checkbox" {
                marker += attr(box, "checked") != nil ? "[x] " : "[ ] "
            }
            var body = finishFragment(children(li))
            let loose = !descendants(li, ["p", "pre", "blockquote"]).isEmpty
            if !loose { body = body.replacingOccurrences(of: "\n{2,}", with: "\n", options: .regularExpression) }
            let pad = String(repeating: " ", count: ordered ? marker.count - (marker.hasSuffix("] ") ? 4 : 0) : 2)
            let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
            var out = marker + (lines.first.map(String.init) ?? "")
            for l in lines.dropFirst() { out += "\n" + (l.isEmpty ? "" : pad + l) }
            items.append(out)
        }
        guard !items.isEmpty else { return "" }
        return "\n\n" + items.joined(separator: "\n") + "\n\n"
    }

    func link(_ n: XMLNode) -> String {
        let inner = children(n)
        let text = oneLine(inner)
        let href = owner.absolute(attr(n, "href") ?? "")
        if href.isEmpty || href.hasPrefix("#") || href.lowercased().hasPrefix("javascript:") { return inner }
        if text.isEmpty { return "" }
        // An image wrapped in a link: keep the image (an embed can't sit inside a link).
        if text.hasPrefix("![") && text.hasSuffix(")") || text.hasPrefix("![[") { return text }
        if text.contains("\u{1}") { return inner }
        let lead = inner.hasPrefix(" ") ? " " : "", trail = inner.hasSuffix(" ") ? " " : ""
        return lead + "[" + text + "](" + HTMLToMarkdown.destination(href) + ")" + trail
    }

    /// An image as a hotlink to the web: the largest srcset candidate, else a lazy-load
    /// attribute, else `src`, made absolute. Nothing is downloaded.
    func img(_ n: XMLNode, extraSrcsets: [String] = []) -> String {
        let sets = [attr(n, "srcset"), attr(n, "data-srcset"), attr(n, "data-lazy-srcset")].compactMap { $0 } + extraSrcsets
        var src = HTMLToMarkdown.bestFromSrcset(sets.joined(separator: ", ")) ?? ""
        for lazy in ["data-src", "data-original", "data-lazy-src", "data-url", "data-hi-res-src", "src"] where src.isEmpty {
            if let l = attr(n, lazy)?.trimmingCharacters(in: .whitespacesAndNewlines), !l.isEmpty, !l.lowercased().hasPrefix("data:") { src = l }
        }
        src = owner.absolute(src)
        guard let scheme = URL(string: src)?.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return "" }
        if HTMLToMarkdown.isTrackingPixel(src: src, width: attr(n, "width"), height: attr(n, "height")) { return "" }
        let alt = oneLine(collapse(attr(n, "alt") ?? "")).replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
        return "![\(alt)](\(HTMLToMarkdown.destination(src)))"
    }

    func table(_ n: XMLNode) -> String {
        var rows: [XMLNode] = []
        func collect(_ x: XMLNode) {
            for c in x.children ?? [] where c.kind == .element {
                switch name(c) {
                case "tr": rows.append(c)
                case "thead", "tbody", "tfoot": collect(c)
                default: break
                }
            }
        }
        collect(n)
        let cellsPerRow = rows.map { elements($0, ["td", "th"]) }
        let cols = cellsPerRow.map(\.count).max() ?? 0
        // Layout tables (one column, or nested tables) read better as plain blocks.
        if cols <= 1 || !descendants(n, ["table"]).isEmpty {
            return "\n\n" + children(n) + "\n\n"
        }
        let caption = elements(n, ["caption"]).first.map { oneLine(children($0)) } ?? ""
        func cell(_ c: XMLNode) -> String {
            let t = oneLine(children(c).replacingOccurrences(of: "\u{1}", with: ""))
            return t.replacingOccurrences(of: "|", with: "\\|")
        }
        var lines: [String] = []
        for (i, cells) in cellsPerRow.enumerated() {
            var vals = cells.map(cell)
            while vals.count < cols { vals.append("") }
            lines.append("| " + vals.joined(separator: " | ") + " |")
            if i == 0 { lines.append("|" + String(repeating: " --- |", count: cols)) }
        }
        return "\n\n" + (caption.isEmpty ? "" : "*" + caption + "*\n\n") + lines.joined(separator: "\n") + "\n\n"
    }

    /// Tidy a fragment: trim trailing spaces on lines, at most one blank line, no edge blank lines.
    func finishFragment(_ s: String) -> String {
        var lines = s.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            var l = String(line)
            while l.last == " " || l.last == "\t" { l.removeLast() }
            // Leading spaces on a text line are layout noise (code and nesting are re-indented explicitly).
            return l
        }
        var out: [String] = []
        for l in lines {
            if l.trimmingCharacters(in: .whitespaces).isEmpty {
                if let last = out.last, !last.isEmpty { out.append("") }
            } else { out.append(l) }
        }
        while out.last == "" { out.removeLast() }
        lines = out
        // A single leading space is an inline-join artifact; two or more is list/code nesting.
        return lines.map { l in
            l.hasPrefix(" ") && !l.hasPrefix("  ") ? String(l.dropFirst()) : l
        }.joined(separator: "\n")
    }

    func finish(_ s: String) -> String {
        var md = finishFragment(s)
        // Runs of spaces inside a line (adjacent inline nodes) collapse; code is still a placeholder here.
        md = md.replacingOccurrences(of: "(?m)(\\S) {2,}", with: "$1 ", options: .regularExpression)
        // Put code blocks back, indented to match their placeholder (inside list items).
        if !codeBlocks.isEmpty {
            let lines = md.split(separator: "\n", omittingEmptySubsequences: false)
            md = lines.map { line -> String in
                let t = line.trimmingCharacters(in: .whitespaces)
                guard t.hasPrefix("\u{1}"), t.hasSuffix("\u{1}"), let i = Int(t.dropFirst().dropLast()), codeBlocks.indices.contains(i) else {
                    return String(line).replacingOccurrences(of: "\u{1}", with: "")
                }
                let indent = String(line.prefix { $0 == " " })
                return codeBlocks[i].split(separator: "\n", omittingEmptySubsequences: false)
                    .map { $0.isEmpty ? "" : indent + $0 }.joined(separator: "\n")
            }.joined(separator: "\n")
        }
        return md.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
