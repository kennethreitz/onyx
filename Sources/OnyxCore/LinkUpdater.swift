import Foundation

/// What renaming or moving a file or folder does to the links pointing at it (Obsidian's
/// "Automatically update internal links"). `plan` works out every edit up front, from the vault
/// as it is before the move, so the app can ask first (`alwaysUpdateLinks` off) and then write
/// them all at once.
///
/// Rewritten: `[[name]]`, `![[name]]`, `[[name|alias]]`, `[[name#heading]]`, `![[img.png|300]]`
/// (suffixes kept), path links (`[[Folder/Note]]`, `[[/Folder/Note]]`), relative wikilinks
/// (`[[../Note]]`), frontmatter and inline-field links (`partOf: "[[X]]"`, `up:: [[X]]`, bare
/// YAML `partOf: X`), Markdown links and embeds (via `MarkdownLinks`), and canvas file cards.
/// Code blocks, inline code and anything outside the snapshot (`.obsidian`, excluded files) are
/// never touched.
public enum LinkUpdater {
    public struct Edit: Sendable, Equatable {
        public var path: String
        public var text: String
        public var links: Int
    }

    public struct Plan: Sendable {
        /// Notes, canvases and bases that move: old path → new path.
        public var noteMoves: [String: String] = [:]
        /// Everything that moves, attachments included.
        public var fileMoves: [String: String] = [:]
        /// Files whose links change, with their new text (paths as they are before the move).
        public var edits: [Edit] = []
        public var linkCount: Int { edits.reduce(0) { $0 + $1.links } }
        public var isEmpty: Bool { edits.isEmpty }
    }

    /// Old → new for `from` and, when it's a folder, everything under it.
    public static func moves(_ snap: VaultSnapshot, from: String, to dest: String) -> (notes: [String: String], files: [String: String]) {
        var notes: [String: String] = [:], files: [String: String] = [:]
        func under(_ p: String) -> String? {
            if p == from { return dest }
            if p.hasPrefix(from + "/") { return dest + String(p.dropFirst(from.count)) }
            return nil
        }
        for p in snap.notes.keys { if let n = under(p) { notes[p] = n } }
        for p in snap.canvases.keys { if let n = under(p) { notes[p] = n } }
        for p in snap.bases.keys { if let n = under(p) { notes[p] = n } }
        files = notes
        for p in snap.attachments.keys { if let n = under(p) { files[p] = n } }
        return (notes, files)
    }

    /// Every link edit a move of `from` to `dest` needs. `linkFormat` is app.json's
    /// `newLinkFormat` ("shortest", "relative", "absolute"), used when a bare-name link has to
    /// become a path because the name is no longer unique. `read` returns a canvas's text.
    public static func plan(_ snap: VaultSnapshot, from: String, to dest: String,
                            linkFormat: String = "shortest", read: (String) -> String?) -> Plan {
        var plan = Plan()
        (plan.noteMoves, plan.fileMoves) = moves(snap, from: from, to: dest)
        let fileMap = plan.fileMoves, noteMap = plan.noteMoves
        guard !fileMap.isEmpty else { return plan }
        let post = PostIndex(snap, moves: fileMap)
        // a bare link can start resolving elsewhere when something with its name moves in
        let movedNames = Set(fileMap.values.flatMap { [displayName($0).lowercased(), ($0 as NSString).lastPathComponent.lowercased()] })
        for (path, note) in snap.notes {
            var text = note.content
            var count = 0
            if let (t, n) = rewriteWikiLinks(note, path: path, snap: snap, post: post, fileMap: fileMap, noteMap: noteMap,
                                             movedNames: movedNames, linkFormat: linkFormat) {
                text = t; count += n
            }
            if let md = MarkdownLinks.rewriteCounting(text, oldNote: path, newNote: noteMap[path] ?? path,
                                                       exists: { snap.notes[$0] != nil || snap.attachments[$0] != nil },
                                                       resolveName: { snap.resolve($0, from: path) },
                                                       moved: { fileMap[$0] }) {
                text = md.text; count += md.count
            }
            if count > 0 { plan.edits.append(Edit(path: path, text: text, links: count)) }
        }
        for c in snap.canvases.keys {
            guard let old = read(c) else { continue }
            let target = { (f: String) in snap.resolve(f, from: c).flatMap { fileMap[$0] } }
            guard let new = CanvasFile.rewriteFiles(old, target) else { continue }
            let n = CanvasFile.summarize(old).files.filter { target($0) != nil }.count
            plan.edits.append(Edit(path: c, text: new, links: max(n, 1)))
        }
        plan.edits.sort { $0.path < $1.path }
        return plan
    }

    // MARK: Wikilinks

    static func isNote(_ p: String) -> Bool { p.lowercased().hasSuffix(".md") }
    static func noExt(_ p: String) -> String { isNote(p) ? String(p.dropLast(3)) : p }
    /// What a bare link names: a note without `.md`, any other file with its extension.
    static func displayName(_ p: String) -> String { (noExt(p) as NSString).lastPathComponent }

    static func rewriteWikiLinks(_ note: NoteRecord, path: String, snap: VaultSnapshot, post: PostIndex,
                                 fileMap: [String: String], noteMap: [String: String], movedNames: Set<String>,
                                 linkFormat: String) -> (String, Int)? {
        let source = noteMap[path] ?? path
        let sourceMoved = source != path
        var text = note.content as NSString
        var count = 0
        // the index already skips fenced code; inline `code` and %% comments %% are skipped here
        lazy var inline: [NSRange] = {
            let all = NSRange(location: 0, length: text.length)
            return (MarkdownLinks.codeSpan.matches(in: note.content, range: all) + MarkdownLinks.comment.matches(in: note.content, range: all)).map(\.range)
        }()
        let mayHaveInline = note.content.utf8.contains { $0 == 0x60 || $0 == 0x25 }
        for l in note.summary.links.sorted(by: { $0.range.location > $1.range.location }) {
            let tgt = l.target
            guard !tgt.isEmpty else { continue }
            if mayHaveInline, inline.contains(where: { NSIntersectionRange($0, l.range).length > 0 }) { continue }
            let bareName = !tgt.contains("/")
            let lowerTgt = tgt.lowercased()
            guard let target = snap.resolve(tgt, from: path) else { continue }
            // skip links where nothing about them moved
            let newPath = fileMap[target] ?? target
            let relative = tgt.hasPrefix("./") || tgt.hasPrefix("../")
            guard newPath != target || (sourceMoved && (bareName || relative))
                    || (bareName && (movedNames.contains(lowerTgt) || movedNames.contains(String(noExt(lowerTgt))))) else { continue }
            guard let replacement = newTarget(for: tgt, target: target, newPath: newPath, source: source,
                                              post: post, linkFormat: linkFormat), replacement != tgt else { continue }
            guard NSMaxRange(l.range) <= text.length else { continue }
            let tStart: Int
            if l.isBare { tStart = l.range.location }   // `partOf:: Knowledge` or YAML `partOf: Knowledge`
            else {
                let whole = text.substring(with: l.range) as NSString
                let open = whole.range(of: "[[")
                guard open.location != NSNotFound else { continue }
                tStart = l.range.location + NSMaxRange(open)
            }
            let tLen = (tgt as NSString).length
            guard tStart + tLen <= text.length, text.substring(with: NSRange(location: tStart, length: tLen)) == tgt else { continue }
            text = text.replacingCharacters(in: NSRange(location: tStart, length: tLen), with: replacement) as NSString
            count += 1
        }
        return count > 0 ? (text as String, count) : nil
    }

    /// The link text for `newPath`, keeping the link's style where it still works. nil = leave it.
    static func newTarget(for tgt: String, target: String, newPath: String, source: String,
                          post: PostIndex, linkFormat: String) -> String? {
        let keepExt = tgt.lowercased().hasSuffix(".md")
        func shown(_ p: String) -> String { keepExt || !isNote(p) ? p : noExt(p) }
        let dir = (source as NSString).deletingLastPathComponent
        func relativePath(dot: Bool) -> String {
            var r = MarkdownLinks.relative(from: dir, to: newPath)
            if dot && !r.hasPrefix("../") { r = "./" + r }
            return shown(r)
        }
        if tgt.hasPrefix("./") || tgt.hasPrefix("../") {
            return relativePath(dot: tgt.hasPrefix("./"))
        }
        if tgt.contains("/") {
            guard newPath != target else { return nil }
            return (tgt.hasPrefix("/") ? "/" : "") + shown(newPath)
        }
        // bare name: stays a name while that name still finds the file, else becomes a path
        var name = (shown(newPath) as NSString).lastPathComponent
        if name.lowercased() == tgt.lowercased() { name = tgt }   // keep the writer's casing
        if post.resolveBare(name, from: source) == newPath { return name }
        switch linkFormat {
        case "relative": return relativePath(dot: false)
        default: return shown(newPath)   // "absolute", and "shortest" when the name is ambiguous
        }
    }

    /// Just enough of the vault, after the move, to tell where a bare name would resolve,
    /// following `VaultSnapshot.resolve`'s rules.
    struct PostIndex {
        var notePaths: [String: String] = [:]      // lowercased path without .md → path
        var noteNames: [String: [String]] = [:]    // lowercased name without .md → paths
        var attPaths: [String: String] = [:]       // lowercased path → path
        var attNames: [String: [String]] = [:]     // lowercased file name → paths

        init(_ snap: VaultSnapshot, moves: [String: String]) {
            for p0 in snap.notes.keys {
                let p = moves[p0] ?? p0, l = p.lowercased()
                notePaths[String(l.dropLast(3))] = p
                noteNames[((l as NSString).lastPathComponent as NSString).deletingPathExtension, default: []].append(p)
            }
            for p0 in snap.attachments.keys {
                let p = moves[p0] ?? p0, l = p.lowercased()
                attPaths[l] = p
                attNames[(l as NSString).lastPathComponent, default: []].append(p)
            }
        }

        func resolveBare(_ name: String, from source: String) -> String? {
            let lower = name.lowercased()
            let ne = lower.hasSuffix(".md") ? String(lower.dropLast(3)) : lower
            if let p = notePaths[ne] { return p }
            if let p = attPaths[lower] { return p }
            var c = noteNames[ne] ?? []
            if c.isEmpty { c = attNames[lower] ?? [] }
            guard !c.isEmpty else { return nil }
            if c.count == 1 { return c[0] }
            let folder = (source as NSString).deletingLastPathComponent
            if let same = c.filter({ ($0 as NSString).deletingLastPathComponent == folder }).min() { return same }
            return c.min { a, b in a.count == b.count ? a < b : a.count < b.count }
        }
    }
}
