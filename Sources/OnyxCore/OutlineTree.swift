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

/// Pure outline construction: nest headings, widen scope around the open note, and
/// flatten only the expanded branches so a large vault stays cheap to draw.
public enum OutlineTree {
    public static func folderId(_ path: String) -> String { "f:" + path }
    public static func noteId(_ path: String) -> String { "n:" + path }
    public static func headingId(_ path: String, index: Int, line: Int) -> String { "h:\(path)#\(index)@\(line)" }

    /// Last heading whose source line is at or above `line` (0-based, as in `Heading.line`).
    public static func headingIndex(at line: Double, in headings: [Heading]) -> Int? {
        let n = Int(floor(line))
        var best: Int? = nil
        for (i, h) in headings.enumerated() {
            if h.line <= n { best = i } else { break }
        }
        return best
    }

    public static func activeId(path: String?, line: Double, headings: [Heading]) -> String? {
        guard let path else { return nil }
        if let i = headingIndex(at: line, in: headings) {
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

    public static func build(scope: OutlineScope, currentPath: String?, currentText: String? = nil,
                             snapshot: VaultSnapshot) -> [OutlineNode] {
        switch scope {
        case .note:
            guard let path = currentPath else { return [] }
            return nestHeadings(headings(for: path, currentPath: currentPath, currentText: currentText, in: snapshot), path: path)
        case .folder:
            return folderTree(of: currentPath, in: snapshot)
        case .neighbors:
            guard let path = currentPath, snapshot.notes[path] != nil else { return [] }
            return neighborTree(of: path, in: snapshot)
        case .vault:
            return fileTree(snapshot.tree, in: snapshot)
        }
    }

    /// Visible rows of expanded branches only. Heading trees are materialized when a note
    /// (or a folder that stands in for its folder note) is expanded, and heading branches
    /// are open unless listed in `collapsedHeadings`.
    public static func flatten(_ roots: [OutlineNode], expanded: Set<String>,
                               headings: (String) -> [Heading],
                               collapsedHeadings: Set<String> = []) -> [OutlineRow] {
        var out: [OutlineRow] = []
        func kids(of n: OutlineNode) -> [OutlineNode] {
            var c = n.children
            if n.loadsHeadings, let path = n.path {
                c = nestHeadings(headings(path), path: path) + c
            }
            return c
        }
        func isOpen(_ n: OutlineNode, hasChildren: Bool) -> Bool {
            guard hasChildren else { return false }
            if n.kind == .heading { return !collapsedHeadings.contains(n.id) }
            return expanded.contains(n.id)
        }
        func walk(_ n: OutlineNode, depth: Int) {
            let c = kids(of: n)
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
    /// and its headings (heading branches are open by default). A this-note heading
    /// forest needs no structural expansion.
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

}

extension OutlineTree {
    /// Folder scope: the open note's folder as the root, with its subfolders and notes.
    /// A note at the vault root uses the vault's top-level children (no dummy root row).
    static func folderTree(of currentPath: String?, in snap: VaultSnapshot) -> [OutlineNode] {
        guard let path = currentPath, let note = snap.notes[path] else { return [] }
        let folder = note.folder
        if folder.isEmpty { return fileTree(snap.tree, in: snap) }
        guard let node = findFolder(folder, in: snap.tree) else {
            // the note's folder isn't in the tree yet: show the note alone
            return [noteNode(path, title: snap.notes[path]?.name ?? path, in: snap)]
        }
        return [folderNode(node, in: snap)]
    }

    static func neighborTree(of path: String, in snap: VaultSnapshot) -> [OutlineNode] {
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
            var n = noteNode(p, title: snap.notes[p]?.name ?? p, in: snap)
            n.children += partNodes.map { partOutline($0, in: snap) }
            return n
        }

        var roots: [OutlineNode] = []
        if parents.isEmpty {
            roots.append(withParts(path))
        } else {
            for (i, parent) in parents.enumerated() {
                var n = noteNode(parent, title: snap.notes[parent]?.name ?? parent, in: snap)
                if i == 0 { n.children.append(withParts(path)) }
                roots.append(n)
            }
        }
        roots += linked.map { noteNode($0, title: snap.notes[$0]?.name ?? $0, in: snap) }
        return roots
    }

    static func partOutline(_ node: Ancestry.Node, in snap: VaultSnapshot) -> OutlineNode {
        var n = noteNode(node.path, title: snap.notes[node.path]?.name ?? node.path, in: snap)
        if !node.cycle { n.children += node.children.map { partOutline($0, in: snap) } }
        return n
    }

    static func fileTree(_ root: FileNode, in snap: VaultSnapshot) -> [OutlineNode] {
        (root.children ?? []).compactMap { childNode($0, in: snap) }
    }

    static func childNode(_ n: FileNode, in snap: VaultSnapshot) -> OutlineNode? {
        if n.isFolder { return folderNode(n, in: snap) }
        guard n.isNote, snap.notes[n.path] != nil else { return nil }
        return noteNode(n.path, title: n.displayName, in: snap)
    }

    static func folderNode(_ n: FileNode, in snap: VaultSnapshot) -> OutlineNode {
        let kids = (n.children ?? []).compactMap { childNode($0, in: snap) }
        let folderNote = n.folderNote
        return OutlineNode(
            id: folderId(n.path),
            kind: .folder,
            title: n.name,
            path: folderNote,
            children: kids,
            loadsHeadings: folderNote != nil
        )
    }

    static func noteNode(_ path: String, title: String, in snap: VaultSnapshot) -> OutlineNode {
        // expandable when the note has headings; children stay deferred
        let has = !(snap.notes[path]?.summary.headings.isEmpty ?? true)
        return OutlineNode(id: noteId(path), kind: .note, title: title, path: path,
                           children: [], loadsHeadings: has)
    }

    static func findFolder(_ path: String, in root: FileNode) -> FileNode? {
        if root.isFolder, root.path == path { return root }
        for c in root.children ?? [] {
            if let f = findFolder(path, in: c) { return f }
        }
        return nil
    }
}
