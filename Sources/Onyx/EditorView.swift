import AppKit
import SwiftUI
import OnyxCore

/// The writing room: NSTextView on TextKit 1, a centered 760px measure,
/// a warm active-line glow and a colored cursor, as in Reitz Mono.
final class OnyxTextView: NSTextView {
    // AppKit recenters the insertion point on every width change. A pane resize/split is
    // not a caret navigation; keep the viewport under the source-anchor coordinator instead.
    private var sizing = 0   // depth: AppKit nests setFrameSize calls
    override func setFrameSize(_ newSize: NSSize) {
        sizing += 1
        super.setFrameSize(newSize)
        sizing -= 1
    }
    override func scrollToVisible(_ rect: NSRect) -> Bool {
        if sizing > 0 { return false }
        return super.scrollToVisible(rect)
    }

    var onFollowLink: (String) -> Void = { _ in }
    var onExtract: (() -> Void)?
    var onExtractHeading: (() -> Void)?
    var onComposerMenu: ((NSMenu) -> Void)?
    var measure: CGFloat = Theme.editorMeasure
    /// Heading/list folding (EditorFolding.swift): display only, the text is never changed.
    let folds = EditorFolds()
    var applyingFolds = false

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        folds.draw(dirtyRect)
    }

    private var foldTracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = foldTracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: ["onyx": "folds"])
        addTrackingArea(t); foldTracking = t
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        onComposerMenu?(menu)
        return menu
    }

    // Files, images and vault paths dropped or pasted in become attachments (AttachmentDrop.swift).
    var onAttach: (([DroppedItem]) -> [String]?)?
    var vaultRoot: () -> URL? = { nil }
    /// Obsidian's `smartIndentList` (default on): Return continues a list.
    var smartIndentList: () -> Bool = { true }
    /// Obsidian's `autoPairBrackets` / `autoPairMarkdown` (default on).
    var smartPairs: () -> SmartPairs.Settings = { SmartPairs.Settings() }
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] { super.acceptableDragTypes + Self.attachmentDragTypes }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let op = super.draggingEntered(sender)
        return isAttachmentDrag(sender) && op.isEmpty ? attachmentDragOperation(sender) : op
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let op = super.draggingUpdated(sender)
        return isAttachmentDrag(sender) && op.isEmpty ? attachmentDragOperation(sender) : op
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        performAttachmentDrop(sender) || super.performDragOperation(sender)
    }
    override func paste(_ sender: Any?) {
        if !pasteAttachments() { super.paste(sender) }
    }

    @objc func composeExtract() { onExtract?() }
    @objc func composeExtractHeading() { onExtractHeading?() }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let lm = layoutManager, let tc = textContainer, window?.firstResponder === self else { return }
        let sel = selectedRange()
        guard sel.length == 0 else { return }
        let ns = string as NSString
        let lineRange = ns.lineRange(for: NSRange(location: min(sel.location, ns.length), length: 0))
        var glyphs = lm.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
        var r: NSRect
        if glyphs.length == 0 {
            r = lm.extraLineFragmentRect
            if r.isEmpty, sel.location > 0 { glyphs = lm.glyphRange(forCharacterRange: NSRange(location: sel.location - 1, length: 1), actualCharacterRange: nil); r = lm.boundingRect(forGlyphRange: glyphs, in: tc) }
        } else {
            r = lm.boundingRect(forGlyphRange: glyphs, in: tc)
        }
        r.origin.x = 0; r.size.width = bounds.width
        r.origin.y += textContainerOrigin.y
        Theme.activeLine.setFill()
        r.fill()
    }

    override func layout() {
        super.layout()
        let inset = max(36, (bounds.width - measure) / 2)
        if abs(textContainerInset.width - inset) > 0.5 {
            textContainerInset = NSSize(width: inset, height: 96)
        }
    }

    // ⌘-click follows [[links]]; plain click edits.
    override func mouseDown(with event: NSEvent) {
        if !event.modifierFlags.contains(.command), let (region, _) = folds.hit(convert(event.locationInWindow, from: nil)) {
            folds.toggle(region); return   // the chevron or the ⋯ pill: never moves the caret
        }
        if event.modifierFlags.contains(.command), let target = wikilink(at: convert(event.locationInWindow, from: nil)) {
            onFollowLink(target); return
        }
        super.mouseDown(with: event)
    }

    // ⌘-hover over a [[link]] shows the same preview card the reader shows on hover.
    var onPreview: (_ target: String?, _ rect: NSRect) -> Void = { _, _ in }
    private var previewRange: NSRange?
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let p = convert(event.locationInWindow, from: nil)
        folds.mouseMoved(to: p)
        if folds.hoverPart != nil { NSCursor.arrow.set() }
        previewHover(event.modifierFlags, at: convert(event.locationInWindow, from: nil))
    }
    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        guard let w = window else { return }
        previewHover(event.modifierFlags, at: convert(w.mouseLocationOutsideOfEventStream, from: nil))
    }
    override func mouseExited(with event: NSEvent) { super.mouseExited(with: event); endPreviewHover(); folds.mouseExited() }
    func previewHover(_ flags: NSEvent.ModifierFlags, at point: NSPoint) {
        guard flags.contains(.command), bounds.contains(point), let hit = wikilinkHit(at: point) else { endPreviewHover(); return }
        if hit.range == previewRange { return }
        previewRange = hit.range
        guard let lm = layoutManager, let tc = textContainer else { return }
        var r = lm.boundingRect(forGlyphRange: lm.glyphRange(forCharacterRange: hit.range, actualCharacterRange: nil), in: tc)
        r.origin.x += textContainerOrigin.x; r.origin.y += textContainerOrigin.y
        onPreview(hit.target, r)
    }
    func endPreviewHover() {
        guard previewRange != nil else { return }
        previewRange = nil
        onPreview(nil, .zero)
    }

    /// The [[link]] under a point, without side effects.
    func wikilinkHit(at point: NSPoint) -> (target: String, range: NSRange)? {
        guard let lm = layoutManager, let tc = textContainer else { return nil }
        let p = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        var frac: CGFloat = 0
        let g = lm.glyphIndex(for: p, in: tc, fractionOfDistanceThroughGlyph: &frac)
        guard lm.boundingRect(forGlyphRange: NSRange(location: g, length: 1), in: tc).insetBy(dx: -2, dy: -2).contains(p) else { return nil }
        let idx = lm.characterIndexForGlyph(at: g)
        let ns = string as NSString
        guard idx < ns.length else { return nil }
        let lr = ns.lineRange(for: NSRange(location: idx, length: 0))
        for l in NoteParser.parseWikiLinks(string, in: lr) where NSLocationInRange(idx, l.range) {
            return (l.target + (l.heading.map { "#" + $0 } ?? ""), l.range)
        }
        return nil
    }

    func wikilink(at point: NSPoint) -> String? {
        let idx = characterIndexForInsertion(at: point)
        let ns = string as NSString
        guard idx <= ns.length else { return nil }
        let lr = ns.lineRange(for: NSRange(location: min(idx, max(0, ns.length - 1)), length: 0))
        for l in NoteParser.parseWikiLinks(string, in: lr) where NSLocationInRange(idx, l.range) || NSMaxRange(l.range) == idx {
            return l.target + (l.heading.map { "#" + $0 } ?? "")
        }
        if let m = MarkdownHighlighter.url.matches(in: string, range: lr).first(where: { NSLocationInRange(idx, $0.range) }), let u = URL(string: ns.substring(with: m.range)) {
            NSWorkspace.shared.open(u); return nil
        }
        // [text](file.pdf) / ![](img.png): local Markdown links follow like wikilinks
        if let t = MarkdownLinkHit.target(in: ns.substring(with: lr), at: idx - lr.location) { return t }
        return nil
    }

    // MARK: Wikilink suggestions
    //
    // Typing `[[` pairs to `[[]]` and shows a quiet list under the link. The list never edits
    // the text by itself: every keystroke goes into the note and only filters. ↑/↓ highlight
    // (nothing is highlighted until you do, unless the top match is exact); ↩/⇥ take the
    // highlighted row, or with nothing highlighted keep what you typed and step past `]]`;
    // Esc closes it; typing `]]` or moving the caret out of the link closes it too.
    // After `#` it lists that note's headings; after `|` (alias) and `#^` (block) it stays away.

    var suggest: (LinkCompletion.Part, String) -> [LinkSuggestion] = { _, _ in [] }
    // The same list for `key::` lines (FieldCompletion): keys after `word:`, notes after `key:: `.
    var fieldSuggest: (FieldCompletion.Part, String) -> [LinkSuggestion] = { _, _ in [] }
    private var fieldCtx: FieldCompletion.Context?
    private var fieldLineStart = 0
    private var dismissedFieldLine: Int?
    private lazy var panel = LinkSuggestPanel()
    private var linkCtx: LinkCompletion.Context?
    private var linkLineStart = 0
    private var dismissedOpen: Int?       // absolute offset of the `[[` Esc closed
    private var lastQuery: String?
    private var refreshing = false

    var suggestionsVisible: Bool { panel.isVisible }

    /// First Esc with a selection or several ranges: one caret at the end of the primary range.
    func collapseSelectionOrCursors() {
        let ranges = selectedRanges.map { $0.rangeValue }
        let r = ranges.first ?? selectedRange()
        setSelectedRange(NSRange(location: NSMaxRange(r), length: 0))
    }

    func hideSuggestions() { panel.hide(); linkCtx = nil; fieldCtx = nil; lastQuery = nil }

    func refreshSuggestions() {
        guard !refreshing else { return }
        refreshing = true; defer { refreshing = false }
        let sel = selectedRange()
        guard isEditable, sel.length == 0, window != nil, !hasMarkedText() else { hideSuggestions(); return }
        let ns = string as NSString
        let lr = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        let line = ns.substring(with: NSRange(location: lr.location, length: max(0, NSMaxRange(lr) - lr.location)))
        guard let c = LinkCompletion.context(line: line, caret: sel.location - lr.location) else {
            dismissedOpen = nil
            refreshFieldSuggestions(line: line, lineStart: lr.location, caret: sel.location - lr.location)
            return
        }
        fieldCtx = nil
        let absOpen = lr.location + c.open
        if let d = dismissedOpen, d != absOpen { dismissedOpen = nil }
        guard dismissedOpen == nil else { hideSuggestions(); return }
        switch c.part { case .alias, .block: hideSuggestions(); return; default: break }
        let items = suggest(c.part, c.query)
        guard !items.isEmpty else { hideSuggestions(); return }
        let m = panel.model
        let queryChanged = c.query != lastQuery || linkCtx?.open != c.open || linkLineStart != lr.location
        m.items = items
        if queryChanged || (m.highlighted ?? 0) >= items.count {
            m.highlighted = LinkCompletion.defaultHighlight(topIsExact: items[0].exact)
        }
        m.onPick = { [weak self] i in self?.acceptSuggestion(i) }
        linkCtx = c; linkLineStart = lr.location; lastQuery = c.query
        let anchor = firstRect(forCharacterRange: NSRange(location: absOpen, length: 2), actualRange: nil)
        if let w = window, anchor != .zero { panel.show(below: anchor, parent: w) }
        if ProcessInfo.processInfo.environment["ONYX_DEBUG"] != nil {
            FileHandle.standardError.write("[suggest] q=\"\(c.query)\" part=\(c.part) n=\(items.count) hl=\(m.highlighted.map(String.init) ?? "-") top=\(items[0].title)\n".data(using: .utf8)!)
        }
    }

    private func refreshFieldSuggestions(line: String, lineStart: Int, caret: Int) {
        guard let fc = FieldCompletion.context(line: line, caret: caret),
              lineStart >= Frontmatter.parse(string).bodyOffset else {
            dismissedFieldLine = nil; hideSuggestions(); return
        }
        if let d = dismissedFieldLine {
            if d == lineStart { hideSuggestions(); return }
            dismissedFieldLine = nil
        }
        let items = fieldSuggest(fc.part, fc.query)
        guard !items.isEmpty else { hideSuggestions(); return }
        let m = panel.model
        let queryChanged = fc.query != lastQuery || fieldCtx?.part != fc.part || fieldLineStart != lineStart
        m.items = items
        if queryChanged || (m.highlighted ?? 0) >= items.count {
            m.highlighted = LinkCompletion.defaultHighlight(topIsExact: items[0].exact)
        }
        m.onPick = { [weak self] i in self?.acceptSuggestion(i) }
        linkCtx = nil; fieldCtx = fc; fieldLineStart = lineStart; lastQuery = fc.query
        let at = lineStart + max(0, fc.queryStart - (fc.query.isEmpty ? 1 : 0))
        let anchor = firstRect(forCharacterRange: NSRange(location: at, length: 1), actualRange: nil)
        if let w = window, anchor != .zero { panel.show(below: anchor, parent: w) }
    }

    private func acceptField(_ i: Int) {
        guard let fc = fieldCtx, panel.model.items.indices.contains(i) else { return }
        let item = panel.model.items[i]
        let from = fieldLineStart + fc.queryStart
        let to = max(from, selectedRange().location)
        hideSuggestions()
        insertText(item.insert, replacementRange: NSRange(location: from, length: to - from))
    }

    func acceptSuggestion(_ i: Int) {
        if linkCtx == nil, fieldCtx != nil { acceptField(i); return }
        guard let c = linkCtx, panel.model.items.indices.contains(i) else { return }
        let item = panel.model.items[i]
        let ns = string as NSString
        let from = linkLineStart + c.queryStart
        // replace the whole segment the caret is in (to the next ] | # on the line)
        var to = selectedRange().location
        while to < ns.length, let ch = UnicodeScalar(ns.character(at: to)), !"]|#\n".unicodeScalars.contains(ch) { to += 1 }
        hideSuggestions()
        insertText(item.insert, replacementRange: NSRange(location: from, length: to - from))
        let ns2 = string as NSString
        let end = selectedRange().location
        let next = end < ns2.length ? ns2.substring(with: NSRange(location: end, length: 1)) : ""
        if end + 2 <= ns2.length, ns2.substring(with: NSRange(location: end, length: 2)) == "]]" {
            setSelectedRange(NSRange(location: end + 2, length: 0))
        } else if next != "#" && next != "|" {
            insertText("]]", replacementRange: selectedRange())
        }
        hideSuggestions()
    }

    /// ↩/⇥ with nothing highlighted: keep what was typed, step past the closing `]]`.
    private func leaveLink() {
        hideSuggestions()
        let ns = string as NSString
        var i = selectedRange().location
        while i < ns.length, let ch = UnicodeScalar(ns.character(at: i)), ch != "]", ch != "\n" { i += 1 }
        if i + 2 <= ns.length, ns.substring(with: NSRange(location: i, length: 2)) == "]]" {
            setSelectedRange(NSRange(location: i + 2, length: 0))
        } else {
            setSelectedRange(NSRange(location: i, length: 0))
            insertText("]]", replacementRange: selectedRange())
        }
    }

    override func didChangeText() {
        super.didChangeText()
        refreshSuggestions()
        DispatchQueue.main.async { [weak self] in self?.refreshSuggestions() }
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        // Carets never live inside folded text: navigation steps over it, Find/outline/undo open it.
        let ranges = folds.adjust(ranges, stillSelecting: stillSelecting)
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        needsDisplay = true
        if !stillSelecting, panel.isVisible || linkCtx != nil || fieldCtx != nil { DispatchQueue.main.async { [weak self] in self?.refreshSuggestions() } }
    }

    /// Apply a core `TextEdit` as one undoable change. When smart lists are on,
    /// also renumbers nearby ordered lists in the same step.
    @discardableResult
    func apply(_ e: TextEdit) -> Bool {
        let e = smartIndentList() ? ListRenumber.applying(e, to: string) : e
        guard shouldChangeText(in: e.range, replacementString: e.replacement) else { return false }
        textStorage?.replaceCharacters(in: e.range, with: e.replacement)
        didChangeText()
        setSelectedRange(e.selection)
        scrollRangeToVisible(e.selection)
        return true
    }

    func apply(_ action: SmartPairsAction) {
        switch action {
        case .replace(let e): apply(e)
        case .move(let r): setSelectedRange(r); scrollRangeToVisible(r)
        }
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        if !hasMarkedText(), let typed = insertString as? String {
            let range = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
            if let action = SmartPairs.insert(string, range, typed: typed, settings: smartPairs()) {
                apply(action); return
            }
        }
        super.insertText(insertString, replacementRange: replacementRange)
    }

    override func deleteBackward(_ sender: Any?) {
        if !hasMarkedText(), let e = SmartPairs.deleteBackward(string, selectedRange(), settings: smartPairs()) {
            apply(e); return
        }
        super.deleteBackward(sender)
    }

    /// Backspace, Delete, ⌘⌫, cut, and the other text-delete selectors: if the
    /// deletion leaves a numbered list out of order, fix it in the same undo group.
    override func doCommand(by selector: Selector) {
        if smartIndentList(), !hasMarkedText(), Self.deleteSelectors.contains(NSStringFromSelector(selector)) {
            renumberAfterDelete { super.doCommand(by: selector) }
            return
        }
        super.doCommand(by: selector)
    }

    override func cut(_ sender: Any?) {
        if smartIndentList(), !hasMarkedText() {
            renumberAfterDelete { super.cut(sender) }
            return
        }
        super.cut(sender)
    }

    private static let deleteSelectors: Set<String> = [
        "deleteBackward:", "deleteForward:",
        "deleteWordBackward:", "deleteWordForward:",
        "deleteToBeginningOfLine:", "deleteToEndOfLine:",
        "deleteToBeginningOfParagraph:", "deleteToEndOfParagraph:",
        "deleteBackwardByDecomposingPreviousCharacter:", "delete:",
    ]

    private func renumberAfterDelete(_ body: () -> Void) {
        let um = undoManager
        let before = string
        um?.beginUndoGrouping()
        body()
        if let e = ListRenumber.afterChange(string, selection: selectedRange(), from: before) {
            apply(e)
        }
        um?.endUndoGrouping()
    }

    override func insertNewline(_ sender: Any?) {
        // IME composition and Shift-Return get a plain newline.
        if !hasMarkedText(), smartIndentList(),
           !(NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false),
           let e = ListContinue.newline(string, selectedRange()) {
            apply(e); return
        }
        super.insertNewline(sender)
    }

    override func insertTab(_ sender: Any?) {
        if !hasMarkedText(), ListContinue.isListSelection(string, selectedRange()) {
            apply(EditCommands.indent(string, selectedRange())); return
        }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        if !hasMarkedText(), ListContinue.isListSelection(string, selectedRange()) {
            apply(EditCommands.outdent(string, selectedRange())); return
        }
        super.insertBacktab(sender)
    }

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .option, .control])
        // No matching rows is still a valid link. ↩/⇥ leaves the typed name untouched.
        if mods.isEmpty, [36, 76, 48].contains(event.keyCode), !event.modifierFlags.contains(.shift), !panel.isVisible {
            let ns = string as NSString, sel = selectedRange()
            let lr = ns.lineRange(for: sel)
            if sel.length == 0, LinkCompletion.context(line: ns.substring(with: lr), caret: sel.location - lr.location) != nil {
                leaveLink(); return
            }
        }
        if panel.isVisible {
            if !mods.isEmpty { hideSuggestions(); baseKeyDown(event); return }
            let m = panel.model
            switch event.keyCode {
            case 125: m.highlighted = LinkCompletion.move(m.highlighted, by: 1, count: m.items.count); return   // ↓
            case 126: m.highlighted = LinkCompletion.move(m.highlighted, by: -1, count: m.items.count); return  // ↑
            default: break
            }
            let key: LinkCompletion.Key = switch event.keyCode {
                case 36, 76: .returnKey
                case 48: event.modifierFlags.contains(.shift) ? .other : .tab
                case 53: .escape
                default: .other
            }
            switch LinkCompletion.action(for: key, highlighted: m.highlighted) {
            case .accept(let i): acceptSuggestion(i); return
            case .leave:
                if fieldCtx != nil { hideSuggestions(); break }   // a field line: the key does its usual thing
                leaveLink(); return
            case .dismiss:
                if fieldCtx != nil { dismissedFieldLine = fieldLineStart }
                else if let c = linkCtx { dismissedOpen = linkLineStart + c.open }
                hideSuggestions(); return
            case .pass: break
            }
        }
        baseKeyDown(event)
    }

    /// Test harness only (ONYX_TYPE_TEST): a non-key window has no active input context, so
    /// do what the key bindings would, directly.
    var directKeys = false
    private func baseKeyDown(_ e: NSEvent) {
        guard directKeys else { super.keyDown(with: e); return }
        let cmd = e.modifierFlags.contains(.command)
        switch e.keyCode {
        case 36: insertNewline(nil)
        case 48: insertTab(nil)
        case 53: cancelOperation(nil)
        case 123: moveLeft(nil)
        case 124: moveRight(nil)
        case 125: cmd ? moveToEndOfDocument(nil) : moveDown(nil)
        case 126: cmd ? moveToBeginningOfDocument(nil) : moveUp(nil)
        default: if let c = e.characters, !c.isEmpty, !cmd { insertText(c, replacementRange: selectedRange()) }
        }
    }

    override func scrollWheel(with event: NSEvent) { if panel.isVisible { hideSuggestions() }; super.scrollWheel(with: event) }
    override func resignFirstResponder() -> Bool { hideSuggestions(); return super.resignFirstResponder() }
    override func viewWillMove(toWindow newWindow: NSWindow?) { if newWindow == nil { hideSuggestions() }; super.viewWillMove(toWindow: newWindow) }
}

struct EditorView: NSViewRepresentable {
    @Bindable var ws: Workspace
    var fontSize: Double = 14
    var measure: Double = 41
    @AppStorage(Typeset.face) private var typeface = "lm"
    /// Set for an unfocused split pane: show this note, read-only until the pane is focused.
    var source: (path: String?, text: String)? = nil
    /// The split pane this view belongs to when unfocused (nil = the focused pane).
    var paneID: UUID? = nil
    @Environment(\.colorScheme) var scheme

    var path: String? { source == nil ? ws.currentPath : source!.path }
    var text: String { source?.text ?? ws.text }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        storage.delegate = context.coordinator   // tracks what each keystroke changed (partial restyle)
        let lm = FoldLayoutManager()
        storage.addLayoutManager(lm)
        let tc = NSTextContainer(size: NSSize(width: Theme.editorMeasure, height: .greatestFiniteMagnitude))
        tc.widthTracksTextView = true
        lm.addTextContainer(tc)
        let tv = OnyxTextView(frame: .zero, textContainer: tc)
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = EditorPrefs.spellcheckOn   // Format ▸ Toggle Spellcheck, Settings ▸ Editor
        tv.smartInsertDeleteEnabled = false
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.drawsBackground = true
        tv.backgroundColor = Theme.paper
        tv.insertionPointColor = Theme.cursor
        tv.selectedTextAttributes = [.backgroundColor: Theme.selection]
        tv.typingAttributes = MarkdownHighlighter().baseAttributes
        tv.autoresizingMask = [.width]
        tv.isVerticallyResizable = true
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        tv.textContainerInset = NSSize(width: 80, height: 96)
        tv.delegate = context.coordinator
        tv.folds.attach(tv)
        tv.folds.onChange = { [weak ws] p in ws?.editorFoldsChanged(p) }
        tv.suggest = { [weak ws] part, q in ws?.linkSuggestions(part, q) ?? [] }
        tv.fieldSuggest = { [weak ws] part, q in ws?.fieldSuggestions(part, q) ?? [] }
        tv.onFollowLink = { [weak ws] t in GraphPreviewController.shared.close(); ws?.openLink(t) }
        tv.onExtract = { [weak ws] in ws?.beginExtract() }
        tv.vaultRoot = { [weak ws] in ws?.root }
        tv.smartIndentList = { [weak ws] in
            (ws?.obsidianJSON("app.json") as? [String: Any])?["smartIndentList"] as? Bool ?? true
        }
        tv.smartPairs = { [weak ws] in
            SmartPairs.Settings.from(appJSON: ws?.obsidianJSON("app.json") as? [String: Any])
        }
        tv.onAttach = { [weak ws, weak c = context.coordinator] items in ws?.attachmentLinks(items, note: c?.parent.path) }
        tv.onExtractHeading = { [weak ws] in ws?.beginExtract(heading: true) }
        tv.onComposerMenu = { [weak tv] menu in
            guard let tv, tv.isEditable else { return }
            let sel = tv.selectedRange()
            let hasSel = sel.length > 0
            let inHeading = NoteComposer.headingSection(in: tv.string, at: sel.location) != nil
            guard hasSel || inHeading else { return }
            menu.addItem(.separator())
            if hasSel {
                let item = NSMenuItem(title: CommandCatalog.title("extract"), action: #selector(OnyxTextView.composeExtract), keyEquivalent: "")
                item.target = tv
                menu.addItem(item)
            }
            if inHeading {
                let item = NSMenuItem(title: CommandCatalog.title("extractheading"), action: #selector(OnyxTextView.composeExtractHeading), keyEquivalent: "")
                item.target = tv
                menu.addItem(item)
            }
        }
        tv.onPreview = { [weak ws, weak tv] t, rect in
            guard let ws, let tv else { return }
            guard let t else { GraphPreviewController.shared.leaveLink(); return }
            let parts = t.split(separator: "#", maxSplits: 1).map(String.init)
            let name = parts.first ?? ""
            guard let p = name.isEmpty ? ws.currentPath : ws.snapshot?.resolve(name, from: ws.currentPath) else { return }
            GraphPreviewController.shared.schedule(ws: ws, path: p, rect: rect, in: tv, mode: nil, heading: parts.count > 1 ? parts[1] : nil)
        }

        let scroll = ThinScrollView()
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        ThinScroller.install(on: scroll)
        scroll.drawsBackground = true
        scroll.backgroundColor = Theme.paper
        scroll.automaticallyAdjustsContentInsets = false
        context.coordinator.textView = tv
        context.coordinator.load(text)
        context.coordinator.loadedPath = path
        tv.isEditable = source == nil
        context.coordinator.wasLive = source == nil
        if source == nil { DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) } }
        // Open where this pane was (⌘↩ from the reader, or a fresh split), then report as it scrolls.
        let c = context.coordinator
        let start = ws.initialTop(paneID)
        scroll.contentView.postsBoundsChangedNotifications = true
        scroll.onResize = { [weak c] in c?.holdAnchor() }
        c.scrollHandled = ws.scrollRequest?.id   // a new view opens at initialTop; don't replay old requests
        c.anchor = start
        NotificationCenter.default.addObserver(c, selector: #selector(Coordinator.scrolled), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        if start > 0 {
            c.restoring = true
            c.restore(start, caret: source == nil, tries: 30)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.parent = self
        guard let tv = c.textView else { return }
        let live = source == nil
        if tv.isEditable != live { tv.isEditable = live }
        if live { ws.liveEditor = tv }
        if live && !c.wasLive { DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) } }
        c.wasLive = live
        if c.loadedToken != ws.renderToken || (tv.string != text && !c.isEditing) {
            c.loadedToken = ws.renderToken
            if tv.string != text { c.load(text, keepSelection: c.loadedPath == path) }
            c.loadedPath = path
        }
        // back/forward: land where you were (after any reload above)
        if live, let r = ws.scrollRequest, r.id != c.scrollHandled {
            c.scrollHandled = r.id
            c.anchor = r.line
            c.restoring = true
            c.restore(r.line, caret: true, tries: 30)
        }
        if live, let line = ws.editorJump {
            DispatchQueue.main.async { c.reveal(line: line); ws.editorJump = nil }
        }
        if c.scheme != scheme { c.scheme = scheme; c.rehighlight() }
        let tk = "\(fontSize)/\(measure)/\(typeface)"
        if c.typeKey != tk {
            if !c.typeKey.isEmpty { c.rehighlight() }
            c.typeKey = tk
            tv.measure = Theme.editorMeasure
            tv.typingAttributes = MarkdownHighlighter().baseAttributes
            tv.needsLayout = true
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate {
        var parent: EditorView
        weak var textView: OnyxTextView?
        var loadedToken = -1
        var loadedPath: String?
        var isEditing = false
        var wasLive = true
        var scheme: ColorScheme?
        var typeKey = ""
        var restoring = false
        var anchor: Double = 0   // last position the writer chose (scroll or restore)
        var scrollHandled: Int?
        private var reportQueued = false
        private var highlighter: MarkdownHighlighter { MarkdownHighlighter() }
        /// The styled text's shape and the one character edit since, for restyling just its lines.
        private var shape: MarkdownHighlighter.Shape?
        private var pendingEdit: MarkdownHighlighter.Edit?
        private var editsSinceStyle = 0

        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters) else { return }
            editsSinceStyle += 1
            pendingEdit = MarkdownHighlighter.Edit(range: editedRange, delta: delta)
        }

        /// Restyle after a change: only the edited lines when exactly one edit happened and the
        /// highlighter agrees it was local; everything otherwise.
        private func restyle(_ ts: NSTextStorage, full: Bool) {
            let edit = !full && editsSinceStyle == 1 ? pendingEdit : nil
            shape = highlighter.apply(to: ts, edit: edit, previous: edit == nil ? nil : shape)
            pendingEdit = nil; editsSinceStyle = 0
        }

        init(_ p: EditorView) { parent = p }

        func load(_ text: String, keepSelection: Bool = false) {
            guard let tv = textView, let ts = tv.textStorage else { return }
            let sel = tv.selectedRange()
            let visible = tv.enclosingScrollView?.contentView.bounds.origin
            tv.folds.loading = true
            ts.setAttributedString(NSAttributedString(string: text, attributes: highlighter.baseAttributes))
            tv.folds.loading = false
            restyle(ts, full: true)
            if keepSelection {
                tv.setSelectedRange(NSRange(location: min(sel.location, (text as NSString).length), length: 0))
                if let v = visible { tv.enclosingScrollView?.contentView.scroll(to: v) }
            } else {
                tv.setSelectedRange(NSRange(location: initialCursor(text), length: 0))
                tv.scroll(.zero)
            }
            tv.undoManager?.removeAllActions()
            tv.folds.restore(path: parent.path, store: FoldStores.store(for: parent.ws.root))
        }

        /// Edits that would change folded text (or pull the next line into a fold) open it first.
        func textView(_ textView: NSTextView, shouldChangeTextInRanges ranges: [NSValue], replacementStrings: [String]?) -> Bool {
            (textView as? OnyxTextView)?.folds.revealForEdit(ranges.map(\.rangeValue))
            return true
        }

        /// Start writing below the frontmatter and title, like opening a notebook to the page.
        func initialCursor(_ text: String) -> Int {
            (text as NSString).length
        }

        func rehighlight() {
            guard let ts = textView?.textStorage else { return }
            restyle(ts, full: true)
            textView?.needsDisplay = true
        }

        /// Distance below the visible top that counts as "where you are": just under the title line.
        static let anchorY: CGFloat = 48

        private func lineStart(_ line: Int, in ns: NSString) -> Int {
            var loc = 0
            for _ in 0..<max(0, line) {
                let r = ns.lineRange(for: NSRange(location: loc, length: 0))
                if NSMaxRange(r) >= ns.length { return ns.length }
                loc = NSMaxRange(r)
            }
            return loc
        }

        /// Fractional source line at the anchor: the line index plus how far down its
        /// (possibly soft-wrapped) paragraph the anchor sits.
        func topLine() -> Double? {
            guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer,
                  let clip = tv.enclosingScrollView?.contentView else { return nil }
            let ns = tv.string as NSString
            guard ns.length > 0 else { return 0 }
            let y = clip.bounds.minY + Self.anchorY - tv.textContainerOrigin.y
            if y <= 0 { return 0 }
            let g = lm.glyphIndex(for: NSPoint(x: 0, y: y), in: tc)
            let ch = min(lm.characterIndexForGlyph(at: g), ns.length - 1)
            let lr = ns.lineRange(for: NSRange(location: ch, length: 0))
            var line = 0
            ns.enumerateSubstrings(in: NSRange(location: 0, length: lr.location), options: [.byLines, .substringNotRequired]) { _, _, _, _ in line += 1 }
            let rect = lm.boundingRect(forGlyphRange: lm.glyphRange(forCharacterRange: lr, actualCharacterRange: nil), in: tc)
            let frac = rect.height > 0 ? min(max((y - rect.minY) / rect.height, 0), 0.999) : 0
            return Double(line) + Double(frac)
        }

        func scrollTo(line: Double, caret: Bool) {
            guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer,
                  let scroll = tv.enclosingScrollView else { return }
            let ns = tv.string as NSString
            let loc = lineStart(Int(line), in: ns)
            let lr = ns.lineRange(for: NSRange(location: loc, length: 0))
            lm.ensureLayout(forCharacterRange: NSRange(location: 0, length: NSMaxRange(lr)))
            let rect = lm.boundingRect(forGlyphRange: lm.glyphRange(forCharacterRange: lr, actualCharacterRange: nil), in: tc)
            let frac = CGFloat(line - line.rounded(.down))
            let maxY = max(0, tv.frame.height - scroll.contentView.bounds.height)
            let y = min(max(0, rect.minY + frac * rect.height + tv.textContainerOrigin.y - Self.anchorY), maxY)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
            if caret { tv.setSelectedRange(NSRange(location: loc, length: 0)) }
        }

        /// Wait for the scroll view to get a real size (SwiftUI lays it out after creation).
        func restore(_ line: Double, caret: Bool, tries: Int) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { [weak self] in
                guard let self, let tv = self.textView, let clip = tv.enclosingScrollView?.contentView else { return }
                if clip.bounds.height < 1 || tv.frame.width < 1, tries > 0 { return self.restore(line, caret: caret, tries: tries - 1) }
                tv.layoutManager?.ensureLayout(for: tv.textContainer!)
                self.scrollTo(line: line, caret: caret)
                if tries > 0 { return self.restore(line, caret: false, tries: tries - 1) }
                self.restoring = false
                if let t = self.topLine() { self.parent.ws.reportTop(self.parent.paneID, t) }
            }
        }

        func holdAnchor() {
            guard anchor > 0, textView != nil else { return }
            let was = restoring
            restoring = true
            scrollTo(line: anchor, caret: false)
            restoring = was
        }

        @objc func scrolled(_ n: Notification) {
            if (textView?.enclosingScrollView as? ThinScrollView)?.resizing ?? 0 > 0 { return }
            guard !restoring, !reportQueued else { return }
            reportQueued = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.reportQueued = false
                if !self.restoring, let t = self.topLine() { self.anchor = t; self.parent.ws.reportTop(self.parent.paneID, t) }
            }
        }

        func reveal(line: Int) {
            guard let tv = textView else { return }
            let ns = tv.string as NSString
            var loc = 0
            for _ in 0..<line { let r = ns.lineRange(for: NSRange(location: loc, length: 0)); loc = NSMaxRange(r); if loc >= ns.length { break } }
            tv.setSelectedRange(NSRange(location: min(loc, ns.length), length: 0))
            tv.scrollRangeToVisible(NSRange(location: min(loc, ns.length), length: 0))
            tv.showFindIndicator(for: ns.lineRange(for: NSRange(location: min(loc, ns.length), length: 0)))
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView, let ts = tv.textStorage else { return }
            isEditing = true
            restyle(ts, full: false)
            if parent.source == nil { parent.ws.text = tv.string }
            isEditing = false
            if parent.source == nil, parent.ws.finder.visible, parent.ws.mode == .edit {   // keep the count and marks true while typing
                let ws = parent.ws
                DispatchQueue.main.async { ws.runFind(reveal: false, fromCaret: false) }
            }
        }
    }
}
