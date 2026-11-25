import Foundation

/// How the sidebar orders one folder's rows. Natural name order ("Note 2" before "Note 10"), by
/// modified or created date (folders take their newest / oldest note), folders on top by default.
public struct TreeSort: Codable, Equatable, Hashable, Sendable {
    public enum Key: String, Codable, CaseIterable, Sendable {
        case name, modified, created
        public var title: String { switch self { case .name: "Name"; case .modified: "Modified"; case .created: "Created" } }
    }
    public var key: Key
    public var ascending: Bool
    public var foldersFirst: Bool
    public init(key: Key = .name, ascending: Bool? = nil, foldersFirst: Bool = true) {
        self.key = key; self.ascending = ascending ?? (key == .name); self.foldersFirst = foldersFirst
    }
    public static let standard = TreeSort()
}

/// The vault default plus per-folder overrides ("Sort this folder by…").
public struct TreeOrder: Codable, Equatable, Sendable {
    public var base = TreeSort.standard
    public var overrides: [String: TreeSort] = [:]
    public init(base: TreeSort = .standard, overrides: [String: TreeSort] = [:]) { self.base = base; self.overrides = overrides }
    public func sort(for folder: String) -> TreeSort { overrides[folder] ?? base }
}

/// Dates for sorting: a note's own, a folder's newest modification and oldest creation inside it.
public struct TreeDates: Sendable {
    public var modified: [String: Date] = [:]
    public var created: [String: Date] = [:]
    public init(_ snap: VaultSnapshot) {
        func bump(_ p: String, _ m: Date, _ c: Date) {
            modified[p] = max(modified[p] ?? .distantPast, m)
            created[p] = min(created[p] ?? .distantFuture, c)
        }
        func up(_ p: String, _ m: Date, _ c: Date) {
            bump(p, m, c)
            var f = (p as NSString).deletingLastPathComponent
            while !f.isEmpty { bump(f, m, c); f = (f as NSString).deletingLastPathComponent }
        }
        // Each file sets its own dates and its folder's; folders then pass theirs up once
        // (206 folders instead of walking every file's ancestry).
        var direct: [String: (Date, Date)] = [:]
        func file(_ p: String, _ m: Date, _ c: Date) {
            bump(p, m, c)
            let f = (p as NSString).deletingLastPathComponent
            guard !f.isEmpty else { return }
            let o = direct[f]
            direct[f] = (max(o?.0 ?? .distantPast, m), min(o?.1 ?? .distantFuture, c))
        }
        for (p, n) in snap.notes { file(p, n.mtime, n.ctime) }
        for (p, d) in snap.attachments { file(p, d, d) }
        for (f, (m, c)) in direct { up(f, m, c) }
    }

    public func ordered(_ nodes: [FileNode], by s: TreeSort) -> [FileNode] {
        func name(_ n: FileNode) -> String { n.isNote ? n.displayName : n.name }
        func byName(_ a: FileNode, _ b: FileNode) -> Bool { name(a).localizedStandardCompare(name(b)) == .orderedAscending }
        return nodes.sorted { a, b in
            if s.foldersFirst && a.isFolder != b.isFolder { return a.isFolder }
            switch s.key {
            case .name:
                let r = name(a).localizedStandardCompare(name(b))
                if r == .orderedSame { return a.path < b.path }
                return (r == .orderedAscending) == s.ascending
            case .modified, .created:
                let d = s.key == .modified ? modified : created
                let da = d[a.path] ?? .distantPast, db = d[b.path] ?? .distantPast
                if da == db { return byName(a, b) }
                return (da < db) == s.ascending
            }
        }
    }
}

/// A visible file-tree row: the node and its indent depth (0 at the vault root).
public struct FileTreeRow: Equatable, Identifiable, Sendable {
    public var node: FileNode
    public var depth: Int
    public var id: String { node.id }
    public init(node: FileNode, depth: Int) { self.node = node; self.depth = depth }
}

public extension FileNode {
    /// Visible rows in the order the sidebar draws them, with indent depth.
    func visibleRows(expanded: Set<String>, children: (FileNode) -> [FileNode]) -> [FileTreeRow] {
        var out: [FileTreeRow] = []
        func walk(_ n: FileNode, depth: Int) {
            for c in children(n) {
                out.append(FileTreeRow(node: c, depth: depth))
                if c.isFolder, expanded.contains(c.path) { walk(c, depth: depth + 1) }
            }
        }
        walk(self, depth: 0)
        return out
    }

    /// Visible rows in the order the sidebar draws them, for ⇧-click ranges.
    func visiblePaths(expanded: Set<String>, children: (FileNode) -> [FileNode]) -> [String] {
        visibleRows(expanded: expanded, children: children).map(\.node.path)
    }
}
