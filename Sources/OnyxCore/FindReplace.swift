import Foundation

/// Vault-wide find and replace: matching, preview, and applying a substitution.
///
/// Literal or regular-expression search, with optional whole-word and case
/// options, a vault / folder / note scope, and a switch to skip YAML frontmatter.
/// Regex replacements understand `$1` / `$0` capture groups (and `\1` / `\&`).
public enum FindReplace {

    public enum Scope: Equatable, Sendable {
        case vault
        /// Vault-relative folder; the empty string is the vault root (root-level notes only).
        /// A non-empty folder includes that folder's notes and everything under it.
        case folder(String)
        case note(String)

        public func contains(_ path: String) -> Bool {
            switch self {
            case .vault:
                return true
            case .note(let p):
                return p == path
            case .folder(let folder):
                if folder.isEmpty { return (path as NSString).deletingLastPathComponent.isEmpty }
                return path == folder || path.hasPrefix(folder + "/")
            }
        }
    }

    public struct Options: Equatable, Sendable {
        public var matchCase: Bool
        public var wholeWord: Bool
        public var regex: Bool
        public var includeFrontmatter: Bool
        public var scope: Scope

        public init(matchCase: Bool = false, wholeWord: Bool = false, regex: Bool = false,
                    includeFrontmatter: Bool = true, scope: Scope = .vault) {
            self.matchCase = matchCase
            self.wholeWord = wholeWord
            self.regex = regex
            self.includeFrontmatter = includeFrontmatter
            self.scope = scope
        }
    }

    /// One non-overlapping match, with enough context to preview a substitution.
    public struct Match: Equatable, Hashable, Sendable, Identifiable {
        public var path: String
        public var range: NSRange
        public var text: String
        public var replacement: String
        /// 1-based line number of the start of the match.
        public var line: Int
        public var lineRange: NSRange
        public var lineText: String
        public var prefix: String
        public var suffix: String
        public var id: String { "\(path):\(range.location):\(range.length)" }

        public init(path: String, range: NSRange, text: String, replacement: String,
                    line: Int, lineRange: NSRange, lineText: String, prefix: String, suffix: String) {
            self.path = path
            self.range = range
            self.text = text
            self.replacement = replacement
            self.line = line
            self.lineRange = lineRange
            self.lineText = lineText
            self.prefix = prefix
            self.suffix = suffix
        }
    }

    public struct FileGroup: Equatable, Sendable {
        public var path: String
        public var matches: [Match]
    }

    public struct Preview: Equatable, Sendable {
        public var groups: [FileGroup]
        public var matchCount: Int
        public var fileCount: Int
        public var truncated: Bool
        public var error: String?

        public static let empty = Preview(groups: [], matchCount: 0, fileCount: 0, truncated: false, error: nil)

        public init(groups: [FileGroup], matchCount: Int, fileCount: Int, truncated: Bool, error: String?) {
            self.groups = groups
            self.matchCount = matchCount
            self.fileCount = fileCount
            self.truncated = truncated
            self.error = error
        }
    }

    /// One file after a replace, with the text as it was, so the replace can be undone.
    public struct FileEdit: Equatable, Sendable {
        public var path: String
        public var before: String
        public var after: String
        public var count: Int
    }

    public struct Plan: Equatable, Sendable {
        public var edits: [FileEdit]
        public var matchCount: Int
        public var fileCount: Int
        public var error: String?

        public static let empty = Plan(edits: [], matchCount: 0, fileCount: 0, error: nil)

        public init(edits: [FileEdit], matchCount: Int, fileCount: Int, error: String?) {
            self.edits = edits
            self.matchCount = matchCount
            self.fileCount = fileCount
            self.error = error
        }
    }

    /// How many matches a preview will keep (apply itself is not capped).
    public static let previewCap = 5_000

    public enum CompileResult {
        case empty
        case regex(NSRegularExpression)
        case invalid
    }

    /// Compile the find pattern. An empty query is not an error; it simply matches nothing.
    public static func compile(_ query: String, options: Options) -> CompileResult {
        if query.isEmpty { return .empty }
        var pattern = options.regex ? query : NSRegularExpression.escapedPattern(for: query)
        if options.wholeWord {
            pattern = "(?<![\\p{L}\\p{N}_])(?:\(pattern))(?![\\p{L}\\p{N}_])"
        }
        var opts: NSRegularExpression.Options = [.anchorsMatchLines]
        if !options.matchCase { opts.insert(.caseInsensitive) }
        do {
            return .regex(try NSRegularExpression(pattern: pattern, options: opts))
        } catch {
            return .invalid
        }
    }

    /// Every match in one string, in document order. Zero-length matches are skipped.
    /// Returns nil when the pattern is an invalid regular expression.
    public static func matches(of query: String, replacement: String, in text: String,
                               path: String = "", options: Options) -> [Match]? {
        switch compile(query, options: options) {
        case .invalid: return nil
        case .empty: return []
        case .regex(let re):
            return collect(re, replacement: replacement, in: text, path: path, options: options, cap: Int.max).matches
        }
    }

    public static func preview(query: String, replacement: String, notes: [(path: String, text: String)],
                               options: Options, cap: Int = previewCap) -> Preview {
        switch compile(query, options: options) {
        case .invalid:
            return Preview(groups: [], matchCount: 0, fileCount: 0, truncated: false, error: "Invalid regular expression.")
        case .empty:
            return .empty
        case .regex(let re):
            var groups: [FileGroup] = []
            var total = 0
            var truncated = false
            for note in notes {
                guard options.scope.contains(note.path) else { continue }
                let remain = max(0, cap - total)
                if remain == 0 { truncated = true; break }
                let found = collect(re, replacement: replacement, in: note.text, path: note.path, options: options, cap: remain)
                if !found.matches.isEmpty {
                    groups.append(FileGroup(path: note.path, matches: found.matches))
                    total += found.matches.count
                }
                if found.truncated { truncated = true; break }
            }
            return Preview(groups: groups, matchCount: total, fileCount: groups.count, truncated: truncated, error: nil)
        }
    }

    /// Preview over a vault snapshot. `contents` overrides snapshot text (open, unsaved editors).
    public static func preview(query: String, replacement: String, in snap: VaultSnapshot,
                               options: Options, contents: [String: String] = [:],
                               cap: Int = previewCap) -> Preview {
        let notes: [(path: String, text: String)] = snap.sortedNotePaths.compactMap { p in
            guard options.scope.contains(p) else { return nil }
            guard let t = contents[p] ?? snap.notes[p]?.content else { return nil }
            return (p, t)
        }
        return preview(query: query, replacement: replacement, notes: notes, options: options, cap: cap)
    }

    /// Apply the given matches (already computed, same file) from right to left.
    public static func applying(_ matches: [Match], to text: String) -> String {
        let ordered = matches.sorted { $0.range.location > $1.range.location }
        var s = text
        for m in ordered {
            let ns = s as NSString
            guard m.range.location >= 0, NSMaxRange(m.range) <= ns.length else { continue }
            s = ns.replacingCharacters(in: m.range, with: m.replacement)
        }
        return s
    }

    /// Build a write plan from a set of selected matches and the current file texts.
    public static func plan(matches: [Match], texts: [String: String]) -> Plan {
        let grouped = Dictionary(grouping: matches, by: \.path)
        var edits: [FileEdit] = []
        var count = 0
        for path in grouped.keys.sorted() {
            guard let text = texts[path] else { continue }
            let ms = (grouped[path] ?? []).sorted { $0.range.location < $1.range.location }
            guard !ms.isEmpty else { continue }
            let after = applying(ms, to: text)
            guard after != text else { continue }
            edits.append(FileEdit(path: path, before: text, after: after, count: ms.count))
            count += ms.count
        }
        return Plan(edits: edits, matchCount: count, fileCount: edits.count, error: nil)
    }

    // MARK: Internals

    private struct Collected {
        var matches: [Match]
        var truncated: Bool
    }

    private static func collect(_ re: NSRegularExpression, replacement: String, in text: String,
                                path: String, options: Options, cap: Int) -> Collected {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        let bodyStart = options.includeFrontmatter ? 0 : Frontmatter.parse(text).bodyOffset
        var out: [Match] = []
        var truncated = false
        re.enumerateMatches(in: text, options: [], range: full) { result, _, stop in
            guard let result else { return }
            let r = result.range
            guard r.length > 0, r.location != NSNotFound else { return }
            if r.location < bodyStart { return }
            if out.count >= cap { truncated = true; stop.pointee = true; return }
            let matched = ns.substring(with: r)
            let repl = substitute(result, in: text, template: replacement, regex: re, literal: !options.regex)
            let info = lineInfo(at: r.location, in: ns)
            let rel = r.location - info.range.location
            let prefix = rel > 0 && rel <= (info.text as NSString).length
                ? (info.text as NSString).substring(to: rel) : ""
            let endInLine = rel + r.length
            let suffix: String
            if r.location + r.length <= NSMaxRange(info.range), endInLine <= (info.text as NSString).length {
                suffix = (info.text as NSString).substring(from: endInLine)
            } else {
                let after = NSMaxRange(r)
                suffix = after < ns.length ? ns.substring(from: after) : ""
            }
            out.append(Match(path: path, range: r, text: matched, replacement: repl,
                             line: info.number, lineRange: info.range, lineText: info.text,
                             prefix: prefix, suffix: suffix))
        }
        return Collected(matches: out, truncated: truncated)
    }

    /// Regex templates use `$1` / `$0`. `\1` and `\&` are accepted as aliases. Literal
    /// replacements leave `$` and `\` alone.
    public static func substitute(_ result: NSTextCheckingResult, in text: String, template: String,
                                  regex: NSRegularExpression, literal: Bool) -> String {
        if literal { return template }
        let t = dollarTemplate(template)
        return regex.replacementString(for: result, in: text, offset: 0, template: t)
    }

    /// Translate unescaped `\1`…`\9`, `\0`, and `\&` to the `$` form NSRegularExpression wants.
    public static func dollarTemplate(_ s: String) -> String {
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "\\" {
                let n = s.index(after: i)
                if n < s.endIndex {
                    let d = s[n]
                    if d == "&" { out += "$0"; i = s.index(after: n); continue }
                    if d.isASCII && d.isNumber { out += "$"; out.append(d); i = s.index(after: n); continue }
                    out.append(d); i = s.index(after: n); continue
                }
            } else if c == "$" {
                let n = s.index(after: i)
                if n < s.endIndex, s[n] == "&" { out += "$0"; i = s.index(after: n); continue }
            }
            out.append(c)
            i = s.index(after: i)
        }
        return out
    }

    static func lineInfo(at utf16: Int, in ns: NSString) -> (number: Int, range: NSRange, text: String) {
        let loc = max(0, min(utf16, ns.length))
        var start = 0, end = 0, contentsEnd = 0
        ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: loc, length: 0))
        let lineRange = NSRange(location: start, length: contentsEnd - start)
        let number = ns.substring(to: start).reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        return (number, lineRange, ns.substring(with: lineRange))
    }
}
