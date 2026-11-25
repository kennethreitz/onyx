import AppKit
import SwiftUI
import OnyxCore

/// Session state for the vault-wide find and replace overlay.
@Observable final class FindReplaceModel {
    enum ScopeKind: String, CaseIterable, Identifiable {
        case vault, folder, note
        var id: String { rawValue }
        var label: String {
            switch self {
            case .vault: "Vault"
            case .folder: "Folder"
            case .note: "Note"
            }
        }
    }

    var query = ""
    var replacement = ""
    var matchCase = false
    var wholeWord = false
    var regex = false
    var includeFrontmatter = true
    var scopeKind: ScopeKind = .vault
    var folder = ""
    var note = ""
    var preview = FindReplace.Preview.empty
    var selected: Set<String> = []
    var focusToken = 0
    var millis = 0
    var lastUndo: FindReplace.Plan?

    var options: FindReplace.Options {
        let scope: FindReplace.Scope
        switch scopeKind {
        case .vault: scope = .vault
        case .folder: scope = .folder(folder)
        case .note: scope = .note(note)
        }
        return FindReplace.Options(matchCase: matchCase, wholeWord: wholeWord, regex: regex,
                                   includeFrontmatter: includeFrontmatter, scope: scope)
    }

    var selectedMatches: [FindReplace.Match] {
        preview.groups.flatMap(\.matches).filter { selected.contains($0.id) }
    }

    func selectAll() { selected = Set(preview.groups.flatMap(\.matches).map(\.id)) }
    func selectNone() { selected = [] }

    func adopt(_ preview: FindReplace.Preview) {
        self.preview = preview
        selectAll()
    }
}

@MainActor
extension Workspace {
    /// Live text for a path: an open editor buffer, else the snapshot.
    func replaceContents() -> [String: String] {
        var d: [String: String] = [:]
        if let snap = snapshot {
            for (path, note) in snap.notes { d[path] = note.content }
        }
        for pane in panes {
            if let p = pane.path, p.lowercased().hasSuffix(".md") { d[p] = pane.text }
        }
        if let p = currentPath, p.lowercased().hasSuffix(".md") { d[p] = text }
        return d
    }

    func openVaultReplace(query seed: String? = nil) {
        if let seed, !seed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            replacer.query = seed
        } else if replacer.query.isEmpty {
            if let tv = liveEditor, findInEditor, tv.selectedRange().length > 0, tv.selectedRange().length < 200 {
                let sel = (tv.string as NSString).substring(with: tv.selectedRange())
                if !sel.contains("\n") { replacer.query = sel }
            }
            if replacer.query.isEmpty, !finder.query.isEmpty { replacer.query = finder.query }
            if replacer.query.isEmpty, !searchQuery.isEmpty { replacer.query = searchQuery }
        }
        if let p = currentPath, p.lowercased().hasSuffix(".md") { replacer.note = p }
        if let folder = treeSelection.selected.first(where: { snapshot?.folders.contains($0) == true }) {
            replacer.folder = folder
        } else if let p = currentPath {
            replacer.folder = (p as NSString).deletingLastPathComponent
        } else if let f = selectedFolder {
            replacer.folder = f
        }
        replacer.focusToken += 1
        if overlay != .findReplace {
            withAnimation(Motion.overlay) { overlay = .findReplace }
        }
    }

    func runVaultReplacePreview() {
        guard let snap = snapshot else { replacer.preview = .empty; replacer.selected = []; return }
        let q = replacer.query
        let r = replacer.replacement
        let o = replacer.options
        let contents = replaceContents()
        let t0 = Date()
        let preview = FindReplace.preview(query: q, replacement: r, in: snap, options: o, contents: contents)
        replacer.millis = Int(Date().timeIntervalSince(t0) * 1000)
        replacer.adopt(preview)
    }

    func revealReplaceMatch(_ m: FindReplace.Match) {
        openNote(m.path)
        editorJump = max(0, m.line - 1)
        readerJump = nil
    }

    /// Confirm, then write the selected (or all) matches. Returns whether anything was written.
    @discardableResult
    func confirmVaultReplace(all: Bool) -> Bool {
        flushSave()
        let matches = all ? replacer.preview.groups.flatMap(\.matches) : replacer.selectedMatches
        let texts = replaceContents()
        let plan = FindReplace.plan(matches: matches, texts: texts)
        if let err = replacer.preview.error {
            toast = err
            return false
        }
        guard !plan.edits.isEmpty else {
            toast = "Nothing to replace."
            return false
        }
        let a = NSAlert()
        let files = plan.fileCount == 1 ? "1 note" : "\(plan.fileCount) notes"
        let hits = plan.matchCount == 1 ? "1 match" : "\(plan.matchCount) matches"
        a.messageText = "Replace \(hits) in \(files)?"
        a.informativeText = "The notes are written immediately. Undo Last Replace puts their previous contents back."
        a.addButton(withTitle: "Replace")
        a.addButton(withTitle: "Cancel")
        a.alertStyle = .informational
        guard a.runModal() == .alertFirstButtonReturn else { return false }
        return applyVaultReplace(plan)
    }

    @discardableResult
    func applyVaultReplace(_ plan: FindReplace.Plan) -> Bool {
        var written: [FindReplace.FileEdit] = []
        for e in plan.edits {
            if writeReplacedNote(e.path, from: e.before, to: e.after) {
                written.append(e)
            }
        }
        guard !written.isEmpty else {
            toast = "Couldn’t replace anything."
            return false
        }
        let done = FindReplace.Plan(edits: written, matchCount: written.reduce(0) { $0 + $1.count },
                                    fileCount: written.count, error: nil)
        replacer.lastUndo = done
        let files = done.fileCount == 1 ? "1 note" : "\(done.fileCount) notes"
        let hits = done.matchCount == 1 ? "1 match" : "\(done.matchCount) matches"
        toast = "Replaced \(hits) in \(files)."
        runVaultReplacePreview()
        return true
    }

    /// Restore the files from the last replace. One shot.
    @discardableResult
    func undoLastVaultReplace() -> Bool {
        guard let plan = replacer.lastUndo, !plan.edits.isEmpty else { return false }
        flushSave()
        var n = 0
        for e in plan.edits {
            if writeReplacedNote(e.path, from: e.after, to: e.before) { n += 1 }
        }
        replacer.lastUndo = nil
        toast = n == 1 ? "Undid replace in 1 note." : "Undid replace in \(n) notes."
        runVaultReplacePreview()
        return n > 0
    }

    /// Write `to` atomically, and update any open editor buffers so they don't overwrite the file.
    @discardableResult
    func writeReplacedNote(_ path: String, from _: String, to next: String) -> Bool {
        if !write(next, to: path, create: false) { return false }
        updateSnapshotNote(path, content: next)
        syncOpenBuffers(path, content: next)
        return true
    }
}

/// The vault-wide find and replace overlay. Esc or the dimmer closes it.
struct FindReplaceView: View {
    var ws: Workspace
    @Bindable var model: FindReplaceModel
    @FocusState private var field: Field?
    enum Field { case find, replace }
    @State private var task: Task<Void, Never>?
    @State private var collapsed: Set<String> = []

    init(ws: Workspace) {
        self.ws = ws
        self.model = ws.replacer
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.hairline)
            controls
            Divider().overlay(Color.hairline)
            results
            Divider().overlay(Color.hairline)
            footer
        }
        .frame(width: 760)
        .panelChrome()
        .onAppear { field = .find; schedulePreview() }
        .onChange(of: model.focusToken) { field = .find; DispatchQueue.main.async { selectFindField() } }
        .onChange(of: model.query) { schedulePreview() }
        .onChange(of: model.replacement) { schedulePreview() }
        .onChange(of: model.matchCase) { schedulePreview() }
        .onChange(of: model.wholeWord) { schedulePreview() }
        .onChange(of: model.regex) { schedulePreview() }
        .onChange(of: model.includeFrontmatter) { schedulePreview() }
        .onChange(of: model.scopeKind) { schedulePreview() }
        .onChange(of: model.folder) { if model.scopeKind == .folder { schedulePreview() } }
        .onChange(of: model.note) { if model.scopeKind == .note { schedulePreview() } }
        .onKeyPress(.escape) { ws.show(.none); return .handled }
        .onDisappear { task?.cancel() }
    }

    var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Replace in Vault").font(Theme.serif(20)).foregroundStyle(Color.ink)
                Text(statusLine).font(.system(size: 11)).foregroundStyle(model.preview.error == nil ? Color.faint : Color.danger)
            }
            Spacer(minLength: 8)
            Button { ws.show(.none) } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.muted).frame(width: 22, height: 22)
            }
            .buttonStyle(.plain).help("Close (Esc)")
        }
        .padding(.leading, 18).padding(.trailing, 12).padding(.vertical, 12)
    }

    var statusLine: String {
        if let err = model.preview.error { return err }
        if model.query.trimmingCharacters(in: .whitespaces).isEmpty { return "Search every note, then replace what’s selected." }
        let n = model.preview.matchCount
        let f = model.preview.fileCount
        var s = n == 0 ? "No matches" : (n == 1 ? "1 match" : "\(n) matches") + (f == 0 ? "" : " in " + (f == 1 ? "1 note" : "\(f) notes"))
        if model.preview.truncated { s += " (first \(FindReplace.previewCap))" }
        if model.millis > 0 { s += " · \(model.millis) ms" }
        let sel = model.selected.count
        if n > 0, sel != n { s += " · \(sel) selected" }
        return s
    }

    var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Color.faint).frame(width: 14)
                TextField("Find in vault", text: $model.query)
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .focused($field, equals: .find)
                    .onSubmit { field = .replace }
                opt("Aa", "Match case", model.matchCase) { model.matchCase.toggle() }
                opt("W", "Whole word", model.wholeWord) { model.wholeWord.toggle() }
                opt(".*", "Regular expression", model.regex) { model.regex.toggle() }
            }
            HStack(spacing: 8) {
                Image(systemName: "arrow.turn.down.right").font(.system(size: 10)).foregroundStyle(Color.faint).frame(width: 14)
                TextField(model.regex ? "Replace with  ·  $1 groups" : "Replace with", text: $model.replacement)
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .focused($field, equals: .replace)
                    .onSubmit { _ = ws.confirmVaultReplace(all: false) }
            }
            HStack(spacing: 10) {
                Picker("Scope", selection: $model.scopeKind) {
                    ForEach(FindReplaceModel.ScopeKind.allCases) { kind in
                        Text(scopeLabel(kind)).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                .labelsHidden()
                Toggle("Frontmatter", isOn: $model.includeFrontmatter)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))
                    .help("Search and replace inside YAML frontmatter")
                Spacer()
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
    }

    func scopeLabel(_ kind: FindReplaceModel.ScopeKind) -> String {
        switch kind {
        case .vault: return "Vault"
        case .folder:
            let name = model.folder.isEmpty ? "root" : (model.folder as NSString).lastPathComponent
            return "Folder (\(name))"
        case .note:
            let name = model.note.isEmpty ? "this note" : ws.noteTitle(model.note)
            return "Note (\(name))"
        }
    }

    var results: some View {
        Group {
            if model.query.trimmingCharacters(in: .whitespaces).isEmpty {
                QuietEmpty(title: "Find across the vault.", hint: "Match case, whole word, or a regular expression, then preview before replacing.")
                    .padding(.vertical, 48)
            } else if let err = model.preview.error {
                QuietEmpty(title: err, hint: "Check the expression and try again.")
                    .padding(.vertical, 48)
            } else if model.preview.groups.isEmpty {
                QuietEmpty(title: "Nothing matches.", hint: "Try a shorter query, a different scope, or include frontmatter.")
                    .padding(.vertical, 48)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.preview.groups, id: \.path) { group in
                            fileGroup(group)
                        }
                    }
                }
                .thinScrollers()
                .frame(maxHeight: 420)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .top)
    }

    func fileGroup(_ group: FindReplace.FileGroup) -> some View {
        let ids = group.matches.map(\.id)
        let checked = ids.filter { model.selected.contains($0) }.count
        let allOn = checked == ids.count
        let mixed = checked > 0 && !allOn
        let open = !collapsed.contains(group.path)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    if allOn { ids.forEach { model.selected.remove($0) } }
                    else { ids.forEach { model.selected.insert($0) } }
                } label: {
                    Image(systemName: allOn ? "checkmark.square.fill" : (mixed ? "minus.square.fill" : "square"))
                        .font(.system(size: 13)).foregroundStyle(allOn || mixed ? Color.ink : Color.faint)
                }.buttonStyle(.plain).help(allOn ? "Deselect all in this note" : "Select all in this note")
                Button {
                    if open { collapsed.insert(group.path) } else { collapsed.remove(group.path) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(open ? 90 : 0))
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Color.faint)
                        Text(ws.noteTitle(group.path)).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Color.ink).lineLimit(1)
                        Text(group.path).font(.system(size: 11)).foregroundStyle(Color.faint).lineLimit(1)
                        Spacer()
                        Text(group.matches.count == 1 ? "1 match" : "\(group.matches.count) matches")
                            .font(.system(size: 10.5).monospacedDigit()).foregroundStyle(Color.faint)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .background(Color.ink.opacity(0.03))
            if open {
                ForEach(group.matches) { m in
                    matchRow(m)
                }
            }
        }
    }

    func matchRow(_ m: FindReplace.Match) -> some View {
        let on = model.selected.contains(m.id)
        return HStack(alignment: .top, spacing: 8) {
            Button {
                if on { model.selected.remove(m.id) } else { model.selected.insert(m.id) }
            } label: {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12)).foregroundStyle(on ? Color.ink : Color.faint)
                    .padding(.top, 2)
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                snippet(m, replacement: false)
                snippet(m, replacement: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { ws.revealReplaceMatch(m) }
            Text("\(m.line)").font(.system(size: 10.5).monospacedDigit()).foregroundStyle(Color.faint).frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 5)
        .background(Color.paper)
        .contextMenu {
            Button("Open note") { ws.revealReplaceMatch(m) }
        }
    }

    func snippet(_ m: FindReplace.Match, replacement: Bool) -> some View {
        let mark = replacement ? (m.replacement.isEmpty ? "∅" : compact(m.replacement)) : compact(m.text)
        var s = AttributedString(trim(m.prefix, leading: true))
        var mid = AttributedString(mark)
        mid.backgroundColor = replacement ? Color.green.opacity(0.22) : Color(nsColor: Theme.findMatch)
        mid.foregroundColor = Color.ink
        if !replacement { mid.strikethroughStyle = replacement ? nil : .single }
        s += mid
        s += AttributedString(trim(m.suffix, leading: false))
        s.font = .system(size: 12, design: .monospaced)
        s.foregroundColor = Color.muted
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(replacement ? "→" : " ")
                .font(.system(size: 10)).foregroundStyle(Color.faint).frame(width: 10)
            Text(s).lineLimit(2)
        }
    }

    func compact(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: "⏎").replacingOccurrences(of: "\t", with: "⇥")
    }

    func trim(_ s: String, leading: Bool) -> String {
        let t = compact(s)
        if t.count <= 48 { return t }
        if leading { return "…" + String(t.suffix(48)) }
        return String(t.prefix(48)) + "…"
    }

    var footer: some View {
        HStack(spacing: 8) {
            Button("Select all") { model.selectAll() }.disabled(model.preview.matchCount == 0)
            Button("Select none") { model.selectNone() }.disabled(model.selected.isEmpty)
            Spacer()
            if model.lastUndo != nil {
                Button("Undo last replace") { _ = ws.undoLastVaultReplace() }
            }
            Button("Replace selected") { _ = ws.confirmVaultReplace(all: false) }
                .disabled(model.selectedMatches.isEmpty || model.preview.error != nil)
            Button("Replace all") { _ = ws.confirmVaultReplace(all: true) }
                .disabled(model.preview.matchCount == 0 || model.preview.error != nil)
        }
        .controlSize(.small)
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    func opt(_ title: String, _ help: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: on ? .bold : .regular, design: title == ".*" ? .monospaced : .default))
                .foregroundStyle(on ? Color.ink : Color.faint)
                .frame(minWidth: 22, minHeight: 18)
        }
        .buttonStyle(.plain).help(help)
    }

    func schedulePreview() {
        task?.cancel()
        let q = model.query
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else {
            model.preview = .empty; model.selected = []; task = nil; return
        }
        task = Task {
            try? await Task.sleep(nanoseconds: 90_000_000)
            if Task.isCancelled { return }
            let snap = ws.snapshot
            let r = model.replacement
            let o = model.options
            let contents = ws.replaceContents()
            let t0 = Date()
            let preview = await Task.detached(priority: .userInitiated) {
                guard let snap else { return FindReplace.Preview.empty }
                return FindReplace.preview(query: q, replacement: r, in: snap, options: o, contents: contents)
            }.value
            if !Task.isCancelled {
                model.millis = Int(Date().timeIntervalSince(t0) * 1000)
                model.adopt(preview)
                task = nil
            }
        }
    }

    func selectFindField() {
        NSApp.keyWindow?.firstResponder.flatMap { $0 as? NSTextView }?.selectAll(nil)
    }
}
