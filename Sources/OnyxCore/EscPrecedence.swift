import Foundation

/// What Esc should do in the current situation, in a fixed order.
/// The app peels one layer per press; returning to reading is last, and only from the editor.
public enum EscAction: String, Equatable, Sendable {
    /// A confirm, sheet, Settings window, or other non-main window owns Esc.
    case passToSheet
    /// An input method is composing; Esc cancels the marked text.
    case passToIME
    /// The wikilink / autocomplete list is open; the text view dismisses it.
    case dismissSuggestions
    /// An inline rename in the file tree.
    case cancelInlineRename
    /// The in-note find bar is open.
    case closeFind
    /// Quick switcher, command palette, graph/atlas overlay, sync log, or move-to picker.
    case dismissOverlay
    /// A multi-selection in the file tree.
    case clearTreeSelection
    case dismissUnpinnedInspector
    case dismissUnpinnedSidebar
    case dismissInspector
    case leaveFocusMode
    /// A non-empty selection or multiple cursors in the editor; collapse to one caret.
    case collapseSelection
    /// Save and show the reader in this pane. Never the other way.
    case returnToReading
    /// Nothing to do: already reading, the setting is off, or the editor is not focused.
    case none
}

/// Snapshot of everything that can claim Esc. Pure, so the order can be unit-tested.
public struct EscSituation: Equatable, Sendable {
    public var sheetOrAlert: Bool
    public var hasMarkedText: Bool
    public var suggestionsVisible: Bool
    public var renaming: Bool
    public var findVisible: Bool
    public var overlayOpen: Bool
    public var treeSelectionConsumes: Bool
    public var unpinnedInspector: Bool
    public var unpinnedSidebar: Bool
    public var inspectorVisible: Bool
    public var focusMode: Bool
    public var editorFocused: Bool
    public var hasSelectionOrMultiCursor: Bool
    public var modeIsEdit: Bool
    public var escReturnsToReading: Bool

    public init(
        sheetOrAlert: Bool = false,
        hasMarkedText: Bool = false,
        suggestionsVisible: Bool = false,
        renaming: Bool = false,
        findVisible: Bool = false,
        overlayOpen: Bool = false,
        treeSelectionConsumes: Bool = false,
        unpinnedInspector: Bool = false,
        unpinnedSidebar: Bool = false,
        inspectorVisible: Bool = false,
        focusMode: Bool = false,
        editorFocused: Bool = false,
        hasSelectionOrMultiCursor: Bool = false,
        modeIsEdit: Bool = false,
        escReturnsToReading: Bool = true
    ) {
        self.sheetOrAlert = sheetOrAlert
        self.hasMarkedText = hasMarkedText
        self.suggestionsVisible = suggestionsVisible
        self.renaming = renaming
        self.findVisible = findVisible
        self.overlayOpen = overlayOpen
        self.treeSelectionConsumes = treeSelectionConsumes
        self.unpinnedInspector = unpinnedInspector
        self.unpinnedSidebar = unpinnedSidebar
        self.inspectorVisible = inspectorVisible
        self.focusMode = focusMode
        self.editorFocused = editorFocused
        self.hasSelectionOrMultiCursor = hasSelectionOrMultiCursor
        self.modeIsEdit = modeIsEdit
        self.escReturnsToReading = escReturnsToReading
    }
}

/// Precedence for Esc, highest first:
/// sheet/alert → IME → autocomplete → inline rename → find bar → overlay (switcher, palette, graph, sync log, version history, move-to)
/// → tree multi-selection → unpinned inspector → unpinned sidebar → docked inspector
/// → focus mode → collapse selection/multi-cursor → return to reading (editor only, setting on).
/// Esc in reading view never switches to editing.
public enum EscPrecedence {
    public static func action(_ s: EscSituation) -> EscAction {
        if s.sheetOrAlert { return .passToSheet }
        if s.hasMarkedText { return .passToIME }
        if s.suggestionsVisible { return .dismissSuggestions }
        if s.renaming { return .cancelInlineRename }
        if s.findVisible { return .closeFind }
        if s.overlayOpen { return .dismissOverlay }
        if s.treeSelectionConsumes { return .clearTreeSelection }
        if s.unpinnedInspector { return .dismissUnpinnedInspector }
        if s.unpinnedSidebar { return .dismissUnpinnedSidebar }
        if s.inspectorVisible { return .dismissInspector }
        if s.focusMode { return .leaveFocusMode }
        if s.editorFocused, s.hasSelectionOrMultiCursor { return .collapseSelection }
        if s.editorFocused, s.modeIsEdit, s.escReturnsToReading { return .returnToReading }
        return .none
    }
}
