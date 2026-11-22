import Foundation

/// Obsidian's Note composer: merge two notes, or extract a selection or a heading section
/// into a new note (or append it to an existing one).
public enum NoteComposer {

    /// Where the source body is placed inside the target when merging.
    public enum Placement: String, CaseIterable, Sendable {
        case append, prepend
        public var title: String { self == .append ? "Append" : "Prepend" }
    }

    /// What replaces the extracted text in the source note.
    public enum AfterExtract: String, CaseIterable, Sendable {
        case link, embed, none
        public var title: String {
            switch self {
            case .link: "Link to new file"
            case .embed: "Embed new file"
            case .none: "None"
            }
        }
    }

    /// Folder a newly extracted note is created in.
    public enum NewLocation: String, CaseIterable, Sendable {
        case sameFolder, vaultRoot
        public var title: String {
            switch self {
            case .sameFolder: "Same folder as current file"
            case .vaultRoot: "Vault folder"
            }
        }
    }

    /// Settings ▸ Editor ▸ Note composer. Defaults match Obsidian's core plugin.
    public enum Settings {
        public static let confirmMergeKey = "onyx.composer.confirmMerge"
        public static let placementKey = "onyx.composer.placement"
        public static let locationKey = "onyx.composer.location"
        public static let afterExtractKey = "onyx.composer.afterExtract"
        public static let openAfterExtractKey = "onyx.composer.openAfterExtract"

        public static var confirmMerge: Bool {
            UserDefaults.standard.object(forKey: confirmMergeKey) as? Bool ?? true
        }
        public static var placement: Placement {
            Placement(rawValue: UserDefaults.standard.string(forKey: placementKey) ?? "") ?? .append
        }
        public static var location: NewLocation {
            NewLocation(rawValue: UserDefaults.standard.string(forKey: locationKey) ?? "") ?? .sameFolder
        }
        public static var afterExtract: AfterExtract {
            AfterExtract(rawValue: UserDefaults.standard.string(forKey: afterExtractKey) ?? "") ?? .link
        }
        public static var openAfterExtract: Bool {
            UserDefaults.standard.object(forKey: openAfterExtractKey) as? Bool ?? false
        }
    }

    // MARK: - Merge

    /// Combine `source` into `target`: frontmatter is merged, then the bodies are joined.
    /// Target scalar values win; list values are unioned (target first, then new source items).
    /// The result always ends with a newline when it is not empty.
    public static func merge(source: String, target: String, placement: Placement = .append) -> String {
        let srcFM = Frontmatter.parse(source)
        let dstFM = Frontmatter.parse(target)
        let srcBody = body(of: source, fm: srcFM)
        let dstBody = body(of: target, fm: dstFM)
        let props = mergeProperties(target: dstFM.properties, source: srcFM.properties)
        let joined: String
        switch placement {
        case .append: joined = joinBodies(dstBody, srcBody)
        case .prepend: joined = joinBodies(srcBody, dstBody)
        }
        return render(properties: props, body: joined)
    }

    /// The Markdown body of a note, with frontmatter removed and edge blank lines trimmed.
    public static func body(of text: String, fm: Frontmatter? = nil) -> String {
        let fm = fm ?? Frontmatter.parse(text)
        let ns = text as NSString
        let start = min(max(fm.bodyOffset, 0), ns.length)
        return ns.substring(from: start).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func joinBodies(_ a: String, _ b: String) -> String {
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return a + "\n\n" + b
    }

    public static func mergeProperties(target: [Property], source: [Property]) -> [Property] {
        var out = target
        for p in source {
            if let i = out.firstIndex(where: { $0.key.lowercased() == p.key.lowercased() }) {
                out[i] = Property(key: out[i].key, value: mergeValue(out[i].value, p.value))
            } else {
                out.append(p)
            }
        }
        return out
    }

    static func mergeValue(_ target: PropertyValue, _ source: PropertyValue) -> PropertyValue {
        switch (target, source) {
        case (.list(let a), .list(let b)):
            return .list(union(a, b))
        case (.list(let a), _):
            let s = source.display
            return s.isEmpty ? .list(a) : .list(union(a, [s]))
        case (_, .list(let b)):
            return .list(union([target.display], b))
        default:
            return target
        }
    }

    static func union(_ a: [String], _ b: [String]) -> [String] {
        var seen = Set(a)
        var out = a
        for x in b where !seen.contains(x) { out.append(x); seen.insert(x) }
        return out
    }

    /// Render properties as a YAML frontmatter block plus `body`.
    public static func render(properties: [Property], body: String) -> String {
        let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if properties.isEmpty {
            return body.isEmpty ? "" : body + "\n"
        }
        var lines = ["---"]
        for p in properties { lines.append(contentsOf: renderProperty(p)) }
        lines.append("---")
        if body.isEmpty { return lines.joined(separator: "\n") + "\n" }
        return lines.joined(separator: "\n") + "\n\n" + body + "\n"
    }

    static func renderProperty(_ p: Property) -> [String] {
        switch p.value {
        case .string(let s): return ["\(p.key): \(yamlScalar(s))"]
        case .number(let n):
            let v = n.rounded() == n ? String(Int(n)) : String(n)
            return ["\(p.key): \(v)"]
        case .bool(let b): return ["\(p.key): \(b ? "true" : "false")"]
        case .list(let items):
            if items.isEmpty { return ["\(p.key): []"] }
            return ["\(p.key):"] + items.map { "  - \(yamlScalar($0))" }
        }
    }

    static func yamlScalar(_ s: String) -> String {
        if s.isEmpty { return "\"\"" }
        let special = s.hasPrefix(" ") || s.hasSuffix(" ")
            || s.contains(":") || s.contains("#") || s.contains("\n")
            || s.contains("{") || s.contains("}") || s.contains("[") || s.contains("]")
            || s.contains(",") || s.contains("&") || s.contains("*") || s.contains("!")
            || s.contains("%") || s.contains("@") || s.contains("`")
            || s.contains("\"") || s.contains("'")
            || s.hasPrefix("-") || s.hasPrefix("?") || s.hasPrefix("|") || s.hasPrefix(">")
        let looksBool = ["true", "false", "yes", "no", "on", "off", "null", "~"].contains(s.lowercased())
        let looksNumber = Double(s) != nil
        guard special || looksBool || looksNumber else { return s }
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    // MARK: - Extract

    /// Default filename (no extension) when the selection starts with a heading; otherwise nil.
    /// Leading blank lines are skipped; the heading's visible text is used, after inline markup
    /// is stripped, and made safe as a filename.
    public static func defaultName(forSelection text: String) -> String? {
        let ns = text as NSString
        var loc = 0
        while loc < ns.length {
            let lr = ns.lineRange(for: NSRange(location: loc, length: 0))
            let line = ns.substring(with: lr).trimmingCharacters(in: .newlines)
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { loc = NSMaxRange(lr); if lr.length == 0 { break }; continue }
            return headingName(t)
        }
        return nil
    }

    /// The heading section that contains `offset`: from that heading through (not including)
    /// the next heading of the same or a higher level. Nil when the caret is before the first
    /// heading, in frontmatter, or the note has no headings.
    public static func headingSection(in text: String, at offset: Int) -> (range: NSRange, name: String)? {
        let fm = Frontmatter.parse(text)
        let headings = NoteParser.parseHeadings(text, from: fm.bodyOffset)
        guard !headings.isEmpty else { return nil }
        let ns = text as NSString
        let off = min(max(offset, 0), ns.length)
        guard let current = headings.last(where: { $0.offset <= off }) else { return nil }
        let start = current.offset
        let end = headings.first(where: { $0.offset > start && $0.level <= current.level })?.offset ?? ns.length
        let length = end - start
        guard length > 0 else { return nil }
        let name = NoteNaming.fileName(fromTitle: current.text)
        guard !name.isEmpty else { return nil }
        return (NSRange(location: start, length: length), name)
    }

    /// Wikilink, embed, or empty string that replaces the extracted text.
    public static func replacement(title: String, style: AfterExtract) -> String {
        switch style {
        case .link: return "[[\(title)]]"
        case .embed: return "![[\(title)]]"
        case .none: return ""
        }
    }

    /// Visible title used in a wikilink to `path`. Uses the path (without `.md`) when the
    /// basename would be ambiguous.
    public static func displayTitle(path: String, clash: Bool) -> String {
        let noExt = path.lowercased().hasSuffix(".md") ? String(path.dropLast(3)) : path
        return clash ? noExt : (noExt as NSString).lastPathComponent
    }

    /// Folder a new extracted note should be created in.
    public static func folder(forCurrent path: String?, location: NewLocation) -> String {
        switch location {
        case .vaultRoot: return ""
        case .sameFolder: return path.map { ($0 as NSString).deletingLastPathComponent } ?? ""
        }
    }

    /// Vault-relative path for a typed name. A name with slashes is taken as a path from the
    /// vault root; otherwise it is placed in `folder`. The `.md` extension is added when missing.
    public static func path(named raw: String, folder: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.lowercased().hasSuffix(".md") { name = String(name.dropLast(3)) }
        name = name.replacingOccurrences(of: ":", with: "-")
        while name.hasPrefix(".") { name = String(name.dropFirst()) }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "Untitled" }
        var path = name.contains("/") ? name : (folder.isEmpty ? name : folder + "/" + name)
        if !path.lowercased().hasSuffix(".md") { path += ".md" }
        return path
    }

    /// Add " 2", " 3", … when `occupied` is already taken.
    public static func uniquePath(_ path: String, occupied: (String) -> Bool) -> String {
        guard occupied(path) else { return path }
        let base = path.lowercased().hasSuffix(".md") ? String(path.dropLast(3)) : path
        var n = 2
        var candidate = "\(base) \(n).md"
        while occupied(candidate) {
            n += 1
            candidate = "\(base) \(n).md"
        }
        return candidate
    }

    static func headingName(_ line: String) -> String? {
        var level = 0
        for ch in line { if ch == "#" { level += 1 } else { break } }
        let rest = line.dropFirst(level)
        guard (1...6).contains(level), rest.hasPrefix(" ") else { return nil }
        let name = NoteNaming.fileName(fromTitle: NoteParser.stripInline(rest.trimmingCharacters(in: .whitespaces)))
        return name.isEmpty ? nil : name
    }
}

/// Rewrite wikilinks and bare field links after a note is merged (or renamed) onto another
/// path. The rules match `Workspace.relocate`: path links always update, name links update
/// when the basename changes (and become a path when that name would be ambiguous). Headings,
/// aliases, embeds, and field keys are kept. The replacement is only the target span, so
/// `[[Note#Head|Alias]]` and `partOf:: Note` both work.
public enum WikiLinkRemap {
    public static func rewrite(
        _ text: String,
        links: [WikiLink],
        map: [String: String],
        resolve: (String) -> String?,
        nameClash: (String) -> Bool
    ) -> String? {
        func noExt(_ p: String) -> String { p.lowercased().hasSuffix(".md") ? String(p.dropLast(3)) : p }
        func title(_ p: String) -> String { (noExt(p) as NSString).lastPathComponent }
        var out = text as NSString
        var changed = false
        for l in links.sorted(by: { $0.range.location > $1.range.location }) {
            guard let target = resolve(l.target), let newPath = map[target] else { continue }
            let usesPath = l.target.contains("/")
            let newTarget: String
            if usesPath {
                newTarget = l.target.lowercased().hasSuffix(".md") ? newPath : noExt(newPath)
            } else if title(target) != title(newPath) {
                let clash = nameClash(title(newPath))
                newTarget = clash ? noExt(newPath) : title(newPath)
            } else {
                continue
            }
            guard NSMaxRange(l.range) <= out.length else { continue }
            let tStart: Int
            if l.isBare {
                tStart = l.range.location
            } else {
                let whole = out.substring(with: l.range) as NSString
                let open = whole.range(of: "[[")
                guard open.location != NSNotFound else { continue }
                tStart = l.range.location + NSMaxRange(open)
            }
            let rawTarget = out.substring(from: tStart) as NSString
            let tLen = (l.target as NSString).length
            guard tLen <= rawTarget.length, rawTarget.substring(to: tLen) == l.target else { continue }
            out = out.replacingCharacters(in: NSRange(location: tStart, length: tLen), with: newTarget) as NSString
            changed = true
        }
        return changed ? out as String : nil
    }
}
