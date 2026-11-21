import Foundation

/// Flatten a sidebar selection into a book outline for PDF export.
/// Folders expand recursively in sidebar order, with a folder's own note first, then its children.
/// Items inside a selected folder are not repeated.
public enum SectionExport {
    public struct Item: Equatable, Sendable {
        public enum Kind: Equatable, Sendable { case part, note }
        public var kind: Kind
        public var path: String
        public var title: String
        public var depth: Int
        public init(kind: Kind, path: String, title: String, depth: Int) {
            self.kind = kind; self.path = path; self.title = title; self.depth = depth
        }
    }

    public static func noteTitle(_ path: String) -> String {
        let last = (path as NSString).lastPathComponent
        return last.lowercased().hasSuffix(".md") ? String(last.dropLast(3)) : last
    }

    /// A reasonable default filename: the folder name when exporting one folder, otherwise "Selection.pdf".
    public static func defaultFilename(_ items: [Item]) -> String {
        let top = items.filter { $0.depth == 0 }
        if top.count == 1, top[0].kind == .part { return top[0].title + ".pdf" }
        return "Selection.pdf"
    }

    public static func outline(selected: some Collection<String>, root: FileNode, children: (FileNode) -> [FileNode]) -> [Item] {
        let roots = Set(TreeSelection.roots(selected))
        var items: [Item] = []
        var seen = Set<String>()

        func emit(_ node: FileNode, depth: Int) {
            if node.isFolder {
                guard seen.insert(node.path).inserted else { return }
                items.append(Item(kind: .part, path: node.path, title: node.displayName, depth: depth))
                if let fn = node.folderNote, seen.insert(fn).inserted {
                    items.append(Item(kind: .note, path: fn, title: noteTitle(fn), depth: depth + 1))
                }
                for c in children(node) { emit(c, depth: depth + 1) }
            } else if node.isNote {
                guard seen.insert(node.path).inserted else { return }
                items.append(Item(kind: .note, path: node.path, title: node.displayName, depth: depth))
            }
        }

        func walk(_ node: FileNode) {
            for c in children(node) {
                if roots.contains(c.path) { emit(c, depth: 0) }
                else if c.isFolder { walk(c) }
            }
        }
        walk(root)
        return items
    }
}
