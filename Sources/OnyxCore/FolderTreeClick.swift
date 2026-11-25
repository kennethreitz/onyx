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


/// Tracks a file-tree pointer press so a click fires once and a drag can still
/// start after the movement threshold. A regular click fires on mouse-down
/// (the folder expands immediately) and must not fire again on mouse-up — that
/// second toggle was a regression that made a folder snap back when you let go.
/// A ⌘-click is deferred until mouse-up so a ⌘-drag can move files without
/// toggling selection first.
public struct TreePointerSession: Equatable, Sendable {
    public enum Down: Equatable, Sendable { case clickNow, deferClick }
    public enum Drag: Equatable, Sendable { case startDrag, none }
    public enum Up: Equatable, Sendable { case clickNow, none }

    /// Squared distance, in view points, that counts as a drag (4pt).
    public static let dragThresholdSquared: Double = 16

    private var armed = false
    private var clickFired = false
    private var dragging = false

    public init() {}

    public mutating func mouseDown(command: Bool, canDrag: Bool) -> Down {
        dragging = false
        if command, canDrag {
            armed = true
            clickFired = false
            return .deferClick
        }
        clickFired = true
        armed = canDrag
        return .clickNow
    }

    public mutating func mouseDragged(distanceSquared: Double) -> Drag {
        guard armed, !dragging, distanceSquared >= Self.dragThresholdSquared else { return .none }
        dragging = true
        armed = false
        return .startDrag
    }

    public mutating func mouseUp() -> Up {
        let fire = armed && !dragging && !clickFired
        reset()
        return fire ? .clickNow : .none
    }

    public mutating func cancel() { reset() }

    private mutating func reset() {
        armed = false
        clickFired = false
        dragging = false
    }
}
