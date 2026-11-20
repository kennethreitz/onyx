import Foundation

/// Finder-style selection in the file tree. Pure, so it can be tested.
/// - click: select just this row (the caller also opens it)
/// - toggle (⌘-click): add or remove one row; the open note doesn't change
/// - extend (⇧-click): the contiguous run of visible rows from the anchor to this row
public struct TreeSelection: Equatable, Sendable {
    public private(set) var selected: Set<String> = []
    public private(set) var anchor: String?
    public init() {}

    public var count: Int { selected.count }
    public var isMulti: Bool { selected.count > 1 }
    public func contains(_ p: String) -> Bool { selected.contains(p) }

    public mutating func click(_ p: String) { selected = [p]; anchor = p }

    public mutating func toggle(_ p: String) {
        if selected.contains(p) { selected.remove(p) } else { selected.insert(p) }
        anchor = p
    }

    /// `visible` is the tree's visible rows in display order. With no anchor (or an anchor no
    /// longer visible) it behaves like a click.
    public mutating func extend(to p: String, visible: [String]) {
        guard let a = anchor, let i = visible.firstIndex(of: a), let j = visible.firstIndex(of: p) else { click(p); return }
        selected = Set(visible[min(i, j)...max(i, j)])
        // the anchor stays put, so a second ⇧-click re-spans from the same row (as in Finder)
    }

    public mutating func clear() { selected = []; anchor = nil }

    /// Drop paths that disappeared (deleted, moved, collapsed away is fine to keep).
    public mutating func prune(_ exists: (String) -> Bool) {
        selected = selected.filter(exists)
        if let a = anchor, !exists(a) { anchor = nil }
    }

    /// The paths to act on: sorted, with anything inside a selected folder dropped
    /// (deleting or moving the folder already covers it).
    public static func roots(_ paths: some Collection<String>) -> [String] {
        let sorted = Set(paths).sorted()
        return sorted.filter { p in !sorted.contains { $0 != p && p.hasPrefix($0 + "/") } }
    }

    /// "Mercury", "Mercury and Venus", "3 items: Mercury, Venus, Mars", "7 items: A, B, C, …".
    public static func describe(_ paths: [String]) -> String {
        let names = paths.map { p -> String in
            let last = (p as NSString).lastPathComponent
            return last.lowercased().hasSuffix(".md") ? String(last.dropLast(3)) : last
        }
        switch names.count {
        case 0: return "nothing"
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default:
            let head = names.prefix(3).joined(separator: ", ")
            return "\(names.count) items: \(head)\(names.count > 3 ? ", …" : "")"
        }
    }
}

public extension FileNode {
    /// The rows the tree shows, in order: children of expanded folders only.
    func visiblePaths(expanded: Set<String>) -> [String] {
        var out: [String] = []
        func walk(_ n: FileNode) {
            for c in n.children ?? [] {
                out.append(c.path)
                if c.isFolder, expanded.contains(c.path) { walk(c) }
            }
        }
        walk(self)
        return out
    }
}
