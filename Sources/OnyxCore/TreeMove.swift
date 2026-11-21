import Foundation

/// Policy for ⌘-dragging notes and folders onto a file-tree row (or the vault root).
public enum TreeMove {
    public enum Verdict: Equatable, Sendable {
        /// Nothing to do: empty sources, or every item is already in the folder.
        case none
        /// A folder would land inside itself or one of its descendants.
        case refuse(String)
        /// The destination already has something with that name.
        case collision(String)
        /// These sources should be moved (already-in-folder items dropped).
        case move([String])
    }

    /// Folder a drop on `target` should move into. `""` is the vault root.
    /// Dropping on a file uses that file’s parent; dropping on a folder (or the root zone) uses it as-is.
    public static func destination(droppingOn target: String, targetIsFolder: Bool) -> String {
        targetIsFolder ? target : (target as NSString).deletingLastPathComponent
    }

    public static func destPath(source: String, toFolder folder: String) -> String {
        let name = (source as NSString).lastPathComponent
        return folder.isEmpty ? name : folder + "/" + name
    }

    public static func verdict(sources: [String], toFolder folder: String, occupied: (String) -> Bool) -> Verdict {
        let roots = TreeSelection.roots(sources)
        guard !roots.isEmpty else { return .none }
        for p in roots {
            if folder == p || folder.hasPrefix(p + "/") {
                return .refuse("You can’t move a folder into itself.")
            }
        }
        var toMove: [String] = []
        for p in roots {
            if (p as NSString).deletingLastPathComponent == folder { continue }
            let dest = destPath(source: p, toFolder: folder)
            if occupied(dest), dest.lowercased() != p.lowercased() {
                let last = (dest as NSString).lastPathComponent
                let shown = last.lowercased().hasSuffix(".md") ? String(last.dropLast(3)) : last
                return .collision("“\(shown)” already exists there.")
            }
            toMove.append(p)
        }
        return toMove.isEmpty ? .none : .move(toMove)
    }
}
