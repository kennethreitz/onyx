import Foundation

/// Turns a Markdown note into spoken prose: frontmatter, comments, code, and
/// markup are stripped; links keep their visible name.
public enum SpeechText {
    public static func clean(_ markdown: String) -> String {
        var s = markdown.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let fm = Frontmatter.parse(s)
        if fm.bodyOffset > 0, fm.bodyOffset <= (s as NSString).length {
            s = (s as NSString).substring(from: fm.bodyOffset)
        }
        s = stripComments(s)
        s = stripFencedCode(s)
        s = replaceWikilinks(s)
        s = stripLines(s)
        s = rewriteInlines(s)
        return collapse(s)
    }

    // MARK: Comments and fences

    static let commentRegex = try! NSRegularExpression(pattern: #"(?s)%%.*?%%|<!--.*?-->"#)

    static func stripComments(_ text: String) -> String {
        commentRegex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: "")
    }

    static let fenceOpenRegex = try! NSRegularExpression(pattern: #"^ {0,3}(`{3,}|~{3,})"#)

    /// Drops fenced code blocks, including an unclosed fence through the end of the note.
    static func stripFencedCode(_ text: String) -> String {
        let ns = text as NSString
        var out = ""
        var loc = 0
        var open = false
        var marker = ""
        while loc < ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
            let line = ns.substring(with: lineRange)
            let lineLen = (line as NSString).length
            if let m = fenceOpenRegex.firstMatch(in: line, range: NSRange(location: 0, length: lineLen)) {
                let found = (line as NSString).substring(with: m.range(at: 1))
                if !open {
                    if !out.isEmpty, !out.hasSuffix("\n\n") { out += "\n" }
                    open = true
                    marker = found
                    loc = NSMaxRange(lineRange)
                    continue
                } else if found.first == marker.first, found.count >= marker.count {
                    open = false
                    marker = ""
                    loc = NSMaxRange(lineRange)
                    continue
                }
            }
            if !open { out += line }
            loc = NSMaxRange(lineRange)
        }
        return out
    }

    // MARK: Line-level markup

    static let headingRegex = try! NSRegularExpression(pattern: #"^ {0,3}#{1,6}[ \t]+"#)
    static let headingCloseRegex = try! NSRegularExpression(pattern: #"[ \t]+#+\s*$"#)
    static let setextRegex = try! NSRegularExpression(pattern: #"^ {0,3}(?:=+|-+)[ \t]*$"#)
    static let ruleRegex = try! NSRegularExpression(pattern: #"^ {0,3}(?:(?:-[ \t]*){3,}|(?:\*[ \t]*){3,}|(?:_[ \t]*){3,})$"#)
    static let quoteRegex = try! NSRegularExpression(pattern: #"^ {0,3}>[ \t]?"#)
    static let calloutRegex = try! NSRegularExpression(pattern: #"^\[![^\]]+\][ \t]*"#)
    static let listRegex = try! NSRegularExpression(pattern: #"^ {0,3}(?:[-*+]|\d+[.)])[ \t]+(?:\[[ xX]\][ \t]+)?"#)
    static let footnoteDefRegex = try! NSRegularExpression(pattern: #"^\[\^[^\]]+\]:[ \t]*"#)
    static let linkDefRegex = try! NSRegularExpression(pattern: #"^ {0,3}\[(?![\^])[^\]]+\]:[ \t]+\S.*$"#)

    static func stripLines(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var out: [String] = []
        out.reserveCapacity(lines.count)
        for line in lines {
            var t = line
            let trimmed = t.trimmingCharacters(in: .whitespaces)
            let full = NSRange(location: 0, length: (t as NSString).length)
            if ruleRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) != nil {
                out.append("")
                continue
            }
            if setextRegex.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) != nil {
                if !out.isEmpty { out.append("") }
                continue
            }
            if linkDefRegex.firstMatch(in: t, range: full) != nil {
                continue
            }
            t = quoteRegex.stringByReplacingMatches(in: t, range: NSRange(location: 0, length: (t as NSString).length), withTemplate: "")
            t = calloutRegex.stringByReplacingMatches(in: t, range: NSRange(location: 0, length: (t as NSString).length), withTemplate: "")
            t = headingRegex.stringByReplacingMatches(in: t, range: NSRange(location: 0, length: (t as NSString).length), withTemplate: "")
            t = headingCloseRegex.stringByReplacingMatches(in: t, range: NSRange(location: 0, length: (t as NSString).length), withTemplate: "")
            t = listRegex.stringByReplacingMatches(in: t, range: NSRange(location: 0, length: (t as NSString).length), withTemplate: "")
            t = footnoteDefRegex.stringByReplacingMatches(in: t, range: NSRange(location: 0, length: (t as NSString).length), withTemplate: "")
            if isTableRow(t) {
                if let cells = speakTableRow(t) {
                    out.append(cells)
                }
                continue
            }
            out.append(t)
        }
        return out.joined(separator: "\n")
    }

    static func isTableRow(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("|") || t.hasSuffix("|")
    }

    /// Spoken cells, or nil for a separator row that should be skipped.
    static func speakTableRow(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let cells = trimmed.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if cells.isEmpty { return nil }
        if cells.allSatisfy({ $0.allSatisfy({ $0 == "-" || $0 == ":" || $0 == " " }) }) { return nil }
        return cells.joined(separator: ", ")
    }

    // MARK: Inlines

    static let imageRegex = try! NSRegularExpression(pattern: #"!\[([^\]]*)\]\([^)]*\)"#)
    static let mdLinkRegex = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\([^)]*\)"#)
    static let refLinkRegex = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\[[^\]]*\]"#)
    static let autoLinkRegex = try! NSRegularExpression(pattern: #"<https?://[^>\s]+>|<[^>\s@]+@[^>\s]+>"#)
    static let bareURLRegex = try! NSRegularExpression(pattern: #"(?i)(?<![<@])(?:https?://|www\.)[^\s<>]+"#)
    static let inlineCodeRegex = try! NSRegularExpression(pattern: #"(?<!`)(`+)((?:(?!\1).)+?)\1(?!`)"#)
    static let displayMathRegex = try! NSRegularExpression(pattern: #"\$\$[\s\S]*?\$\$"#)
    static let inlineMathRegex = try! NSRegularExpression(pattern: #"(?<!\\)\$(?!\$)(?:\\.|[^$\n])+?(?<!\\)\$"#)
    static let footnoteRefRegex = try! NSRegularExpression(pattern: #"\[\^[^\]]+\]"#)
    static let brTagRegex = try! NSRegularExpression(pattern: #"(?i)<br\s*/?>"#)
    static let blockTagRegex = try! NSRegularExpression(pattern: #"(?i)</?(?:p|div|tr|li|h[1-6]|blockquote)[^>]*>"#)
    static let htmlTagRegex = try! NSRegularExpression(pattern: #"</?[A-Za-z][^>]*>"#)
    static let boldItalicRegex = try! NSRegularExpression(pattern: #"(\*\*\*|___)(.+?)\1"#)
    static let boldRegex = try! NSRegularExpression(pattern: #"(\*\*|__)(.+?)\1"#)
    static let italicStarRegex = try! NSRegularExpression(pattern: #"\*(?!\*)(.+?)\*"#)
    static let italicUnderRegex = try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9])_(?!_)(.+?)_(?![A-Za-z0-9])"#)
    static let strikeRegex = try! NSRegularExpression(pattern: #"~~(.+?)~~"#)
    static let highlightRegex = try! NSRegularExpression(pattern: #"==(.+?)=="#)
    static let unescapeRegex = try! NSRegularExpression(pattern: #"\\([\\`*_{}\[\]()#+\-.!|>])"#)

    static let mediaExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "tif", "tiff", "heic", "ico",
        "pdf", "mp3", "wav", "m4a", "aac", "ogg", "flac",
        "mp4", "mov", "webm", "m4v", "avi", "mkv",
    ]

    static func rewriteInlines(_ text: String) -> String {
        var s = text
        s = replace(imageRegex, in: s, template: "$1")
        s = replace(mdLinkRegex, in: s, template: "$1")
        s = replace(refLinkRegex, in: s, template: "$1")
        s = replace(autoLinkRegex, in: s, template: "")
        s = stripBareURLs(s)
        s = replace(inlineCodeRegex, in: s, template: "$2")
        s = replace(displayMathRegex, in: s, template: "")
        s = replace(inlineMathRegex, in: s, template: "")
        s = replace(footnoteRefRegex, in: s, template: "")
        s = replace(brTagRegex, in: s, template: " ")
        s = replace(blockTagRegex, in: s, template: "\n")
        s = replace(htmlTagRegex, in: s, template: "")
        s = replace(highlightRegex, in: s, template: "$1")
        s = replace(strikeRegex, in: s, template: "$1")
        s = replace(boldItalicRegex, in: s, template: "$2")
        s = replace(boldRegex, in: s, template: "$2")
        s = replace(italicStarRegex, in: s, template: "$1")
        s = replace(italicUnderRegex, in: s, template: "$1")
        s = replace(unescapeRegex, in: s, template: "$1")
        return s
    }

    static func replaceWikilinks(_ text: String) -> String {
        let links = NoteParser.parseWikiLinks(text)
        guard !links.isEmpty else { return text }
        let ns = NSMutableString(string: text)
        for link in links.reversed() {
            let range = link.range
            guard range.location != NSNotFound, NSMaxRange(range) <= ns.length else { continue }
            ns.replaceCharacters(in: range, with: spokenWiki(link))
        }
        return ns as String
    }

    static func spokenWiki(_ link: WikiLink) -> String {
        if let a = link.alias?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty { return a }
        let raw = link.target.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return "" }
        let last = (raw as NSString).lastPathComponent
        if isMedia(last) { return "" }
        let name = (last as NSString).deletingPathExtension
        return name.isEmpty ? last : name
    }

    static func isMedia(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return !ext.isEmpty && mediaExtensions.contains(ext)
    }

    static func stripBareURLs(_ text: String) -> String {
        let ns = text as NSString
        let matches = bareURLRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }
        let out = NSMutableString(string: text)
        for m in matches.reversed() {
            var r = m.range
            // Leave trailing sentence punctuation behind.
            while r.length > 0 {
                let last = out.substring(with: NSRange(location: NSMaxRange(r) - 1, length: 1))
                if ".,;:!?)]}\"'\u{201d}\u{2019}".contains(last) {
                    r.length -= 1
                } else { break }
            }
            out.replaceCharacters(in: r, with: "")
        }
        return out as String
    }

    static func replace(_ regex: NSRegularExpression, in text: String, template: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: template)
    }

    // MARK: Whitespace

    static func collapse(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n").map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            var t = trimmed.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            t = t.replacingOccurrences(of: #" +([.,;:!?])"#, with: "$1", options: .regularExpression)
            return t
        }
        // Collapse runs of blank lines to a single paragraph break.
        var out: [String] = []
        var blank = false
        for line in lines {
            if line.isEmpty {
                if !out.isEmpty { blank = true }
                continue
            }
            if blank { out.append(""); blank = false }
            out.append(line)
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
