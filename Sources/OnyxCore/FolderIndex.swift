import Foundation

/// Folder notes (indexes) live at `<folder>/<FolderName>.md` — for example
/// `Projects/Projects.md` or `Life/Family/Projects/Projects.md`. The vault root
/// has no folder note (`Home.md` is just a root note). The file tree hides that
/// file and marks the folder row (`FileNode.folderNote`); the title path merges
/// the last folder with the note, and a frontmatter `class:` (typically `Index`)
/// shows as a tag in the title bar.
public enum FolderIndex {
    /// The folder-note path for `folder`, or `nil` for the vault root.
    public static func notePath(forFolder folder: String) -> String? {
        var folder = folder
        while folder.hasPrefix("/") { folder.removeFirst() }
        while folder.hasSuffix("/") { folder.removeLast() }
        guard !folder.isEmpty else { return nil }
        let name = (folder as NSString).lastPathComponent
        return folder + "/" + name + ".md"
    }

    /// Whether a folder already has a folder note among the given vault note paths.
    public static func hasIndex(folder: String, notes: Set<String>) -> Bool {
        guard let p = notePath(forFolder: folder) else { return false }
        return notes.contains(p)
    }

    /// Most common `class:` among existing folder notes; `"Index"` when none have a class.
    public static func inferredClass(_ classes: [String?]) -> String {
        var counts: [String: Int] = [:]
        for c in classes {
            guard let c, !c.isEmpty else { continue }
            counts[c, default: 0] += 1
        }
        return counts.max { a, b in
            a.value == b.value ? a.key > b.key : a.value < b.value
        }?.key ?? "Index"
    }

    /// A wikilink: the bare name when it is unique in the vault, otherwise the path without `.md`.
    public static func wikilink(path: String, nameCounts: [String: Int]) -> String {
        let stem = path.lowercased().hasSuffix(".md") ? String(path.dropLast(3)) : path
        let name = (stem as NSString).lastPathComponent
        if nameCounts[name, default: 1] <= 1 { return "[[\(name)]]" }
        return "[[\(stem)]]"
    }

    /// Seeded body for a new folder index: frontmatter class, a title, a short
    /// placeholder, a list of wikilinks to the folder's current notes and
    /// subfolders, and a `partOf::` link to the parent folder's index when there is one.
    public static func draft(
        folder: String,
        childNotes: [String],
        childFolders: [String],
        parentIndex: String? = nil,
        nameCounts: [String: Int] = [:],
        indexClass: String = "Index"
    ) -> String {
        let title = (folder as NSString).lastPathComponent
        let selfPath = notePath(forFolder: folder)
        var lines: [String] = []
        if !indexClass.isEmpty {
            lines.append("---")
            lines.append("class: \(indexClass)")
            lines.append("---")
        }
        lines.append("# \(title)")
        lines.append("")
        lines.append("An index of this folder.")
        lines.append("")

        let folders = childFolders.sorted {
            ($0 as NSString).lastPathComponent.localizedStandardCompare(($1 as NSString).lastPathComponent) == .orderedAscending
        }
        let notes = childNotes.filter { $0 != selfPath }.sorted {
            ($0 as NSString).lastPathComponent.localizedStandardCompare(($1 as NSString).lastPathComponent) == .orderedAscending
        }
        if !folders.isEmpty || !notes.isEmpty {
            for f in folders { lines.append("- \(wikilink(path: f, nameCounts: nameCounts))") }
            for n in notes { lines.append("- \(wikilink(path: n, nameCounts: nameCounts))") }
            lines.append("")
        }
        if let parentIndex {
            lines.append("partOf:: \(wikilink(path: parentIndex, nameCounts: nameCounts))")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Build a draft from a live snapshot: child notes and subfolders, the parent
    /// folder's index when it exists, and the class already used by other folder notes.
    public static func draft(forFolder folder: String, in snap: VaultSnapshot) -> String {
        let index = notePath(forFolder: folder)
        let childNotes = snap.notes.keys.filter {
            ($0 as NSString).deletingLastPathComponent == folder && $0 != index
        }
        var folderSet = snap.folders
        for p in snap.notes.keys {
            var dir = (p as NSString).deletingLastPathComponent
            while !dir.isEmpty {
                folderSet.insert(dir)
                dir = (dir as NSString).deletingLastPathComponent
            }
        }
        let childFolders = folderSet.filter { ($0 as NSString).deletingLastPathComponent == folder }

        let parent = (folder as NSString).deletingLastPathComponent
        let parentIndex = notePath(forFolder: parent).flatMap { snap.notes[$0] != nil ? $0 : nil }

        var classes: [String?] = []
        for f in folderSet {
            if let p = notePath(forFolder: f), p != index, snap.notes[p] != nil {
                classes.append(snap.noteClass(p))
            }
        }

        var nameCounts: [String: Int] = [:]
        for p in snap.notes.keys {
            let n = ((p as NSString).lastPathComponent as NSString).deletingPathExtension
            nameCounts[n, default: 0] += 1
        }

        return draft(
            folder: folder,
            childNotes: Array(childNotes),
            childFolders: Array(childFolders),
            parentIndex: parentIndex,
            nameCounts: nameCounts,
            indexClass: inferredClass(classes)
        )
    }
}
