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
    public var title: String { name }
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
    public var folders: Set<String> = []
    public private(set) var namesIndex: [String: [String]] = [:]
    public private(set) var pathIndex: [String: String] = [:]
    public private(set) var attachmentNames: [String: [String]] = [:]
    public private(set) var backlinks: [String: Set<String>] = [:]
    public private(set) var tags: [String: Set<String>] = [:]
    public private(set) var unresolved: [String: Set<String>] = [:]
    public private(set) var tree: FileNode = FileNode(name: "", path: "", isFolder: true, children: [])

    public init(root: URL) { self.root = root }

    public var sortedNotePaths: [String] { notes.keys.sorted() }

    // MARK: Resolution

    public func resolve(_ rawTarget: String, from source: String? = nil) -> String? {
        var target = rawTarget.trimmingCharacters(in: .whitespaces)
        if target.isEmpty { return source }
        target = target.removingPercentEncoding ?? target
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
        for s in sources.sorted() {
            guard let note = notes[s] else { continue }
            let lines = note.content.components(separatedBy: "\n")
            var found = false
            for (i, line) in lines.enumerated() where line.contains("[[") {
                for l in NoteParser.parseWikiLinks(line) where resolve(l.target, from: s) == path {
                    out.append(Backlink(source: s, line: i, context: line.trimmingCharacters(in: .whitespaces)))
                    found = true
                    break
                }
            }
            if !found { out.append(Backlink(source: s, line: 0, context: "")) }
        }
        return out
    }

    /// Notes mentioning this note's name in plain text without linking to it.
    public func unlinkedMentions(of path: String, limit: Int = 50) -> [Backlink] {
        guard let note = notes[path], note.name.count >= 3 else { return [] }
        let needle = note.name.lowercased()
        let linked = backlinks[path] ?? []
        var out: [Backlink] = []
        for (p, n) in notes where p != path && !linked.contains(p) && n.lowered.contains(needle) {
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
        for rel in paths {
            let url = root.appendingPathComponent(rel)
            var isDir: ObjCBool = false
            let exists = fm.fileExists(atPath: url.path, isDirectory: &isDir)
            if !exists {
                notes[rel] = nil; attachments[rel] = nil
                if folders.contains(rel) {
                    folders = folders.filter { $0 != rel && !$0.hasPrefix(rel + "/") }
                    notes = notes.filter { !$0.key.hasPrefix(rel + "/") }
                    attachments = attachments.filter { !$0.key.hasPrefix(rel + "/") }
                }
                continue
            }
            if (rel as NSString).lastPathComponent.hasPrefix(".") || rel.split(separator: "/").contains(where: { $0.hasPrefix(".") }) { continue }
            if isDir.boolValue {
                if !folders.contains(rel) { // new folder: scan it
                    let sub = VaultSnapshot.scan(root: url)
                    folders.insert(rel)
                    for f in sub.folders { folders.insert(rel + "/" + f) }
                    for (p, n) in sub.notes {
                        var n2 = n; n2.path = rel + "/" + p; n2.folder = (n2.path as NSString).deletingLastPathComponent
                        notes[n2.path] = n2
                    }
                    for (p, d) in sub.attachments { attachments[rel + "/" + p] = d }
                }
                continue
            }
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            let mtime = attrs?[.modificationDate] as? Date ?? Date()
            if rel.lowercased().hasSuffix(".md") {
                if let r = VaultSnapshot.makeRecord(rel: rel, url: url, mtime: mtime, ctime: attrs?[.creationDate] as? Date ?? mtime, size: attrs?[.size] as? Int ?? 0) {
                    notes[rel] = r
                }
            } else {
                attachments[rel] = mtime
            }
            var parent = (rel as NSString).deletingLastPathComponent
            while !parent.isEmpty && !folders.contains(parent) { folders.insert(parent); parent = (parent as NSString).deletingLastPathComponent }
        }
        rebuildDerived()
    }

    /// Update one note from in-memory content (after Onyx saves it).
    public mutating func update(path: String, content: String) {
        let old = notes[path]
        notes[path] = VaultSnapshot.makeRecord(rel: path, content: content, mtime: Date(), ctime: old?.ctime ?? Date(), size: content.utf8.count)
        rebuildDerived()
    }

    public mutating func rebuildDerived() {
        var names: [String: [String]] = [:]
        var paths: [String: String] = [:]
        for p in notes.keys {
            let lower = p.lowercased()
            paths[String(lower.dropLast(3))] = p
            names[((lower as NSString).lastPathComponent as NSString).deletingPathExtension, default: []].append(p)
        }
        for (p, n) in notes { for a in n.aliases { _ = a; _ = p } }
        var att: [String: [String]] = [:]
        for p in attachments.keys {
            att[(p.lowercased() as NSString).lastPathComponent, default: []].append(p)
            att[p.lowercased(), default: []].append(p)
        }
        namesIndex = names; pathIndex = paths; attachmentNames = att
        var bl: [String: Set<String>] = [:]
        var unres: [String: Set<String>] = [:]
        var tg: [String: Set<String>] = [:]
        for (p, n) in notes {
            for l in n.summary.links {
                if let t = resolve(l.target, from: p) { if t != p { bl[t, default: []].insert(p) } }
                else if !l.target.isEmpty { unres[l.target, default: []].insert(p) }
            }
            for m in n.summary.markdownLinks {
                let rel = ((n.folder as NSString).appendingPathComponent(m) as NSString).standardizingPath
                if notes[rel] != nil { bl[rel, default: []].insert(p) }
                else if let t = resolve(m, from: p) { bl[t, default: []].insert(p) }
            }
            for t in n.summary.tags { tg[t, default: []].insert(p) }
        }
        backlinks = bl; unresolved = unres; tags = tg
        tree = buildTree()
    }

    func buildTree() -> FileNode {
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
        var hits: [SearchHit] = []
        for (p, n) in notes {
            let lp = p.lowercased()
            if !pathFilters.allSatisfy({ lp.contains($0) }) { continue }
            if !fileFilters.allSatisfy({ n.name.lowercased().contains($0) }) { continue }
            if !tagFilters.allSatisfy({ tf in n.summary.tags.contains { $0.lowercased() == tf || $0.lowercased().hasPrefix(tf + "/") } }) { continue }
            if !terms.allSatisfy({ n.lowered.contains($0) || n.name.lowercased().contains($0) }) { continue }
            var score = 0
            let lname = n.name.lowercased()
            for t in terms {
                if lname == t { score += 100 } else if lname.contains(t) { score += 40 }
                score += min(20, n.lowered.components(separatedBy: t).count - 1)
            }
            var snippets: [String] = []
            if let first = terms.first {
                for line in n.content.split(separator: "\n", omittingEmptySubsequences: true) where line.lowercased().contains(first) {
                    snippets.append(snippet(String(line), around: first))
                    if snippets.count >= 3 { break }
                }
            }
            hits.append(SearchHit(path: p, name: n.name, score: score, snippets: snippets))
        }
        hits.sort { $0.score == $1.score ? $0.path < $1.path : $0.score > $1.score }
        return Array(hits.prefix(limit))
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
