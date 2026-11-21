import Foundation

/// What a pointer click on a folder in the file tree should do.
///
/// The disclosure chevron always toggles expansion and never opens the folder
/// note. A click on the rest of the row toggles expansion too, and if the folder
/// has an index note (`Folder/Folder.md`) it also opens that note — a second
/// click on an already-open folder note's row collapses the folder.
public struct FolderTreeClick: Equatable, Sendable {
    public enum Target: Equatable, Sendable { case chevron, row }

    public var toggleExpansion: Bool
    public var openFolderNote: Bool

    public init(toggleExpansion: Bool, openFolderNote: Bool) {
        self.toggleExpansion = toggleExpansion
        self.openFolderNote = openFolderNote
    }

    public static func action(_ target: Target, hasFolderNote: Bool) -> FolderTreeClick {
        switch target {
        case .chevron: return FolderTreeClick(toggleExpansion: true, openFolderNote: false)
        case .row: return FolderTreeClick(toggleExpansion: true, openFolderNote: hasFolderNote)
        }
    }
}


/// How `openNote` reveals a note in the file tree.
///
/// Expanding every ancestor of the current note must not run after a user has
/// collapsed one of those folders — including a second click on a folder that
/// has an index note, which opens that note again.
public enum TreeReveal {
    /// Parent folders of `path`, nearest first (the note itself is not included).
    public static func ancestors(of path: String) -> [String] {
        var out: [String] = []
        var parent = (path as NSString).deletingLastPathComponent
        while !parent.isEmpty {
            out.append(parent)
            parent = (parent as NSString).deletingLastPathComponent
        }
        return out
    }

    /// Whether opening a note should expand its ancestors. False when the note is
    /// already open (a reload must not undo a collapse) or when the caller has
    /// just toggled a folder row (`reveal` is false).
    public static func shouldExpandAncestors(alreadyOpen: Bool, reveal: Bool) -> Bool {
        reveal && !alreadyOpen
    }
}
