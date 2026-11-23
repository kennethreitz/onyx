import Foundation

/// A clickable piece of the title-bar path.
public struct TitleCrumb: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Reveal this folder in the sidebar.
        case folder(path: String)
        /// The open note. Shown as the last crumb; it is not a control.
        case note
        /// A `partOf` ancestor: open it. `others` lists the note's other direct parents
        /// (only on the last ancestor crumb).
        case ancestor(path: String, others: [String])
    }
    public var name: String
    public var kind: Kind
    public init(name: String, kind: Kind) { self.name = name; self.kind = kind }
}

/// Build the title-bar crumbs for a note (or canvas/base) in `folder` named `name`.
///
/// A folder note such as `Projects/Projects.md` or `Life/Family/Projects/Projects.md`
/// merges the last folder and the note into one final crumb, so the path is not
/// "… / Projects / Projects". Clicking that last crumb stays on the note; earlier
/// crumbs still reveal their folder. Ordinary notes are unchanged.
public enum TitlePath {
    public static func crumbs(folder: String, name: String) -> [TitleCrumb] {
        let parts = folder.isEmpty ? [] : folder.split(separator: "/").map(String.init)
        let isIndex = parts.last == name
        let folderCount = isIndex ? parts.count - 1 : parts.count
        var crumbs: [TitleCrumb] = []
        var acc: [String] = []
        for (i, p) in parts.enumerated() {
            acc.append(p)
            if i < folderCount {
                crumbs.append(TitleCrumb(name: p, kind: .folder(path: acc.joined(separator: "/"))))
            }
        }
        crumbs.append(TitleCrumb(name: name, kind: .note))
        return crumbs
    }

    /// With a `partOf` ancestry (root-most first, ending at the direct parent) the path reads
    /// `Grandparent › Parent › Note` instead of the folders, so the two never repeat each other.
    /// Without one it is the folder path above.
    public static func crumbs(folder: String, name: String, ancestry: [String], otherParents: [String] = []) -> [TitleCrumb] {
        guard !ancestry.isEmpty else { return crumbs(folder: folder, name: name) }
        func stem(_ p: String) -> String { ((p as NSString).lastPathComponent as NSString).deletingPathExtension }
        var out = ancestry.enumerated().map { i, p in
            TitleCrumb(name: stem(p), kind: .ancestor(path: p, others: i == ancestry.count - 1 ? otherParents : []))
        }
        out.append(TitleCrumb(name: name, kind: .note))
        return out
    }
}
