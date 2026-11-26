import AppKit
import SwiftUI
import OnyxCore

enum EditorPrefs {
    static let spellcheck = "onyx.spellcheck"     // continuous spellcheck in the editor; default on
    static var spellcheckOn: Bool { UserDefaults.standard.object(forKey: spellcheck) as? Bool ?? true }
}

/// The Obsidian-style editing, file, and view commands that live in the palette, the menus,
/// and Settings ▸ Shortcuts. The text transforms themselves are in OnyxCore/EditCommands.
extension Workspace {

    // MARK: Editing

    /// Run a transform on the live editor and apply it as one undoable change. From the reader,
    /// switch to editing first.
    func applyEdit(retry: Bool = true, _ f: @escaping (String, NSRange) -> TextEdit?) {
        guard currentPath != nil, !isCanvas, !isBase, !isFile else { NSSound.beep(); return }
        if mode != .edit {
            guard retry else { NSSound.beep(); return }
            withAnimation(Motion.fade) { mode = .edit }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.applyEdit(retry: false, f) }
            return
        }
        guard let tv = (MainWindow.current?.firstResponder as? OnyxTextView) ?? liveEditor, tv.isEditable else { NSSound.beep(); return }
        guard let e = f(tv.string, tv.selectedRange()) else { NSSound.beep(); return }
        _ = tv.apply(e)
        DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
    }

    func wrap(_ open: String, _ close: String? = nil) { applyEdit { EditCommands.toggleWrap($0, $1, open: open, close: close) } }

    func insertNow(_ format: String) {
        let f = DateFormatter(); f.dateFormat = format
        let s = f.string(from: Date())
        applyEdit { EditCommands.insert($0, $1, s) }
    }

    /// Insert now in a moment.js format (Templates' date and time formats, like Obsidian's insert commands).
    func insertMoment(_ format: String) {
        let s = MomentFormat.format(Date(), format)
        applyEdit { EditCommands.insert($0, $1, s) }
    }

    /// Run an editing command by catalog id. Returns false for ids that aren't editing commands.
    @discardableResult
    func runEditCommand(_ id: String) -> Bool {
        switch id {
        case "bold": applyEdit { EditCommands.toggleBold($0, $1) }
        case "italic": applyEdit { EditCommands.toggleItalic($0, $1) }
        case "strike": wrap("~~")
        case "highlight": wrap("==")
        case "inlinecode": wrap("`")
        case "comment": wrap("%%")
        case "wikilink": applyEdit { EditCommands.insertWikilink($0, $1) }
        case "mdlink": applyEdit { EditCommands.insertMarkdownLink($0, $1) }
        case "bullet": applyEdit { EditCommands.toggleLines($0, $1, .bullet) }
        case "numbered": applyEdit { EditCommands.toggleLines($0, $1, .numbered) }
        case "checklist": applyEdit { EditCommands.toggleLines($0, $1, .checklist) }
        case "checkbox": applyEdit { EditCommands.cycleCheckbox($0, $1) }
        case "quote": applyEdit { EditCommands.toggleLines($0, $1, .quote) }
        case "callout": applyEdit { EditCommands.callout($0, $1) }
        case "hr": applyEdit { EditCommands.horizontalRule($0, $1) }
        case "table": applyEdit { EditCommands.table($0, $1) }
        case "codeblock": applyEdit { EditCommands.codeBlock($0, $1) }
        case "date": insertMoment(templateSettings.dateFormat)
        case "time": insertMoment(templateSettings.timeFormat)
        case "indent": applyEdit { EditCommands.indent($0, $1) }
        case "outdent": applyEdit { EditCommands.outdent($0, $1) }
        case "lineup": applyEdit { EditCommands.moveLines($0, $1, up: true) }
        case "linedown": applyEdit { EditCommands.moveLines($0, $1, up: false) }
        case "dupline": applyEdit { EditCommands.duplicateLines($0, $1) }
        case "delline": applyEdit { EditCommands.deleteLines($0, $1) }
        default:
            if id.count == 2, id.hasPrefix("h"), let n = Int(id.dropFirst()), (1...6).contains(n) {
                applyEdit { EditCommands.heading($0, $1, level: n) }
            } else { return false }
        }
        return true
    }

    /// Catalog ids of the Format commands, in menu order (nil = divider).
    static let formatMenu: [String?] = [
        "bold", "italic", "strike", "highlight", "inlinecode", "comment", nil,
        "wikilink", "mdlink", nil,
        "h1", "h2", "h3", "h4", "h5", "h6", nil,
        "bullet", "numbered", "checklist", "checkbox", "quote", "indent", "outdent", nil,
        "callout", "codeblock", "table", "hr", "date", "time", nil,
        "lineup", "linedown", "dupline", "delline",
    ]

    // MARK: Navigation

    /// Open the daily note for today + `days` by the calendar (not the next existing one).
    func openDaily(days: Int) {
        guard snapshot != nil else { return }
        let date = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        let path = DailyNotes.path(for: date, settings: daily)
        if snapshot?.notes[path] == nil { _ = write(dailyNoteText(for: date, path: path), to: path, create: true) }
        openNote(path)
        mode = .edit
    }

    /// Headings of the open note, from the live text.
    var liveHeadings: [Heading] { NoteParser.summarize(text).headings }

    func jumpToHeading(_ i: Int) {
        let hs = liveHeadings
        guard hs.indices.contains(i) else { return }
        readerJump = i; editorJump = hs[i].line
    }

    /// Show the open note in the file tree: dock the sidebar on Files, expand, scroll to it.
    func revealInSidebar() {
        guard let p = currentPath else { return }
        withAnimation(Motion.layout) {
            focusMode = false
            sidebarTab = .files
            if !sidebarVisible || !sidebarPinned {
                sidebarVisible = true; sidebarPinned = true
                UserDefaults.standard.set(true, forKey: "onyx.sidebarOpen")
            }
            for parent in TreeReveal.ancestors(of: p) { expanded.insert(parent) }
            selectedFolder = nil
        }
        revealToken += 1
    }

    func searchVault(_ q: String? = nil) {
        if let q { searchQuery = q }
        sidebarTab = .search
        if !sidebarVisible { toggleSidebar() }
        focusSearch += 1
    }

    /// Search the vault for the editor selection (or the word at the caret).
    func searchSelection() {
        guard let tv = (MainWindow.current?.firstResponder as? OnyxTextView) ?? liveEditor else { searchVault(); return }
        let ns = tv.string as NSString
        var r = tv.selectedRange()
        if r.length == 0, r.location != NSNotFound, r.location <= ns.length { r = tv.selectionRange(forProposedRange: r, granularity: .selectByWord) }
        guard r.location != NSNotFound, NSMaxRange(r) <= ns.length else { searchVault(); return }
        let s = ns.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
        searchVault(s.isEmpty ? nil : s)
    }

    // MARK: Files

    func newNoteInPane() { split(.vertical); newNote() }

    /// Copy the open note next to itself as “Name 2.md” and open the copy.
    func duplicateCurrent() {
        guard let p = currentPath, !isCanvas, !isBase, !isFile else { NSSound.beep(); return }
        flushSave()
        let base = String(p.dropLast(3))
        var n = 2, dest = "\(base) \(n).md"
        while snapshot?.notes[dest] != nil || FileManager.default.fileExists(atPath: root?.appendingPathComponent(dest).path ?? "") {
            n += 1; dest = "\(base) \(n).md"
        }
        guard write(text, to: dest, create: true) else { toast = "Couldn’t duplicate"; return }
        openNote(dest)
        toast = "Duplicated as \(((dest as NSString).lastPathComponent as NSString).deletingPathExtension)"
    }

    func copyFilePath() { if let p = currentPath { copyFilePath(p) } }
    func copyFilePath(_ p: String) {
        guard let root else { return }
        let full = root.appendingPathComponent(p).path
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(full, forType: .string)
        toast = "Copied path"
    }

    func openInDefaultApp() {
        guard let p = currentPath, let root else { return }
        flushSave()
        NSWorkspace.shared.open(root.appendingPathComponent(p))
    }

    // MARK: View

    /// ⌘= / ⌘- / ⌘0: editor and reader text size together (the same prefs as Settings).
    func zoom(_ step: Int) {
        let d = UserDefaults.standard
        if step == 0 {
            d.set(14.0, forKey: Prefs.editorSize); d.set(19.0, forKey: Prefs.readerSize)
            toast = "Text size reset"; return
        }
        let e = min(22, max(11, (d.object(forKey: Prefs.editorSize) as? Double ?? 14) + Double(step)))
        let r = min(26, max(15, (d.object(forKey: Prefs.readerSize) as? Double ?? 19) + Double(step)))
        d.set(e, forKey: Prefs.editorSize); d.set(r, forKey: Prefs.readerSize)
        toast = "Text size \(Int(mode == .edit ? e : r))"
    }

    func toggleSpellcheck() {
        let on = !EditorPrefs.spellcheckOn
        UserDefaults.standard.set(on, forKey: EditorPrefs.spellcheck)
        Self.applySpellcheck(on)
        toast = on ? "Spellcheck on" : "Spellcheck off"
    }

    static func applySpellcheck(_ on: Bool) {
        for w in NSApp.windows {
            guard let root = w.contentView else { continue }
            var stack: [NSView] = [root]
            while let v = stack.popLast() {
                if let tv = v as? OnyxTextView { tv.isContinuousSpellCheckingEnabled = on }
                stack.append(contentsOf: v.subviews)
            }
        }
    }

    /// The app menu's Settings… item (SwiftUI owns the window).
    static func openSettings() {
        guard let menu = NSApp.mainMenu?.items.first?.submenu,
              let i = menu.items.firstIndex(where: { $0.keyEquivalent == "," }) else { return }
        menu.performActionForItem(at: i)
    }

    static func openVaultPanel(_ ws: Workspace) {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.prompt = "Open Vault"
        if p.runModal() == .OK, let u = p.url { OnyxApp.remember(u); ws.open(vault: u) }
    }
}
