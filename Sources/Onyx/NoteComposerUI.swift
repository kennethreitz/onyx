import AppKit
import SwiftUI
import OnyxCore

/// Pending extract: the range in the open note, the text to write, and a default filename.
struct PendingExtract: Equatable {
    var sourcePath: String
    var range: NSRange
    var text: String
    var defaultName: String
}

extension Workspace {

    /// Merge the open note into a note the user picks in the quick switcher.
    func beginMerge() {
        guard currentPath != nil, !isCanvas, !isBase, currentPath?.lowercased().hasSuffix(".md") == true else {
            NSSound.beep(); return
        }
        flushSave()
        withAnimation(Motion.overlay) { overlay = .merge }
    }

    func confirmMerge(into target: String) {
        show(.none)
        guard let source = currentPath, source != target else { NSSound.beep(); return }
        guard snapshot?.notes[target] != nil else { NSSound.beep(); return }
        if NoteComposer.Settings.confirmMerge {
            let srcName = noteTitle(source)
            let dstName = noteTitle(target)
            let a = NSAlert()
            a.messageText = "Merge “\(srcName)” into “\(dstName)”?"
            a.informativeText = "The contents of “\(srcName)” will be added to “\(dstName)”, links to “\(srcName)” will point at “\(dstName)”, and “\(srcName)” will be moved to the Trash. You can restore it from the Trash in Finder."
            a.addButton(withTitle: "Merge")
            a.addButton(withTitle: "Cancel")
            a.alertStyle = .warning
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        performMerge(from: source, into: target)
    }

    /// Extract the current selection, or a heading section, into a new or existing note.
    func beginExtract(heading: Bool = false) {
        guard currentPath != nil, !isCanvas, !isBase else { NSSound.beep(); return }
        flushSave()
        if mode != .edit {
            withAnimation(.easeInOut(duration: 0.18)) { mode = .edit }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.beginExtract(heading: heading) }
            return
        }
        guard let tv = (MainWindow.current?.firstResponder as? OnyxTextView) ?? liveEditor else { NSSound.beep(); return }
        let ns = tv.string as NSString
        let sel = tv.selectedRange()
        let pending: PendingExtract?
        if heading {
            guard let section = NoteComposer.headingSection(in: tv.string, at: sel.location),
                  NSMaxRange(section.range) <= ns.length else { NSSound.beep(); return }
            let text = ns.substring(with: section.range)
            pending = PendingExtract(sourcePath: currentPath ?? "", range: section.range, text: text, defaultName: section.name)
        } else {
            guard sel.length > 0, NSMaxRange(sel) <= ns.length else { NSSound.beep(); return }
            let text = ns.substring(with: sel)
            let name = NoteComposer.defaultName(forSelection: text)
                ?? NoteNaming.fileName(fromTitle: text.split(whereSeparator: { $0.isNewline }).first.map(String.init) ?? "")
            let defaultName = name.isEmpty ? "Untitled" : name
            pending = PendingExtract(sourcePath: currentPath ?? "", range: sel, text: text, defaultName: defaultName)
        }
        guard let pending, !pending.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { NSSound.beep(); return }
        pendingExtract = pending
        withAnimation(Motion.overlay) { overlay = .extract }
    }

    func finishExtract(named raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { NSSound.beep(); return }
        let folder = NoteComposer.folder(forCurrent: currentPath, location: NoteComposer.Settings.location)
        let dest = NoteComposer.path(named: name, folder: folder)
        finishExtract(to: dest, creating: snapshot?.notes[dest] == nil && !fileExists(dest))
    }

    func finishExtract(to dest: String, creating: Bool) {
        // The picker dismisses before this runs, so read the pending extract first.
        guard let pending = pendingExtract, let source = currentPath, source == pending.sourcePath else {
            pendingExtract = nil
            if overlay == .extract { show(.none) }
            NSSound.beep(); return
        }
        pendingExtract = nil
        if overlay == .extract { show(.none) }
        guard dest != source else { toast = "Pick a different note"; NSSound.beep(); return }
        if creating {
            let path = NoteComposer.uniquePath(dest, occupied: { fileExists($0) || snapshot?.notes[$0] != nil })
            let content = pending.text.hasSuffix("\n") ? pending.text : pending.text + "\n"
            guard write(content, to: path, create: true) else { return }
            completeExtract(pending, dest: path, created: true)
        } else {
            guard let existing = snapshot?.notes[dest]?.content ?? readFile(dest) else { NSSound.beep(); return }
            let merged = NoteComposer.merge(source: pending.text, target: existing, placement: .append)
            guard write(merged, to: dest, create: false) else { return }
            noteUpdatedOnDisk(dest, content: merged)
            completeExtract(pending, dest: dest, created: false)
        }
    }

    // MARK: Private

    private func performMerge(from source: String, into target: String) {
        guard let snap = snapshot else { return }
        guard let srcText = source == currentPath ? Optional(text) : snap.notes[source]?.content else { return }
        guard let dstText = snap.notes[target]?.content else { return }
        var merged = NoteComposer.merge(source: srcText, target: dstText, placement: NoteComposer.Settings.placement)
        merged = remapText(merged, at: target, from: source, to: target, snap: snap) ?? merged
        guard write(merged, to: target, create: false) else { return }
        noteUpdatedOnDisk(target, content: merged)
        let edited = remapLinks(from: source, to: target)
        let srcName = noteTitle(source)
        let dstName = noteTitle(target)
        trash([source], afterward: { [weak self] in
            guard let self else { return }
            self.openNote(target)
            self.mode = .edit
            let extra = edited.isEmpty ? "" : " · updated links in \(edited.count) note\(edited.count == 1 ? "" : "s")"
            self.toast = "Merged “\(srcName)” into “\(dstName)”\(extra)"
            self.vaultMutated("Merge \(srcName) → \(dstName)", paths: [source, target] + edited)
        })
    }

    private func completeExtract(_ pending: PendingExtract, dest: String, created: Bool) {
        let title = noteTitle(dest)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.replaceExtracted(pending, with: dest)
            self.vaultMutated(created ? "Extract to \(title)" : "Extract into \(title)", paths: [pending.sourcePath, dest])
            self.toast = created ? "Extracted to “\(title)”" : "Appended to “\(title)”"
            if NoteComposer.Settings.openAfterExtract { self.openNote(dest); self.mode = .edit }
        }
    }

    private func replaceExtracted(_ pending: PendingExtract, with dest: String) {
        let clash = nameClash(dest, ignoring: pending.sourcePath)
        let title = NoteComposer.displayTitle(path: dest, clash: clash)
        let style = NoteComposer.Settings.afterExtract
        let replacement = NoteComposer.replacement(title: title, style: style)
        applyEdit { _, _ in
            let sel = replacement.isEmpty
                ? NSRange(location: pending.range.location, length: 0)
                : NSRange(location: pending.range.location, length: (replacement as NSString).length)
            return TextEdit(range: pending.range, replacement: replacement, selection: sel)
        }
    }

    /// Rewrite wikilinks and Markdown links across the vault so `from` now points at `to`.
    /// Skips `from` itself (it is about to be trashed). Returns the paths that changed.
    @discardableResult
    func remapLinks(from: String, to: String) -> [String] {
        guard let snap = snapshot else { return [] }
        let fileMap = [from: to]
        var edited: [String] = []
        for (path, note) in snap.notes where path != from {
            var text = note.content
            var changed = false
            if let w = remapText(text, at: path, from: from, to: to, snap: snap) {
                text = w; changed = true
            }
            if changed, write(text, to: path, create: false) {
                noteUpdatedOnDisk(path, content: text)
                edited.append(path)
            }
        }
        if let root {
            for c in snap.canvases.keys {
                let url = root.appendingPathComponent(c)
                guard let old = try? String(contentsOf: url, encoding: .utf8),
                      let new = CanvasFile.rewriteFiles(old, { f in snap.resolve(f, from: c).flatMap { fileMap[$0] } }) else { continue }
                if c == currentPath, isDirty { continue }
                if write(new, to: c, create: false) {
                    noteUpdatedOnDisk(c, content: new)
                    edited.append(c)
                }
            }
        }
        return edited
    }

    func remapText(_ text: String, at path: String, from: String, to: String, snap: VaultSnapshot) -> String? {
        let fileMap = [from: to]
        var out = text
        var changed = false
        let links = NoteParser.summarize(text).links
        if let w = WikiLinkRemap.rewrite(out, links: links, map: fileMap, resolve: { snap.resolve($0, from: path) }, nameClash: { title in
            nameClashTitle(title, ignoring: [from, to], snap: snap)
        }) {
            out = w; changed = true
        }
        if let md = MarkdownLinks.rewrite(out, oldNote: path, newNote: path,
                                          exists: { snap.notes[$0] != nil || snap.attachments[$0] != nil },
                                          resolveName: { snap.resolve($0, from: path) },
                                          moved: { fileMap[$0] }) {
            out = md; changed = true
        }
        return changed ? out : nil
    }

    func noteTitle(_ path: String) -> String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    func fileExists(_ path: String) -> Bool {
        guard let root else { return false }
        return FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)
    }

    func readFile(_ path: String) -> String? {
        guard let root else { return nil }
        return try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    func nameClash(_ dest: String, ignoring source: String) -> Bool {
        guard let snap = snapshot else { return false }
        return nameClashTitle(NoteComposer.displayTitle(path: dest, clash: false), ignoring: [source, dest], snap: snap)
    }

    func nameClashTitle(_ title: String, ignoring: [String], snap: VaultSnapshot) -> Bool {
        let skip = Set(ignoring)
        return snap.namesIndex[title.lowercased()]?.contains(where: { !skip.contains($0) }) == true
    }
}
