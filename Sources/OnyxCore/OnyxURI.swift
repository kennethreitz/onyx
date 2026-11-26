import Foundation

/// `onyx://` URIs, matching [Obsidian's URI scheme](https://help.obsidian.md/Extending+Obsidian/Obsidian+URI)
/// so existing `obsidian://` links can be rewritten by changing the scheme. The same parser
/// also reads `obsidian://` so a click inside a note can be handled in Onyx without
/// registering that scheme with the system.
public enum OnyxURI: Equatable, Sendable {
    case open(Open)
    case search(Search)
    case new(New)
    case daily(New)
    /// The web clipper (`onyx://clip`). The payload is still parsed by `WebClip.request(from:)`.
    case clip

    public static let scheme = "onyx"
    public static let obsidianScheme = "obsidian"

    public struct Open: Equatable, Sendable {
        public var vault: String?
        public var file: String?
        public var heading: String?
        public var block: String?
        /// Absolute filesystem path; when set it overrides `vault` and `file` (Obsidian's rule).
        public var path: String?

        public init(vault: String? = nil, file: String? = nil, heading: String? = nil,
                    block: String? = nil, path: String? = nil) {
            self.vault = vault; self.file = file; self.heading = heading; self.block = block; self.path = path
        }
    }

    public struct Search: Equatable, Sendable {
        public var vault: String?
        public var query: String?
        public init(vault: String? = nil, query: String? = nil) {
            self.vault = vault; self.query = query
        }
    }

    public enum Spacing: String, Equatable, Sendable {
        case auto, newline, inline
    }

    /// Parameters shared by `new` and `daily` (Obsidian gives daily the same flags).
    public struct New: Equatable, Sendable {
        public var vault: String?
        public var name: String?
        public var file: String?
        public var path: String?
        public var content: String?
        public var clipboard: Bool
        public var silent: Bool
        public var append: Bool
        public var prepend: Bool
        public var overwrite: Bool
        /// Section to append or prepend under (`heading=Tasks`). Requires append or prepend.
        public var heading: String?
        public var spacing: Spacing
        /// Anchor taken from `file=Note#Heading` / `file=Note#^id`.
        public var fileHeading: String?
        public var fileBlock: String?

        public init(vault: String? = nil, name: String? = nil, file: String? = nil, path: String? = nil,
                    content: String? = nil, clipboard: Bool = false, silent: Bool = false,
                    append: Bool = false, prepend: Bool = false, overwrite: Bool = false,
                    heading: String? = nil, spacing: Spacing = .auto,
                    fileHeading: String? = nil, fileBlock: String? = nil) {
            self.vault = vault; self.name = name; self.file = file; self.path = path
            self.content = content; self.clipboard = clipboard; self.silent = silent
            self.append = append; self.prepend = prepend; self.overwrite = overwrite
            self.heading = heading; self.spacing = spacing
            self.fileHeading = fileHeading; self.fileBlock = fileBlock
        }

        /// Overwrite applies only when neither append nor prepend is set.
        public var shouldOverwrite: Bool { overwrite && !append && !prepend }
    }

    // MARK: Parse

    /// Parse an `onyx://` or `obsidian://` URL. Unknown actions, or `clip` on the Obsidian scheme, return nil.
    public static func parse(_ url: URL) -> OnyxURI? {
        guard let scheme = url.scheme?.lowercased(), isHandledScheme(scheme),
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let host = (comps.host ?? "").lowercased()
        let path = comps.path
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let first = trimmed.split(separator: "/").first.map { String($0).lowercased() } ?? ""

        let action: String
        var shorthand: String?
        if host == "x-callback-url" {
            action = first
        } else if host.isEmpty {
            action = first
        } else if host == "vault" {
            action = "vault"
            shorthand = trimmed
        } else {
            action = host
        }

        let items = comps.queryItems ?? []
        let fragment = decodedFragment(url, comps)

        switch action {
        case "clip":
            return scheme == Self.scheme ? .clip : nil
        case "open":
            return .open(parseOpen(items, fragment: fragment))
        case "search":
            return .search(Search(vault: value(items, "vault"), query: value(items, "query")))
        case "new":
            return .new(parseNew(items, fragment: fragment))
        case "daily":
            return .daily(parseNew(items, fragment: fragment))
        case "vault":
            return parseShorthand(shorthand ?? "", vaultOverride: value(items, "vault"), fragment: fragment)
        default:
            return nil
        }
    }

    public static func parse(_ string: String) -> OnyxURI? {
        guard let url = URL(string: string) else { return nil }
        return parse(url)
    }

    public static func isHandledScheme(_ scheme: String) -> Bool {
        let s = scheme.lowercased()
        return s == Self.scheme || s == Self.obsidianScheme
    }

    /// An `onyx://` or `obsidian://` URL overlapping `offset` in `text`: a raw URL, or the
    /// target of a Markdown link. Used when a click inside a note should stay in Onyx.
    public static func url(in text: String, at offset: Int) -> URL? {
        let ns = text as NSString
        guard offset >= 0, offset <= ns.length else { return nil }
        if let re = try? NSRegularExpression(pattern: #"!?\[[^\]\n]*\]\(([^)\n]+)\)"#) {
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length))
            where NSLocationInRange(offset, m.range) || NSMaxRange(m.range) == offset {
                var t = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
                if let sp = t.range(of: " \"") { t = String(t[..<sp.lowerBound]) }
                if t.hasPrefix("<"), t.hasSuffix(">") { t = String(t.dropFirst().dropLast()) }
                if let u = URL(string: t), isHandledScheme(u.scheme ?? "") { return u }
            }
        }
        if let re = try? NSRegularExpression(pattern: #"(?i)(?:onyx|obsidian)://[^\s)<>\]]+"#) {
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length))
            where NSLocationInRange(offset, m.range) || NSMaxRange(m.range) == offset {
                var s = ns.substring(with: m.range)
                while s.hasSuffix(".") || s.hasSuffix(",") || s.hasSuffix(";") || s.hasSuffix(")") { s.removeLast() }
                if let u = URL(string: s), isHandledScheme(u.scheme ?? "") { return u }
            }
        }
        return nil
    }

    // MARK: Build

    /// Percent-encode everything except unreserved characters, so `/`, `+`, `&`, `=` and `#`
    /// in a value survive (URLComponents leaves `+` alone, which some parsers read as a space).
    public static func encode(_ s: String) -> String {
        var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    /// `onyx://open?vault=…&file=…`, with a heading or block id folded into `file` as `#Heading` / `#^id`.
    public static func makeOpen(vault: String, file: String, heading: String? = nil, block: String? = nil) -> URL? {
        var fileVal = file
        if let block, !block.isEmpty { fileVal += "#^" + block }
        else if let heading, !heading.isEmpty { fileVal += "#" + heading }
        return make(action: "open", query: [("vault", vault), ("file", fileVal)])
    }

    public static func make(action: String, query: [(String, String)]) -> URL? {
        let parts = query.compactMap { k, v -> String? in
            let t = v
            if t.isEmpty && k != "query" { return nil }
            return k + "=" + encode(t)
        }
        var s = "onyx://\(action)"
        if !parts.isEmpty { s += "?" + parts.joined(separator: "&") }
        return URL(string: s)
    }

    // MARK: Paths

    /// Split a vault-relative file value into the path and an optional heading or `^block` id.
    /// `Note#Heading`, `Note#^id`, and a trailing `#` with nothing after it are all accepted.
    public static func splitAnchor(_ raw: String) -> (file: String, heading: String?, block: String?) {
        guard let i = raw.firstIndex(of: "#") else { return (raw, nil, nil) }
        let file = String(raw[..<i])
        let rest = String(raw[raw.index(after: i)...])
        if rest.hasPrefix("^") {
            let id = String(rest.dropFirst())
            return (file, nil, id.isEmpty ? nil : id)
        }
        return (file, rest.isEmpty ? nil : rest, nil)
    }

    /// A vault-relative path with `.` / `..` folded, or nil if it would leave the vault.
    /// Leading slashes are stripped; backslashes become slashes. An empty result is the vault root.
    public static func normalizeRelative(_ raw: String) -> String? {
        let s = raw.replacingOccurrences(of: "\\", with: "/")
        var out: [String] = []
        for part in s.split(separator: "/", omittingEmptySubsequences: true).map(String.init) {
            if part == "." { continue }
            if part == ".." {
                if out.isEmpty { return nil }
                out.removeLast()
                continue
            }
            out.append(part)
        }
        return out.joined(separator: "/")
    }

    /// Add `.md` when the last path component has no extension. Other extensions are left alone.
    public static func markdownPath(for file: String) -> String {
        let last = (file as NSString).lastPathComponent
        if last.contains(".") { return file }
        return file + ".md"
    }

    // MARK: Private parse helpers

    private static func parseOpen(_ items: [URLQueryItem], fragment: String?) -> Open {
        var file = value(items, "file")
        var heading: String?
        var block: String?
        if let f = file {
            let parts = splitAnchor(f)
            file = parts.file
            heading = parts.heading
            block = parts.block
        }
        if heading == nil, block == nil, let fragment, !fragment.isEmpty {
            if fragment.hasPrefix("^") {
                let id = String(fragment.dropFirst())
                if !id.isEmpty { block = id }
            } else {
                heading = fragment
            }
        }
        return Open(vault: value(items, "vault"), file: emptyToNil(file), heading: heading, block: block,
                    path: value(items, "path"))
    }

    private static func parseNew(_ items: [URLQueryItem], fragment: String?) -> New {
        var file = value(items, "file")
        var fileHeading: String?
        var fileBlock: String?
        if let f = file {
            let parts = splitAnchor(f)
            file = parts.file
            fileHeading = parts.heading
            fileBlock = parts.block
        }
        if fileHeading == nil, fileBlock == nil, let fragment, !fragment.isEmpty {
            if fragment.hasPrefix("^") {
                let id = String(fragment.dropFirst())
                if !id.isEmpty { fileBlock = id }
            } else {
                fileHeading = fragment
            }
        }
        let spacingRaw = value(items, "spacing")?.lowercased()
        let spacing = spacingRaw.flatMap(Spacing.init(rawValue:)) ?? .auto
        return New(vault: value(items, "vault"), name: value(items, "name"), file: emptyToNil(file),
                   path: value(items, "path"), content: value(items, "content"),
                   clipboard: flag(items, "clipboard"), silent: flag(items, "silent"),
                   append: flag(items, "append"), prepend: flag(items, "prepend"),
                   overwrite: flag(items, "overwrite"), heading: value(items, "heading"),
                   spacing: spacing, fileHeading: fileHeading, fileBlock: fileBlock)
    }

    /// `onyx://vault/<vault>/<path>` — the path may include a `#Heading` / `#^id` already decoded.
    private static func parseShorthand(_ rest: String, vaultOverride: String?, fragment: String?) -> OnyxURI? {
        let decoded = rest
        guard !decoded.isEmpty else { return nil }
        var parts = decoded.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty else { return nil }
        let vault = vaultOverride ?? parts.removeFirst()
        var file = parts.joined(separator: "/")
        var heading: String?
        var block: String?
        if !file.isEmpty {
            let a = splitAnchor(file)
            file = a.file
            heading = a.heading
            block = a.block
        }
        if heading == nil, block == nil, let fragment, !fragment.isEmpty {
            if fragment.hasPrefix("^") {
                let id = String(fragment.dropFirst())
                if !id.isEmpty { block = id }
            } else {
                heading = fragment
            }
        }
        return .open(Open(vault: vault, file: file.isEmpty ? nil : file, heading: heading, block: block))
    }

    private static func value(_ items: [URLQueryItem], _ name: String) -> String? {
        for item in items.reversed() where item.name.lowercased() == name {
            guard let v = item.value else { return nil }
            let t = v
            return t.isEmpty ? nil : t
        }
        return nil
    }

    /// A flag is true when the parameter is present and not an explicit false (`false`, `0`, `no`).
    /// A bare `append` or `append=` counts as true, matching Obsidian's "include this parameter".
    public static func flag(_ items: [URLQueryItem], _ name: String) -> Bool {
        guard let item = items.last(where: { $0.name.lowercased() == name }) else { return false }
        let s = (item.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.isEmpty { return true }
        return s != "false" && s != "0" && s != "no"
    }

    private static func emptyToNil(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        return s
    }

    private static func decodedFragment(_ url: URL, _ comps: URLComponents) -> String? {
        if let f = comps.fragment, !f.isEmpty { return f }
        if let f = url.fragment, !f.isEmpty { return f }
        return nil
    }
}

// MARK: - Vault resolution

public struct KnownVault: Equatable, Sendable {
    public var name: String
    public var url: URL
    public var id: String?

    public init(name: String? = nil, url: URL, id: String? = nil) {
        self.url = url.standardizedFileURL
        self.name = name ?? self.url.lastPathComponent
        self.id = id
    }
}

public enum OnyxURIVaults {
    /// Resolve a vault name or Obsidian vault id. With no name, the current vault is used.
    /// When several known vaults share a folder name, the current one wins, then the earliest
    /// in `among` (callers should put recents first).
    public static func resolve(_ nameOrID: String?, among vaults: [KnownVault], current: KnownVault?) -> KnownVault? {
        guard let raw = nameOrID?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return current
        }
        if let v = vaults.first(where: { $0.id?.caseInsensitiveCompare(raw) == .orderedSame }) { return v }
        if let v = vaults.first(where: { $0.url.path.caseInsensitiveCompare(raw) == .orderedSame }) { return v }
        let named = vaults.filter { $0.name.caseInsensitiveCompare(raw) == .orderedSame }
        if named.isEmpty { return nil }
        if let current, named.contains(where: { $0.url.path.caseInsensitiveCompare(current.url.path) == .orderedSame }) {
            return current
        }
        return named.first
    }

    /// The most specific known vault containing this absolute path, and the vault-relative remainder
    /// (empty when the path is the vault root). Nil when no known vault contains it, or the relative
    /// remainder would escape (should not happen for a real prefix match).
    public static func containing(_ absolute: String, among vaults: [KnownVault]) -> (KnownVault, String)? {
        let expanded = (absolute as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        let path = url.path
        let matches = vaults.filter { vault in
            let root = vault.url.standardizedFileURL.path
            if path.caseInsensitiveCompare(root) == .orderedSame { return true }
            return path.lowercased().hasPrefix(root.lowercased() + "/")
        }
        guard let best = matches.max(by: { $0.url.path.count < $1.url.path.count }) else { return nil }
        let root = best.url.standardizedFileURL.path
        if path.count == root.count { return (best, "") }
        let rel = String(path.dropFirst(root.count + 1))
        guard let normalized = OnyxURI.normalizeRelative(rel) else { return nil }
        return (best, normalized)
    }

    /// Vaults listed in Obsidian's app-level `obsidian.json` (`vaults` keyed by id, each with `path`).
    /// Ordered most-recently-used first when a `ts` is present.
    public static func parseObsidianAppJSON(_ data: Data) -> [KnownVault] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let vaults = obj["vaults"] as? [String: Any] else { return [] }
        var rows: [(KnownVault, Double)] = []
        for (id, raw) in vaults {
            guard let d = raw as? [String: Any], let p = d["path"] as? String, !p.isEmpty else { continue }
            let url = URL(fileURLWithPath: p)
            let ts = (d["ts"] as? Double) ?? (d["ts"] as? Int).map(Double.init) ?? 0
            rows.append((KnownVault(name: url.lastPathComponent, url: url, id: id), ts))
        }
        rows.sort { $0.1 > $1.1 }
        return rows.map(\.0)
    }
}

// MARK: - new / daily content

public enum OnyxURIContent {
    /// Apply `new` / `daily` write semantics to an existing file body (nil if the file does not exist).
    ///
    /// - A missing file, or `overwrite=true` without append/prepend, becomes `incoming`.
    /// - `append` / `prepend` merge `incoming` into the existing body, optionally under `heading`.
    /// - Otherwise the existing body is left unchanged.
    public static func apply(existing: String?, incoming: String, flags: OnyxURI.New) -> String {
        if existing == nil || flags.shouldOverwrite { return incoming }
        let body = existing!
        if !flags.append && !flags.prepend { return body }
        if let heading = flags.heading, !heading.isEmpty {
            return splice(body, heading: heading, content: incoming, prepend: flags.prepend, spacing: flags.spacing)
        }
        return stitch(body, incoming, prepend: flags.prepend, spacing: flags.spacing)
    }

    public static func gap(_ spacing: OnyxURI.Spacing) -> String {
        switch spacing {
        case .inline: return ""
        case .newline: return "\n"
        case .auto: return "\n\n"
        }
    }

    public static func stitch(_ existing: String, _ content: String, prepend: Bool, spacing: OnyxURI.Spacing) -> String {
        let g = gap(spacing)
        if prepend { return content + g + existing }
        return existing + g + content
    }

    /// Insert `content` at the start or end of the section under `heading` (until the next heading
    /// of the same or higher level). If the heading is missing, falls back to stitching the whole file.
    public static func splice(_ existing: String, heading: String, content: String, prepend: Bool, spacing: OnyxURI.Spacing) -> String {
        let headings = NoteParser.summarize(existing).headings
        guard let h = headings.first(where: { $0.text.caseInsensitiveCompare(heading) == .orderedSame }) else {
            return stitch(existing, content, prepend: prepend, spacing: spacing)
        }
        let ranges = NoteParser.lineRanges(Array(existing.utf16))
        guard ranges.indices.contains(h.line) else {
            return stitch(existing, content, prepend: prepend, spacing: spacing)
        }
        let ns = existing as NSString
        let bodyStart = NSMaxRange(ranges[h.line])
        var bodyEnd = ns.length
        if let later = headings.first(where: { $0.line > h.line && $0.level <= h.level }), ranges.indices.contains(later.line) {
            bodyEnd = ranges[later.line].location
        }
        if prepend {
            return ns.replacingCharacters(in: NSRange(location: bodyStart, length: 0), with: content + gap(spacing))
        }
        // Trim trailing newlines in the section so `spacing` is exact, then keep the
        // following heading on its own line (unless spacing is inline).
        var trim = bodyEnd
        while trim > bodyStart, ns.character(at: trim - 1) == 10 { trim -= 1 }
        var piece = gap(spacing) + content
        if bodyEnd < ns.length, spacing != .inline, !piece.hasSuffix("\n") { piece += "\n" }
        return ns.replacingCharacters(in: NSRange(location: trim, length: bodyEnd - trim), with: piece)
    }
}
