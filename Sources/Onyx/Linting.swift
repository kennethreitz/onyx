import AppKit
import SwiftUI
import OnyxCore

/// UI kept separate from the pure rule engine. No automatic folder-wide writes.
extension Workspace {
    @discardableResult
    func lintCurrentNote(touched: Bool = false, announce: Bool = true) -> Bool {
        guard currentPath?.lowercased().hasSuffix(".md") == true else { return false }
        let result = Linter.lint(text, config: .load(), touched: touched)
        guard result != text else { if announce { toast = "No lint changes" }; return false }
        applyLintText(result)
        if announce { toast = "Note linted · Undo to restore" }
        return true
    }

    /// Lint on save (Settings ▸ Linter, off by default): only explicit saves (⌘S, Save and Read,
    /// Esc to reading, switching notes), never the typing autosave, so a space you just typed survives.
    func lintOnSave() {
        guard UserDefaults.standard.bool(forKey: LinterKeys.onSave), editedSinceLint, !isCanvas, !isBase else { return }
        lintCurrentNote(touched: true, announce: false)
        editedSinceLint = false
    }

    /// Native text-system replacement gives one undo step and keeps the selection on its lines.
    func applyLintText(_ result: String) {
        let old = text
        if let tv = liveEditor, tv.string == old, tv.isEditable {
            let selection = tv.selectedRange()
            let start = Linter.mapCursor(selection.location, from: old, to: result)
            let end = Linter.mapCursor(NSMaxRange(selection), from: old, to: result)
            let range = NSRange(location: 0, length: (old as NSString).length)
            guard tv.shouldChangeText(in: range, replacementString: result) else { return }
            tv.breakUndoCoalescing()
            tv.replaceCharacters(in: range, with: result)
            tv.didChangeText()
            tv.setSelectedRange(NSRange(location: start, length: max(0, end - start)))
            tv.undoManager?.setActionName("Lint Note")
            tv.breakUndoCoalescing()
            text = result
        } else {
            text = result
            renderToken += 1
        }
    }

    func chooseLintFolder() {
        guard let root else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.directoryURL = root; panel.prompt = "Preview Lint"
        panel.message = "Choose a folder inside this vault. Preview changes before applying."
        guard panel.runModal() == .OK, let url = panel.url?.standardizedFileURL else { return }
        let base = root.standardizedFileURL.path
        guard url.path == base || url.path.hasPrefix(base + "/") else { toast = "Choose a folder inside this vault"; return }
        previewLintFolder(url.path == base ? "" : String(url.path.dropFirst(base.count + 1)))
    }

    func previewLintFolder(_ folder: String) {
        guard let root, let snapshot else { return }
        let config = LinterConfig.load(), now = Date()
        let prefix = folder.isEmpty ? "" : folder + "/"
        let paths = snapshot.notes.keys.filter { $0.hasPrefix(prefix) && $0.lowercased().hasSuffix(".md") }.sorted()
        var changes: [(String, String, String)] = [], skipped = 0
        for path in paths {
            // Never overwrite a dirty or split-pane buffer with a bulk operation.
            if path == currentPath || panes.contains(where: { $0.path == path }) { skipped += 1; continue }
            let url = root.appendingPathComponent(path)
            // Reject symlinks leaving the vault, even if present in the index.
            guard url.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/"),
                  let old = try? String(contentsOf: url, encoding: .utf8) else { skipped += 1; continue }
            let new = Linter.lint(old, config: config, now: now)
            if old != new { changes.append((path, old, new)) }
        }
        let alert = NSAlert()
        alert.messageText = "Lint \(folder.isEmpty ? "Vault" : folder)?"
        alert.informativeText = "\(changes.count) of \(paths.count) notes would change. \(skipped) open or unreadable notes skipped.\n\nUses your current Linter settings, includes subfolders, and never changes attachments. Bulk edits cannot be undone in the editor.\n\n" + changes.prefix(8).map { $0.0 }.joined(separator: "\n")
        alert.addButton(withTitle: changes.isEmpty ? "Done" : "Apply to \(changes.count) Notes")
        if !changes.isEmpty { alert.addButton(withTitle: "Cancel") }
        let apply = { [weak self] (response: NSApplication.ModalResponse) in
            guard let self, response == .alertFirstButtonReturn, !changes.isEmpty, self.root == root else { return }
            var done = 0, conflicts = 0
            for (path, old, new) in changes {
                let url = root.appendingPathComponent(path)
                guard path != self.currentPath, !self.panes.contains(where: { $0.path == path }),
                      url.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/"),
                      (try? String(contentsOf: url, encoding: .utf8)) == old else { conflicts += 1; continue }
                if self.write(new, to: path, create: false) { done += 1 } else { conflicts += 1 }
            }
            self.toast = "Linted \(done) notes" + (conflicts == 0 ? "" : " · \(conflicts) changed or failed; skipped")
        }
        if let window = NSApp.keyWindow { alert.beginSheetModal(for: window, completionHandler: apply) }
        else { apply(alert.runModal()) }
    }
}

struct LinterSettingsPage: View {
    @AppStorage(LinterKeys.onSave) private var onSave = false
    @AppStorage(LinterKeys.preserveBreaks) private var preserveBreaks = true
    @AppStorage(LinterKeys.listMarker) private var marker = "-"
    @AppStorage(LinterKeys.timestampKey) private var timestampKey = "updated"
    var body: some View {
        Form {
            Section {
                Toggle("Lint on save", isOn: $onSave)
                Text("Off by default. Runs on ⌘S, Save and Read, Esc to reading, and switching notes when you edited the note — never while you type. Current-note linting is one undoable editor edit. Folder linting always requires a preview and confirmation.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Rules") {
                ForEach(Linter.rules) { rule in LintRuleToggle(rule: rule) }
            }
            Section("Options") {
                Toggle("Preserve two-space hard line breaks", isOn: $preserveBreaks)
                Picker("List marker", selection: $marker) { Text("-").tag("-"); Text("*").tag("*"); Text("+").tag("+") }
                Picker("Timestamp key", selection: $timestampKey) { Text("updated").tag("updated"); Text("modified").tag("modified") }
                Text("Timestamps use local time, to the minute. Manual linting stamps only when another rule changes the note; lint-on-save also stamps edited notes. Protected regions are left alone.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped).frame(width: SettingsPage.width, height: 600)
    }
}

private struct LintRuleToggle: View {
    let rule: LintRule
    @AppStorage private var enabled: Bool
    init(rule: LintRule) {
        self.rule = rule
        _enabled = AppStorage(wrappedValue: rule.defaultOn, LinterKeys.rule(rule.id))
    }
    var body: some View {
        Toggle(isOn: $enabled) {
            VStack(alignment: .leading) {
                Text(rule.name)
                Text(rule.description).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
