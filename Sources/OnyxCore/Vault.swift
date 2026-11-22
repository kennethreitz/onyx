import Foundation

public struct NoteRecord: Sendable {
    public var path: String          // vault-relative, e.g. "Knowledge/Tarot/Tarot.md"
    public var name: String          // basename without extension
    public var folder: String        // vault-relative folder ("" for root)
    public var mtime: Date
    public var ctime: Date
    public var size: Int
    public var content: String
    public var lowered: String
    public var summary: NoteSummary

    public var aliases: [String] {
        (summary.frontmatter["aliases"] ?? summary.frontmatter["alias"])?.strings ?? []
    }
    /// The first H1 if present, else the file name.
    public var title: String { summary.headings.first(where: { $0.level == 1 })?.text ?? name }
}

public struct FileNode: Identifiable, Hashable, Sendable {
    public var id: String { path.isEmpty ? "/" : path }
    public var name: String
    public var path: String
    public var isFolder: Bool
    public var children: [FileNode]?
    public var folderNote: String?
    public var isNote: Bool { !isFolder && path.lowercased().hasSuffix(".md") }
    public var displayName: String { isNote ? String(name.dropLast(3)) : name }
    public init(name: String, path: String, isFolder: Bool, children: [FileNode]? = nil, folderNote: String? = nil) {
        self.name = name; self.path = path; self.isFolder = isFolder; self.children = children; self.folderNote = folderNote
    }
}

public struct Backlink: Hashable, Sendable {
    public var source: String
    public var line: Int
    public var context: String
}

public struct SearchHit: Identifiable, Sendable {
    public var id: String { path }
    public var path: String
    public var name: String
    public var score: Int
    public var snippets: [String]
}

/// An immutable snapshot of everything Onyx knows about a vault.
public struct VaultSnapshot: Sendable {
    public var root: URL
    public var notes: [String: NoteRecord] = [:]
    public var attachments: [String: Date] = [:]
    /// Obsidian canvases (also listed in `attachments`): what each one links to.
    public var canvases: [String: CanvasSummary] = [:]
    /// Obsidian Bases (also listed in `attachments`): the raw YAML, re-parsed when opened.
    public var bases: [String: String] = [:]
    /// Resolved outgoing links of each canvas (file nodes and [[links]] in its cards).
    public private(set) var canvasLinks: [String: [String]] = [:]
    public var folders: Set<String> = []
    public private(set) var namesIndex: [String: [String]] = [:]
    public private(set) var pathIndex: [String: String] = [:]
    public private(set) var attachmentNames: [String: [String]] = [:]
    public private(set) var backlinks: [String: Set<String>] = [:]
    public private(set) var tags: [String: Set<String>] = [:]
    public private(set) var unresolved: [String: Set<String>] = [:]
    /// Field relationships keyed by normalized field kind: source -> kind -> targets.
    public private(set) var relationsOut: [String: [String: Set<String>]] = [:]
    /// Reverse index: target -> kind -> sources.
    public private(set) var relationsIn: [String: [String: Set<String>]] = [:]
    public private(set) var tree: FileNode = FileNode(name: "", path: "", isFolder: true, children: [])

    public init(root: URL) { self.root = root }

    public var sortedNotePaths: [String] { notes.keys.sorted() }

    // MARK: Resolution

    public func resolve(_ rawTarget: String, from source: String? = nil) -> String? {
        var target = rawTarget.trimmingCharacters(in: .whitespaces)
        if target.isEmpty { return source }
        if target.utf8.contains(UInt8(ascii: "%")) { target = target.removingPercentEncoding ?? target }
        var lower = target.lowercased()
        if lower.hasPrefix("/") { lower.removeFirst() }
        let noExt = lower.hasSuffix(".md") ? String(lower.dropLast(3)) : lower
        if let p = pathIndex[noExt] { return p }
        // attachments by exact path
        if let p = attachmentNames[lower]?.first(where: { $0.lowercased() == lower }) { return p }
        let last = (noExt as NSString).lastPathComponent
        var candidates = namesIndex[last] ?? []
        if candidates.isEmpty {
            let lastFull = (lower as NSString).lastPathComponent
            candidates = attachmentNames[lastFull] ?? []
        }
        if noExt.contains("/") {
            let suffixMatches = candidates.filter { $0.lowercased().hasSuffix(noExt + ".md") || $0.lowercased().hasSuffix(lower) }
            if !suffixMatches.isEmpty { candidates = suffixMatches }
        }
        guard !candidates.isEmpty else { return nil }
        if candidates.count == 1 { return candidates[0] }
        if let src = source {
            let folder = (src as NSString).deletingLastPathComponent
            if let same = candidates.first(where: { ($0 as NSString).deletingLastPathComponent == folder }) { return same }
        }
        return candidates.min { a, b in a.count == b.count ? a < b : a.count < b.count }
    }

    public func isAttachment(_ path: String) -> Bool { attachments[path] != nil }

    public func backlinks(to path: String) -> [Backlink] {
        guard let sources = backlinks[path] else { return [] }
        var out: [Backlink] = []
        // A link can only resolve here if its target, lowercased, contains this file's name
        // (or is percent-encoded), so lines without either are skipped unparsed.
        let needle = ((path as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased()
        for s in sources.sorted() {
            if canvases[s] != nil { out.append(Backlink(source: s, line: 0, context: "Canvas")); continue }
            guard let note = notes[s] else { continue }
            var found = false
            let pct = note.content.utf8.contains(UInt8(ascii: "%"))
            var lines: [String]? = nil
            if pct || needle.isEmpty || ByteSearch.count(needle, in: note.lowered, cap: 1) > 0 {
                var i = 0
                for raw in note.content.utf8.split(separator: 10, omittingEmptySubsequences: false) {
                    defer { i += 1 }
                    guard raw.contains(UInt8(ascii: "[")) else { continue }
                    let line = String(Substring(raw))
                    guard line.contains("[["), pct || needle.isEmpty || line.lowercased().contains(needle) else { continue }
                    if NoteParser.parseWikiLinks(line).contains(where: { resolve($0.target, from: s) == path }) {
                        out.append(Backlink(source: s, line: i, context: line.trimmingCharacters(in: .whitespaces)))   // every linking line
                        found = true
                    }
                }
            }
            if !found, let l = note.summary.links.first(where: { $0.isBare && resolve($0.target, from: s) == path }) {
                let prefix = (note.content as NSString).substring(to: min(l.range.location, (note.content as NSString).length))
                let i = prefix.reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
                if lines == nil { lines = note.content.components(separatedBy: "\n") }
                out.append(Backlink(source: s, line: i, context: i < lines!.count ? lines![i].trimmingCharacters(in: .whitespaces) : ""))
                found = true
            }
            if !found { out.append(Backlink(source: s, line: 0, context: "")) }
        }
        return out
    }

    /// Every linking line per source (up to `perSource`), for the backlinks under a note.
    /// Field links count too (`partOf:: Knowledge`); frontmatter-only links show no context.
    public func linkedMentions(to path: String, perSource: Int = 3) -> [(source: String, lines: [Backlink])] {
        guard let sources = backlinks[path] else { return [] }
        var out: [(String, [Backlink])] = []
        for s in sources.sorted(by: { (notes[$0]?.name ?? $0).localizedStandardCompare(notes[$1]?.name ?? $1) == .orderedAscending }) {
            if canvases[s] != nil { out.append((s, [Backlink(source: s, line: 0, context: "Canvas")])); continue }
            guard let note = notes[s] else { continue }
            let ns = note.content as NSString
            var lineStarts: [Int] = [0]
            for (i, ch) in note.content.utf16.enumerated() where ch == 10 { lineStarts.append(i + 1) }
            func lineOf(_ loc: Int) -> Int { var lo = 0, hi = lineStarts.count - 1; while lo < hi { let m = (lo + hi + 1) / 2; if lineStarts[m] <= loc { lo = m } else { hi = m - 1 } }; return lo }
            var seen = Set<Int>(), items: [Backlink] = []
            for l in note.summary.links.sorted(by: { $0.range.location < $1.range.location }) where resolve(l.target, from: s) == path {
                let i = lineOf(l.range.location)
                guard !seen.contains(i), l.range.location >= note.summary.frontmatter.bodyOffset else { continue }
                seen.insert(i)
                let end = i + 1 < lineStarts.count ? lineStarts[i + 1] : ns.length
                let text = ns.substring(with: NSRange(location: lineStarts[i], length: end - lineStarts[i])).trimmingCharacters(in: .whitespacesAndNewlines)
                items.append(Backlink(source: s, line: i, context: text))
                if items.count >= perSource { break }
            }
            out.append((s, items))
        }
        return out
    }

    /// Notes mentioning this note's name in plain text without linking to it.
    public func unlinkedMentions(of path: String, limit: Int = 50) -> [Backlink] {
        guard let note = notes[path], note.name.count >= 3 else { return [] }
        let needle = note.name.lowercased()
        let linked = backlinks[path] ?? []
        var out: [Backlink] = []
        for (p, n) in notes where p != path && !linked.contains(p) && ByteSearch.count(needle, in: n.lowered, cap: 1) > 0 {
            let lines = n.content.components(separatedBy: "\n")
            if let i = lines.firstIndex(where: { $0.lowercased().contains(needle) }) {
                out.append(Backlink(source: p, line: i, context: lines[i].trimmingCharacters(in: .whitespaces)))
            }
            if out.count >= limit { break }
        }
        return out.sorted { $0.source < $1.source }
    }

    // MARK: Building

    public static func scan(root: URL, ignore: [String] = []) -> VaultSnapshot {
        var snap = VaultSnapshot(root: root)
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .creationDateKey, .fileSizeKey]
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return snap }
        let rootPath = root.standardizedFileURL.path
        var mdURLs: [(String, URL, Date, Date, Int)] = []
        for case let url as URL in en {
            let full = url.standardizedFileURL.path
            guard full.hasPrefix(rootPath) else { continue }
            var rel = String(full.dropFirst(rootPath.count))
            if rel.hasPrefix("/") { rel.removeFirst() }
            if ignore.contains(where: { !$0.isEmpty && rel.hasPrefix($0) }) { en.skipDescendants(); continue }
            let v = try? url.resourceValues(forKeys: Set(keys))
            if v?.isDirectory == true { snap.folders.insert(rel); continue }
            let mtime = v?.contentModificationDate ?? Date()
            if rel.lowercased().hasSuffix(".md") {
                mdURLs.append((rel, url, mtime, v?.creationDate ?? mtime, v?.fileSize ?? 0))
            } else {
                snap.attachments[rel] = mtime
                if rel.isCanvasPath, let d = try? Data(contentsOf: url) { snap.canvases[rel] = CanvasFile.summarize(String(decoding: d, as: UTF8.self)) }
                if rel.isBasePath, let d = try? Data(contentsOf: url) { snap.bases[rel] = String(decoding: d, as: UTF8.self) }
            }
        }
        // Read + parse concurrently.
        var records = [NoteRecord?](repeating: nil, count: mdURLs.count)
        records.withUnsafeMutableBufferPointer { buf in
            let base = buf.baseAddress!
            DispatchQueue.concurrentPerform(iterations: mdURLs.count) { i in
                let (rel, url, mtime, ctime, size) = mdURLs[i]
                base[i] = makeRecord(rel: rel, url: url, mtime: mtime, ctime: ctime, size: size)
            }
        }
        for r in records { if let r { snap.notes[r.path] = r } }
        snap.rebuildDerived()
        return snap
    }

    public static func makeRecord(rel: String, url: URL, mtime: Date, ctime: Date, size: Int) -> NoteRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let content = String(decoding: data, as: UTF8.self)
        return makeRecord(rel: rel, content: content, mtime: mtime, ctime: ctime, size: size)
    }

    public static func makeRecord(rel: String, content: String, mtime: Date = Date(), ctime: Date = Date(), size: Int = 0) -> NoteRecord {
        let name = String(((rel as NSString).lastPathComponent as NSString).deletingPathExtension)
        return NoteRecord(path: rel, name: name, folder: (rel as NSString).deletingLastPathComponent,
                          mtime: mtime, ctime: ctime, size: size, content: content,
                          lowered: content.lowercased(), summary: NoteParser.summarize(content))
    }

    /// Re-read a set of changed vault-relative paths from disk.
    public mutating func refresh(paths: [String]) {
        let fm = FileManager.default
        // Edits to notes that already exist leave every path, name and folder alone, so only
        // their own links, tags and relations need redoing. Anything else rebuilds everything.
        var structural = false
        var edits: [(NoteRecord, NoteRecord)] = []
        for rel in paths {
            let url = root.appendingPathComponent(rel)
            var isDir: ObjCBool = false
            let exists = fm.fileExists(atPath: url.path, isDirectory: &isDir)
            if !exists {
                if notes[rel] != nil || attachments[rel] != nil || canvases[rel] != nil || bases[rel] != nil || folders.contains(rel) { structural = true }
                notes[rel] = nil; attachments[rel] = nil; canvases[rel] = nil; bases[rel] = nil
                if folders.contains(rel) {
                    folders = folders.filter { $0 != rel && !$0.hasPrefix(rel + "/") }
                    notes = notes.filter { !$0.key.hasPrefix(rel + "/") }
                    attachments = attachments.filter { !$0.key.hasPrefix(rel + "/") }
                    canvases = canvases.filter { !$0.key.hasPrefix(rel + "/") }
                    bases = bases.filter { !$0.key.hasPrefix(rel + "/") }
                }
                continue
            }
            if (rel as NSString).lastPathComponent.hasPrefix(".") || rel.split(separator: "/").contains(where: { $0.hasPrefix(".") }) { continue }
            if isDir.boolValue {
                if !folders.contains(rel) { // new folder: scan it
                    structural = true
                    let sub = VaultSnapshot.scan(root: url)
                    folders.insert(rel)
                    for f in sub.folders { folders.insert(rel + "/" + f) }
                    for (p, n) in sub.notes {
                        var n2 = n; n2.path = rel + "/" + p; n2.folder = (n2.path as NSString).deletingLastPathComponent
                        notes[n2.path] = n2
                    }
                    for (p, d) in sub.attachments { attachments[rel + "/" + p] = d }
                    for (p, c) in sub.canvases { canvases[rel + "/" + p] = c }
                    for (p, b) in sub.bases { bases[rel + "/" + p] = b }
                }
                continue
            }
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            let mtime = attrs?[.modificationDate] as? Date ?? Date()
            if rel.lowercased().hasSuffix(".md") {
                if let r = VaultSnapshot.makeRecord(rel: rel, url: url, mtime: mtime, ctime: attrs?[.creationDate] as? Date ?? mtime, size: attrs?[.size] as? Int ?? 0) {
                    if let old = notes[rel] { edits.append((old, r)) } else { structural = true }
                    notes[rel] = r
                }
            } else {
                if attachments[rel] == nil || rel.isCanvasPath { structural = true }
                attachments[rel] = mtime
                if rel.isCanvasPath, let d = try? Data(contentsOf: url) { canvases[rel] = CanvasFile.summarize(String(decoding: d, as: UTF8.self)) }
                if rel.isBasePath, let d = try? Data(contentsOf: url) { bases[rel] = String(decoding: d, as: UTF8.self) }
            }
            var parent = (rel as NSString).deletingLastPathComponent
            while !parent.isEmpty && !folders.contains(parent) { structural = true; folders.insert(parent); parent = (parent as NSString).deletingLastPathComponent }
        }
        if structural { rebuildDerived(); return }
        for (old, new) in edits { reindex(old: old, new: new) }
    }

    /// Update one note from in-memory content (after Onyx saves it).
    public mutating func update(path: String, content: String) {
        if path.isCanvasPath {
            attachments[path] = Date()
            canvases[path] = CanvasFile.summarize(content)
            rebuildDerived()
            return
        }
        if path.isBasePath {
            attachments[path] = Date()
            bases[path] = content
            rebuildDerived()
            return
        }
        let old = notes[path]
        let new = VaultSnapshot.makeRecord(rel: path, content: content, mtime: Date(), ctime: old?.ctime ?? Date(), size: content.utf8.count)
        notes[path] = new
        if let old { reindex(old: old, new: new) } else { rebuildDerived() }
    }

    /// What one note adds to the derived indexes: who it links to, what it can't resolve,
    /// its tags, and its field relationships (kind -> targets).
    struct Contribution {
        var linked = Set<String>(), unresolved = Set<String>(), tags = Set<String>()
        var relations: [String: Set<String>] = [:]
    }

    func contribution(_ n: NoteRecord) -> Contribution {
        var c = Contribution()
        let p = n.path
        for l in n.summary.links {
            if let t = resolve(l.target, from: p) {
                if t != p { c.linked.insert(t) }
                if let key = l.fieldKey, t != p { c.relations[InlineField.kind(key), default: []].insert(t) }
            }
            else if !l.target.isEmpty { c.unresolved.insert(l.target) }
        }
        for m in n.summary.markdownLinks {
            let rel = ((n.folder as NSString).appendingPathComponent(m) as NSString).standardizingPath
            if notes[rel] != nil { c.linked.insert(rel) }
            else if let t = resolve(m, from: p) { c.linked.insert(t) }
        }
        c.tags = Set(n.summary.tags)
        return c
    }

    /// Swap one existing note's contribution for its new content without touching the rest
    /// of the vault (same result as `rebuildDerived`, for a note whose path set is unchanged).
    mutating func reindex(old: NoteRecord, new: NoteRecord) {
        let p = new.path
        let a = contribution(old), b = contribution(new)
        func swap(_ index: inout [String: Set<String>], _ before: Set<String>, _ after: Set<String>) {
            for k in before.subtracting(after) {
                index[k]?.remove(p)
                if index[k]?.isEmpty == true { index[k] = nil }
            }
            for k in after.subtracting(before) { index[k, default: []].insert(p) }
        }
        swap(&backlinks, a.linked, b.linked)
        swap(&unresolved, a.unresolved, b.unresolved)
        swap(&tags, a.tags, b.tags)
        if a.relations != b.relations {
            for (k, ts) in a.relations { for t in ts where b.relations[k]?.contains(t) != true {
                relationsIn[t]?[k]?.remove(p)
                if relationsIn[t]?[k]?.isEmpty == true { relationsIn[t]?[k] = nil }
                if relationsIn[t]?.isEmpty == true { relationsIn[t] = nil }
            } }
            for (k, ts) in b.relations { for t in ts { relationsIn[t, default: [:]][k, default: []].insert(p) } }
            relationsOut[p] = b.relations.isEmpty ? nil : b.relations
        }
    }

    public mutating func rebuildDerived() {
        var names: [String: [String]] = [:]
        var paths: [String: String] = [:]
        for p in notes.keys {
            let lower = p.lowercased()
            paths[String(lower.dropLast(3))] = p
            names[((lower as NSString).lastPathComponent as NSString).deletingPathExtension, default: []].append(p)
        }
        var att: [String: [String]] = [:]
        for p in attachments.keys {
            att[(p.lowercased() as NSString).lastPathComponent, default: []].append(p)
            att[p.lowercased(), default: []].append(p)
        }
        namesIndex = names; pathIndex = paths; attachmentNames = att
        var bl: [String: Set<String>] = [:]
        var unres: [String: Set<String>] = [:]
        var tg: [String: Set<String>] = [:]
        var rout: [String: [String: Set<String>]] = [:], rin: [String: [String: Set<String>]] = [:]
        // Resolving every link is the expensive part; do it in parallel, then merge.
        let all = Array(notes.values)
        var parts = [Contribution](repeating: Contribution(), count: all.count)
        let me = self
        parts.withUnsafeMutableBufferPointer { buf in
            let base = buf.baseAddress!
            DispatchQueue.concurrentPerform(iterations: all.count) { i in base[i] = me.contribution(all[i]) }
        }
        for (i, n) in all.enumerated() {
            let p = n.path, c = parts[i]
            for t in c.linked { bl[t, default: []].insert(p) }
            for t in c.unresolved { unres[t, default: []].insert(p) }
            for t in c.tags { tg[t, default: []].insert(p) }
            if !c.relations.isEmpty { rout[p] = c.relations }
            for (k, ts) in c.relations { for t in ts { rin[t, default: [:]][k, default: []].insert(p) } }
        }
        var cl: [String: [String]] = [:]
        for (p, c) in canvases {
            var seen = Set<String>(), out: [String] = []
            for f in c.files + c.links {
                guard let t = resolve(f, from: p), t != p, seen.insert(t).inserted else { continue }
                out.append(t)
                bl[t, default: []].insert(p)
            }
            cl[p] = out
        }
        canvasLinks = cl
        backlinks = bl; unresolved = unres; tags = tg; relationsOut = rout; relationsIn = rin
        tree = buildTree()
    }

    public func buildTree() -> FileNode {
        final class Box { var name: String; var path: String; var folders: [String: Box] = [:]; var files: [String] = []
            init(_ n: String, _ p: String) { name = n; path = p } }
        let root = Box("", "")
        func box(for folder: String) -> Box {
            if folder.isEmpty || folder == "." { return root }
            var cur = root
            var acc = ""
            for comp in folder.split(separator: "/") {
                acc = acc.isEmpty ? String(comp) : acc + "/" + comp
                if let b = cur.folders[String(comp)] { cur = b } else { let b = Box(String(comp), acc); cur.folders[String(comp)] = b; cur = b }
            }
            return cur
        }
        for f in folders { _ = box(for: f) }
        for p in notes.keys { box(for: (p as NSString).deletingLastPathComponent).files.append(p) }
        for p in attachments.keys { box(for: (p as NSString).deletingLastPathComponent).files.append(p) }
        func convert(_ b: Box) -> FileNode {
            let folderNotePath = b.path.isEmpty ? nil : b.path + "/" + b.name + ".md"
            let hasFolderNote = folderNotePath.map { notes[$0] != nil } ?? false
            let subs = b.folders.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.map(convert)
            let files = b.files.filter { !(hasFolderNote && $0 == folderNotePath) }
                .sorted { ($0 as NSString).lastPathComponent.localizedStandardCompare(($1 as NSString).lastPathComponent) == .orderedAscending }
                .map { FileNode(name: ($0 as NSString).lastPathComponent, path: $0, isFolder: false, children: nil, folderNote: nil) }
            return FileNode(name: b.name, path: b.path, isFolder: true, children: subs + files, folderNote: hasFolderNote ? folderNotePath : nil)
        }
        return convert(root)
    }

    // MARK: Relationships

    public func parents(of path: String) -> [String] { (relationsOut[path]?["partof"] ?? []).sorted() }
    public func parts(of path: String) -> [String] { (relationsIn[path]?["partof"] ?? []).sorted() }
    /// `related::` is symmetric for display: outgoing and incoming collapse to one list.
    public func related(to path: String) -> [String] {
        let ks = ["related", "relatesto"]
        var r = Set<String>()
        for k in ks { r.formUnion(relationsOut[path]?[k] ?? []); r.formUnion(relationsIn[path]?[k] ?? []) }
        return r.subtracting([path]).sorted()
    }
    public func siblings(of path: String) -> [String] {
        Set(parents(of: path).flatMap(parts(of:))).subtracting([path]).sorted()
    }

    // MARK: Search

    public func search(_ query: String, limit: Int = 200) -> [SearchHit] {
        var terms: [String] = []
        var tagFilters: [String] = []
        var pathFilters: [String] = []
        var fileFilters: [String] = []
        // support "quoted phrases"
        let scanner = query.trimmingCharacters(in: .whitespaces)
        var cur = ""; var inQuote = false
        var tokens: [String] = []
        for ch in scanner {
            if ch == "\"" { inQuote.toggle(); if !inQuote && !cur.isEmpty { tokens.append(cur); cur = "" }; continue }
            if ch == " " && !inQuote { if !cur.isEmpty { tokens.append(cur); cur = "" }; continue }
            cur.append(ch)
        }
        if !cur.isEmpty { tokens.append(cur) }
        for t in tokens {
            let l = t.lowercased()
            if l.hasPrefix("tag:") { tagFilters.append(String(l.dropFirst(4)).trimmingCharacters(in: CharacterSet(charactersIn: "#"))) }
            else if l.hasPrefix("#") && l.count > 1 { tagFilters.append(String(l.dropFirst())) }
            else if l.hasPrefix("path:") { pathFilters.append(String(l.dropFirst(5))) }
            else if l.hasPrefix("file:") { fileFilters.append(String(l.dropFirst(5))) }
            else { terms.append(l) }
        }
        if terms.isEmpty && tagFilters.isEmpty && pathFilters.isEmpty && fileFilters.isEmpty { return [] }
        // Score every note in parallel (byte search on the pre-lowered text), then build
        // snippets only for the hits that make the cut.
        let all = Array(notes.values)
        var scored = [Int?](repeating: nil, count: all.count)
        scored.withUnsafeMutableBufferPointer { buf in
            let base = buf.baseAddress!
            DispatchQueue.concurrentPerform(iterations: all.count) { i in
                let n = all[i]
                let lp = n.path.lowercased()
                if !pathFilters.allSatisfy({ lp.contains($0) }) { return }
                let lname = n.name.lowercased()
                if !fileFilters.allSatisfy({ lname.contains($0) }) { return }
                if !tagFilters.allSatisfy({ tf in n.summary.tags.contains { $0.lowercased() == tf || $0.lowercased().hasPrefix(tf + "/") } }) { return }
                var score = 0
                for t in terms {
                    let count = ByteSearch.count(t, in: n.lowered, cap: 20)
                    if count == 0 && !lname.contains(t) { return }
                    if lname == t { score += 100 } else if lname.contains(t) { score += 40 }
                    score += count
                }
                base[i] = score
            }
        }
        var ranked: [(Int, NoteRecord)] = []
        for (i, s) in scored.enumerated() { if let s { ranked.append((s, all[i])) } }
        ranked.sort { $0.0 == $1.0 ? $0.1.path < $1.1.path : $0.0 > $1.0 }
        return ranked.prefix(limit).map { score, n in
            var snippets: [String] = []
            if let first = terms.first {
                for line in n.content.split(separator: "\n", omittingEmptySubsequences: true) where line.lowercased().contains(first) {
                    snippets.append(snippet(String(line), around: first))
                    if snippets.count >= 3 { break }
                }
            }
            return SearchHit(path: n.path, name: n.name, score: score, snippets: snippets)
        }
    }

    func snippet(_ line: String, around term: String) -> String {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.count > 140, let r = t.lowercased().range(of: term) else { return t }
        let idx = t.distance(from: t.startIndex, to: r.lowerBound)
        let start = max(0, idx - 50)
        let s = t.index(t.startIndex, offsetBy: start)
        let e = t.index(s, offsetBy: min(140, t.distance(from: s, to: t.endIndex)))
        return (start > 0 ? "…" : "") + String(t[s..<e]) + (e < t.endIndex ? "…" : "")
    }
}

/// Literal substring search over UTF-8 bytes (memmem). Matching UTF-8 bytes is the same as
/// matching the characters for a literal needle, and far cheaper than bridging to NSString.
enum ByteSearch {
    /// Non-overlapping occurrences of `needle` in `hay`, stopping at `cap`.
    static func count(_ needle: String, in hay: String, cap: Int) -> Int {
        var hay = hay, needle = needle
        return hay.withUTF8 { h in
            needle.withUTF8 { n in
                guard n.count > 0, h.count >= n.count, let hb = h.baseAddress, let nb = n.baseAddress else { return 0 }
                var found = 0, off = 0
                while found < cap, off + n.count <= h.count, let m = memmem(hb + off, h.count - off, nb, n.count) {
                    found += 1
                    off = hb.distance(to: m.assumingMemoryBound(to: UInt8.self)) + n.count
                }
                return found
            }
        }
    }
}
