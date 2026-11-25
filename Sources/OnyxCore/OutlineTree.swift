import Foundation

/// How far the inspector Outline pane looks: the open note, its folder, its
/// linked and `partOf` neighbors, or the whole vault as one outline.
public enum OutlineScope: String, Sendable, CaseIterable, Identifiable, Codable {
    case note, folder, neighbors, vault
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .note: "This note"
        case .folder: "Folder"
        case .neighbors: "Linked & partOf"
        case .vault: "Whole vault"
        }
    }
}

public enum OutlineKind: String, Sendable, Hashable {
    case folder, note, heading
}

/// One node of an outline. Heading children of a note are left unloaded until
/// flatten, so a whole-vault tree is just the folder structure until a note is expanded.
public struct OutlineNode: Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: OutlineKind
    public var title: String
    public var path: String?
    public var headingIndex: Int?
    public var headingLine: Int?
    public var headingLevel: Int?
    public var children: [OutlineNode]
    /// When true, `flatten` inserts this note's heading tree (after any structural children
    /// already on the node, headings first) once the row is expanded.
    public var loadsHeadings: Bool

    public init(id: String, kind: OutlineKind, title: String, path: String? = nil,
                headingIndex: Int? = nil, headingLine: Int? = nil, headingLevel: Int? = nil,
                children: [OutlineNode] = [], loadsHeadings: Bool = false) {
        self.id = id; self.kind = kind; self.title = title; self.path = path
        self.headingIndex = headingIndex; self.headingLine = headingLine; self.headingLevel = headingLevel
        self.children = children; self.loadsHeadings = loadsHeadings
    }
}

/// A visible row in the outline list, already indented.
public struct OutlineRow: Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: OutlineKind
    public var title: String
    public var depth: Int
    public var path: String?
    public var headingIndex: Int?
    public var headingLine: Int?
    public var headingLevel: Int?
    public var expandable: Bool

    public init(id: String, kind: OutlineKind, title: String, depth: Int, path: String? = nil,
                headingIndex: Int? = nil, headingLine: Int? = nil, headingLevel: Int? = nil,
                expandable: Bool) {
        self.id = id; self.kind = kind; self.title = title; self.depth = depth; self.path = path
        self.headingIndex = headingIndex; self.headingLine = headingLine; self.headingLevel = headingLevel
        self.expandable = expandable
    }
}

/// The result of following the current heading path: which rows to expand or collapse,
/// and which manual holds remain.
public struct OutlineFollow: Equatable, Sendable {
    public var expand: Set<String>
    public var collapse: Set<String>
    public var heldOpen: Set<String>
    public var entered: Set<String>
    public init(expand: Set<String>, collapse: Set<String>, heldOpen: Set<String>, entered: Set<String>) {
        self.expand = expand; self.collapse = collapse; self.heldOpen = heldOpen; self.entered = entered
    }
}

/// Pure outline construction: nest headings, widen scope around the open note, and
/// flatten only the expanded branches so a large vault stays cheap to draw.
public enum OutlineTree {
    public static func folderId(_ path: String) -> String { "f:" + path }
    public static func noteId(_ path: String) -> String { "n:" + path }
    public static func headingId(_ path: String, index: Int, line: Int) -> String { "h:\(path)#\(index)@\(line)" }

    /// If the first heading is an H1, that text is the note's title; otherwise `fallback` (the file name).
    public static func leadingTitle(in headings: [Heading], fallback: String) -> (title: String, usedH1: Bool, heading: Heading?) {
        if let h = headings.first, h.level == 1 { return (h.text, true, h) }
        return (fallback, false, nil)
    }

    /// Headings that nest under the title row. A leading H1 is the title itself, so it is omitted.
    public static func bodyHeadings(_ headings: [Heading]) -> [Heading] {
        if headings.first?.level == 1 { return Array(headings.dropFirst()) }
        return headings
    }

    /// Last heading whose source line is at or above `line` (0-based, as in `Heading.line`).
    public static func headingIndex(at line: Double, in headings: [Heading]) -> Int? {
        let n = Int(floor(line))
        var best: Int? = nil
        for (i, h) in headings.enumerated() {
            if h.line <= n { best = i } else { break }
        }
        return best
    }

    /// The row to highlight for a reading line. A leading H1 is the note's title row, not a child.
    public static func activeId(path: String?, line: Double, headings: [Heading]) -> String? {
        guard let path else { return nil }
        if let i = headingIndex(at: line, in: headings) {
            if i == 0, headings[0].level == 1 { return noteId(path) }
            return headingId(path, index: i, line: headings[i].line)
        }
        return noteId(path)
    }

    /// Nest a flat heading list. A later, shallower heading becomes a new root; skipped
    /// levels (a `####` under a `#`) still nest under the nearest higher heading.
    public static func nestHeadings(_ headings: [Heading], path: String) -> [OutlineNode] {
        var i = 0
        func take(minLevel: Int) -> [OutlineNode] {
            var out: [OutlineNode] = []
            while i < headings.count {
                let h = headings[i]
                if h.level < minLevel { break }
                let idx = i
                i += 1
                let kids = take(minLevel: h.level + 1)
                out.append(OutlineNode(
                    id: headingId(path, index: idx, line: h.line),
                    kind: .heading, title: h.text, path: path,
                    headingIndex: idx, headingLine: h.line, headingLevel: h.level,
                    children: kids
                ))
            }
            return out
        }
        return take(minLevel: 1)
    }

    public static func headings(for path: String, currentPath: String?, currentText: String?, in snap: VaultSnapshot) -> [Heading] {
        if path == currentPath, let currentText { return NoteParser.parseHeadings(currentText) }
        return snap.notes[path]?.summary.headings ?? []
    }

    /// Structural children plus, when a note/folder-note is expanded, its body headings
    /// (a leading H1 is the title row and is not repeated).
    public static func headingChildren(of n: OutlineNode, headings: (String) -> [Heading]) -> [OutlineNode] {
        var c = n.children
        if n.loadsHeadings, let path = n.path {
            c = nestHeadings(bodyHeadings(headings(path)), path: path) + c
        }
        return c
    }

    public static func build(scope: OutlineScope, currentPath: String?, currentText: String? = nil,
                             snapshot: VaultSnapshot) -> [OutlineNode] {
        switch scope {
        case .note:
            guard let path = currentPath else { return [] }
            let hs = headings(for: path, currentPath: currentPath, currentText: currentText, in: snapshot)
            let fallback = snapshot.notes[path]?.name ?? (path as NSString).deletingPathExtension
            let lead = leadingTitle(in: hs, fallback: fallback)
            return [OutlineNode(
                id: noteId(path), kind: .note, title: lead.title, path: path,
                headingIndex: lead.usedH1 ? 0 : nil, headingLine: lead.heading?.line,
                children: nestHeadings(bodyHeadings(hs), path: path), loadsHeadings: false
            )]
        case .folder:
            return folderTree(of: currentPath, currentText: currentText, in: snapshot)
        case .neighbors:
            guard let path = currentPath, snapshot.notes[path] != nil else { return [] }
            return neighborTree(of: path, currentText: currentText, in: snapshot)
        case .vault:
            return fileTree(snapshot.tree, currentPath: currentPath, currentText: currentText, in: snapshot)
        }
    }

    /// Visible rows of expanded branches only. Heading trees are materialized when a note
    /// (or a folder that stands in for its folder note) is expanded, and heading branches
    /// are open unless listed in `collapsedHeadings`.
    public static func flatten(_ roots: [OutlineNode], expanded: Set<String>,
                               headings: (String) -> [Heading],
                               collapsedHeadings: Set<String> = []) -> [OutlineRow] {
        var out: [OutlineRow] = []
        func isOpen(_ n: OutlineNode, hasChildren: Bool) -> Bool {
            guard hasChildren else { return false }
            if n.kind == .heading { return !collapsedHeadings.contains(n.id) }
            return expanded.contains(n.id)
        }
        func walk(_ n: OutlineNode, depth: Int) {
            let c = headingChildren(of: n, headings: headings)
            out.append(OutlineRow(
                id: n.id, kind: n.kind, title: n.title, depth: depth, path: n.path,
                headingIndex: n.headingIndex, headingLine: n.headingLine, headingLevel: n.headingLevel,
                expandable: !c.isEmpty
            ))
            if isOpen(n, hasChildren: !c.isEmpty) {
                for k in c { walk(k, depth: depth + 1) }
            }
        }
        for r in roots { walk(r, depth: 0) }
        return out
    }

    /// Ids of folders and notes along the path to `path`, so flatten can show that note
    /// and its headings. In this-note scope the title row is a note node and is included.
    public static func reveal(_ path: String?, in roots: [OutlineNode],
                              headings: (String) -> [Heading] = { _ in [] }) -> Set<String> {
        if roots.allSatisfy({ $0.kind == .heading }) { return [] }
        guard let path else { return [] }
        var found: [String] = []
        func walk(_ nodes: [OutlineNode], trail: [String]) -> Bool {
            for n in nodes {
                let next = trail + [n.id]
                if n.path == path, n.kind != .heading {
                    found = next
                    return true
                }
                if walk(n.children, trail: next) { return true }
            }
            return false
        }
        _ = walk(roots, trail: [])
        return Set(found)
    }

    /// Expand the ancestor chain and the active node's children; collapse off-path sibling
    /// branches. Depth-0 rows stay listed. Manually expanded (`heldOpen`) nodes stay open
    /// until the active path leaves their top-level root, or until the path entered them
    /// and later left. `keepOpen` (filter/search matches and their ancestors) is never
    /// auto-collapsed. Does not walk unloaded heading trees of off-path notes.
    public static func follow(activeId: String?, roots: [OutlineNode],
                              headings: (String) -> [Heading],
                              expanded: Set<String>,
                              heldOpen: Set<String>,
                              entered: Set<String>,
                              keepOpen: Set<String> = []) -> OutlineFollow {
        let pathIds = pathTo(activeId, in: roots, headings: headings)
        let pathSet = Set(pathIds)
        // The "area" of the path is the last note, folder, or H1 (the title row counts).
        // A hold under the leading H1 stays open while you move among its ## children,
        // and is released when the path enters a later H1 chapter. In folder/vault
        // scopes that is just the current note or folder.
        func section(of id: String?) -> String? {
            let chain = pathNodes(to: id, in: roots, headings: headings)
            if let last = chain.last(where: { $0.kind != .heading || $0.headingLevel == 1 }) {
                return last.id
            }
            return chain.first?.id
        }
        let pathArea = section(of: activeId)

        var newHeld = heldOpen
        var newEntered = entered
        for id in heldOpen where pathSet.contains(id) { newEntered.insert(id) }

        func released(_ id: String) -> Bool {
            if newEntered.contains(id), !pathSet.contains(id) { return true }
            if let pathArea {
                let holdArea = section(of: id)
                if let holdArea, holdArea != pathArea { return true }
            }
            return false
        }

        for id in heldOpen where released(id) {
            newHeld.remove(id)
            newEntered.remove(id)
        }

        var expand: Set<String> = []
        var collapse: Set<String> = []

        func walk(_ nodes: [OutlineNode]) {
            for n in nodes {
                let kids = headingChildren(of: n, headings: headings)
                let onPath = pathSet.contains(n.id)
                let keep = keepOpen.contains(n.id) || (newHeld.contains(n.id) && !released(n.id))
                if onPath || keep {
                    if n.kind != .heading { expand.insert(n.id) }
                } else if !kids.isEmpty, n.kind == .heading {
                    // The row stays listed; collapsing hides off-path children.
                    collapse.insert(n.id)
                }
                // Only descend into path, held, kept, or already-expanded branches so
                // a whole-vault walk does not materialize every note's headings.
                if onPath || keep || expanded.contains(n.id) {
                    walk(kids)
                }
            }
        }
        walk(roots)

        // If the only root is the note title row (this-note scope), it is always on the path
        // when anything in the note is active; include it even if findPath missed.
        if let first = roots.first, first.kind == .note, roots.count == 1, activeId != nil {
            expand.insert(first.id)
        }
        return OutlineFollow(expand: expand, collapse: collapse, heldOpen: newHeld, entered: newEntered)
    }

    /// Ancestor chain from a root down to `activeId`, inclusive. Only materializes heading
    /// trees for notes that could contain the target.
    public static func pathTo(_ activeId: String?, in roots: [OutlineNode],
                              headings: (String) -> [Heading]) -> [String] {
        pathNodes(to: activeId, in: roots, headings: headings).map(\.id)
    }

    static func pathNodes(to activeId: String?, in roots: [OutlineNode],
                          headings: (String) -> [Heading]) -> [OutlineNode] {
        guard let activeId else { return [] }
        let targetNote = notePath(fromId: activeId)
        func walk(_ nodes: [OutlineNode], trail: [OutlineNode]) -> [OutlineNode]? {
            for n in nodes {
                let next = trail + [n]
                if n.id == activeId { return next }
                let kids: [OutlineNode]
                if n.loadsHeadings, let path = n.path, targetNote == path || n.kind == .folder {
                    kids = headingChildren(of: n, headings: headings)
                } else {
                    kids = n.children
                }
                if let p = walk(kids, trail: next) { return p }
            }
            return nil
        }
        return walk(roots, trail: []) ?? []
    }

    public static func notePath(fromId id: String) -> String? {
        if id.hasPrefix("n:") { return String(id.dropFirst(2)) }
        if id.hasPrefix("h:") {
            let rest = String(id.dropFirst(2))
            if let at = rest.lastIndex(of: "@") {
                let beforeAt = rest[..<at]
                if let hash = beforeAt.lastIndex(of: "#") { return String(beforeAt[..<hash]) }
            }
        }
        return nil
    }
}

extension OutlineTree {
    /// Folder scope: the open note's folder as the root, with its subfolders and notes.
    /// A note at the vault root uses the vault's top-level children (no dummy root row).
    static func folderTree(of currentPath: String?, currentText: String?, in snap: VaultSnapshot) -> [OutlineNode] {
        guard let path = currentPath, let note = snap.notes[path] else { return [] }
        let folder = note.folder
        if folder.isEmpty { return fileTree(snap.tree, currentPath: currentPath, currentText: currentText, in: snap) }
        guard let node = findFolder(folder, in: snap.tree) else {
            return [noteNode(path, fallback: snap.notes[path]?.name ?? path, in: snap, currentPath: currentPath, currentText: currentText)]
        }
        return [folderNode(node, in: snap, currentPath: currentPath, currentText: currentText)]
    }

    static func neighborTree(of path: String, currentText: String?, in snap: VaultSnapshot) -> [OutlineNode] {
        let parents = snap.parents(of: path)
        let partNodes = Ancestry.partsTree(of: path, parts: { snap.parts(of: $0) })
        var used: Set<String> = [path]
        used.formUnion(parents)
        func collectParts(_ nodes: [Ancestry.Node]) {
            for n in nodes { used.insert(n.path); collectParts(n.children) }
        }
        collectParts(partNodes)

        var linked: [String] = []
        if let note = snap.notes[path] {
            var seen = Set<String>()
            for l in note.summary.links {
                guard let resolved = snap.resolve(l.target, from: path), resolved != path,
                      snap.notes[resolved] != nil, seen.insert(resolved).inserted, !used.contains(resolved)
                else { continue }
                linked.append(resolved)
            }
        }
        for b in snap.backlinks(to: path) {
            let s = b.source
            if s != path, snap.notes[s] != nil, !used.contains(s), !linked.contains(s) { linked.append(s) }
        }

        func withParts(_ p: String) -> OutlineNode {
            var n = noteNode(p, fallback: snap.notes[p]?.name ?? p, in: snap, currentPath: path, currentText: currentText)
            n.children += partNodes.map { partOutline($0, in: snap, currentPath: path, currentText: currentText) }
            return n
        }

        var roots: [OutlineNode] = []
        if parents.isEmpty {
            roots.append(withParts(path))
        } else {
            for (i, parent) in parents.enumerated() {
                var n = noteNode(parent, fallback: snap.notes[parent]?.name ?? parent, in: snap, currentPath: path, currentText: currentText)
                if i == 0 { n.children.append(withParts(path)) }
                roots.append(n)
            }
        }
        roots += linked.map { noteNode($0, fallback: snap.notes[$0]?.name ?? $0, in: snap, currentPath: path, currentText: currentText) }
        return roots
    }

    static func partOutline(_ node: Ancestry.Node, in snap: VaultSnapshot, currentPath: String?, currentText: String?) -> OutlineNode {
        var n = noteNode(node.path, fallback: snap.notes[node.path]?.name ?? node.path, in: snap, currentPath: currentPath, currentText: currentText)
        if !node.cycle { n.children += node.children.map { partOutline($0, in: snap, currentPath: currentPath, currentText: currentText) } }
        return n
    }

    static func fileTree(_ root: FileNode, currentPath: String?, currentText: String?, in snap: VaultSnapshot) -> [OutlineNode] {
        (root.children ?? []).compactMap { childNode($0, in: snap, currentPath: currentPath, currentText: currentText) }
    }

    static func childNode(_ n: FileNode, in snap: VaultSnapshot, currentPath: String?, currentText: String?) -> OutlineNode? {
        if n.isFolder { return folderNode(n, in: snap, currentPath: currentPath, currentText: currentText) }
        guard n.isNote, snap.notes[n.path] != nil else { return nil }
        return noteNode(n.path, fallback: n.displayName, in: snap, currentPath: currentPath, currentText: currentText)
    }

    static func folderNode(_ n: FileNode, in snap: VaultSnapshot, currentPath: String?, currentText: String?) -> OutlineNode {
        let kids = (n.children ?? []).compactMap { childNode($0, in: snap, currentPath: currentPath, currentText: currentText) }
        let folderNote = n.folderNote
        let body: [Heading] = folderNote.map { headings(for: $0, currentPath: currentPath, currentText: currentText, in: snap) } ?? []
        return OutlineNode(
            id: folderId(n.path),
            kind: .folder,
            title: n.name,
            path: folderNote,
            children: kids,
            loadsHeadings: folderNote != nil && !bodyHeadings(body).isEmpty
        )
    }

    static func noteNode(_ path: String, fallback: String, in snap: VaultSnapshot,
                         currentPath: String? = nil, currentText: String? = nil) -> OutlineNode {
        let hs = headings(for: path, currentPath: currentPath, currentText: currentText, in: snap)
        let lead = leadingTitle(in: hs, fallback: fallback)
        return OutlineNode(
            id: noteId(path), kind: .note, title: lead.title, path: path,
            headingIndex: lead.usedH1 ? 0 : nil, headingLine: lead.heading?.line,
            children: [], loadsHeadings: !bodyHeadings(hs).isEmpty
        )
    }

    static func findFolder(_ path: String, in root: FileNode) -> FileNode? {
        if root.isFolder, root.path == path { return root }
        for c in root.children ?? [] {
            if let f = findFolder(path, in: c) { return f }
        }
        return nil
    }
}
