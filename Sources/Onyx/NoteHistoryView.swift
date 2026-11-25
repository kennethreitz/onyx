import AppKit
import SwiftUI
import OnyxCore

/// History list inside the git sidebar: commits that touched the current note.
struct NoteHistoryList: View {
    @Bindable var ws: Workspace
    var isRepo: Bool
    @State private var entries: [NoteHistoryEntry] = []
    @State private var loading = false
    @State private var loadedPath: String?
    @State private var selected: NoteHistoryEntry.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isRepo {
                QuietEmpty(title: "This vault isn’t a git repository.", hint: "Run git init in the vault folder to get history and auto-sync.").padding(.top, Space.xs)
            } else if ws.currentPath == nil {
                QuietEmpty(title: "Open a note to see its history.", hint: "Commits that touched the current note land here, newest first.").padding(.top, Space.xs)
            } else if let p = ws.currentPath, p.opensInFileView {
                QuietEmpty(title: "Version history is for notes.", hint: "Open a Markdown note to browse earlier commits.").padding(.top, Space.xs)
            } else if loading && entries.isEmpty {
                QuietEmpty(title: "Reading history…").padding(.top, Space.xs)
            } else if entries.isEmpty {
                QuietEmpty(title: "No commits mention this note yet.", hint: "Once this file is committed, earlier versions appear here.").padding(.top, Space.xs)
            } else {
                if let name = noteTitle {
                    Text(name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.muted)
                        .lineLimit(1)
                        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(entries) { e in
                            Button { open(e) } label: { row(e) }
                                .buttonStyle(.plain)
                        }
                    }.thinScrollers()
                }
            }
        }
        .onAppear { refresh() }
        .onChange(of: ws.currentPath) { refresh() }
        .onChange(of: ws.git?.lastCommit) { refresh() }
    }

    var noteTitle: String? {
        guard let p = ws.currentPath else { return nil }
        return ws.noteTitle(p)
    }

    func row(_ e: NoteHistoryEntry) -> some View {
        let on = selected == e.id || ws.versionPreview?.entry.id == e.id
        return VStack(alignment: .leading, spacing: 1) {
            Text(Self.dateLabel.string(from: e.date))
                .font(.system(size: 10.5))
                .foregroundStyle(Color.faint)
            Text(e.subject.isEmpty ? "(no message)" : e.subject)
                .font(.system(size: 12))
                .foregroundStyle(Color.ink)
                .lineLimit(2)
            Text("\(e.author) · \(e.shortHash)")
                .font(.custom("IBMPlexMono", size: 10.5))
                .foregroundStyle(Color.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(on ? Color.ink.opacity(0.07) : .clear)
        .contentShape(Rectangle())
    }

    func open(_ e: NoteHistoryEntry) {
        selected = e.id
        guard let root = ws.root, let store = NoteHistoryStore.detect(root) else { return }
        let current = ws.text
        let path = ws.currentPath ?? e.path
        let older: NoteHistoryEntry? = {
            guard let i = entries.firstIndex(where: { $0.id == e.id }), i + 1 < entries.count else { return nil }
            return entries[i + 1]
        }()
        DispatchQueue.global(qos: .userInitiated).async {
            let content = store.content(of: e)
            var previousText: String? = nil
            var previousHash: String? = nil
            if let older {
                if case .text(let t) = store.content(of: older) { previousText = t }
                previousHash = older.shortHash
            }
            DispatchQueue.main.async {
                ws.openVersionPreview(NoteVersionPreview(
                    entry: e, notePath: path, content: content, currentText: current,
                    previousText: previousText, previousHash: previousHash
                ))
            }
        }
    }

    func refresh() {
        guard isRepo, let root = ws.root, let path = ws.currentPath, !path.opensInFileView else {
            entries = []; loadedPath = nil; loading = false; selected = nil; return
        }
        if loadedPath != path { entries = []; selected = nil }
        loading = true
        let store = NoteHistoryStore.detect(root)
        DispatchQueue.global(qos: .userInitiated).async {
            let found = store?.entries(for: path) ?? []
            DispatchQueue.main.async {
                guard ws.currentPath == path else { return }
                entries = found
                loadedPath = path
                loading = false
                if selected == nil, let first = found.first {
                    open(first)
                }
            }
        }
    }

    static let dateLabel: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

/// Dimmed overlay: a rendered diff against the current note or the previous revision,
/// a raw line diff, a full preview of the chosen version, and Restore.
struct NoteVersionView: View {
    @Bindable var ws: Workspace
    var preview: NoteVersionPreview
    var dismiss: () -> Void
    @State private var tab: Tab = .diff
    @State private var expanded: Set<Int> = []
    @AppStorage("onyx.versionCompareMode") private var compareRaw = VersionCompareMode.latest.rawValue

    enum Tab: String, CaseIterable, Identifiable {
        case diff, raw, preview
        var id: String { rawValue }
        var title: String {
            switch self {
            case .diff: return "Diff"
            case .raw: return "Line diff"
            case .preview: return "Version"
            }
        }
    }

    var compare: VersionCompareMode { VersionCompareMode(rawValue: compareRaw) ?? .latest }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.hairline)
            tabs
            Divider().overlay(Color.hairline)
            content
            Divider().overlay(Color.hairline)
            footer
        }
        .frame(minWidth: 720, minHeight: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .panelChrome()
        .onKeyPress(.escape) { dismiss(); return .handled }
        .onChange(of: preview.entry.id) { expanded = [] }
        .onChange(of: compareRaw) { expanded = [] }
    }

    var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(preview.entry.subject.isEmpty ? "(no message)" : preview.entry.subject)
                    .font(Theme.serif(20)).foregroundStyle(Color.ink)
                    .lineLimit(2)
                Text("\(NoteHistoryList.dateLabel.string(from: preview.entry.date))  ·  \(preview.entry.author)  ·  \(preview.entry.shortHash)")
                    .font(.system(size: 11.5)).foregroundStyle(Color.faint)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.muted).frame(width: 22, height: 22)
            }
            .buttonStyle(.plain).help("Close (Esc)")
        }
        .padding(.leading, 18).padding(.trailing, 12).padding(.vertical, 12)
    }

    var tabs: some View {
        HStack(spacing: 1) {
            ForEach(Tab.allCases) { t in
                Button { withAnimation(Motion.quick) { tab = t } } label: {
                    Text(t.title)
                        .font(.system(size: 11.5, weight: tab == t ? .semibold : .regular))
                        .foregroundStyle(tab == t ? Color.ink : Color.faint)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(tab == t ? Color.ink.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: Radius.control))
                }.buttonStyle(.plain)
            }
            Spacer(minLength: 12)
            if tab != .preview {
                comparePicker
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    var comparePicker: some View {
        HStack(spacing: 1) {
            ForEach(VersionCompareMode.allCases) { m in
                Button { withAnimation(Motion.quick) { compareRaw = m.rawValue } } label: {
                    Text(m.title)
                        .font(.system(size: 11.5, weight: compare == m ? .semibold : .regular))
                        .foregroundStyle(compare == m ? Color.ink : Color.faint)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(compare == m ? Color.ink.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: Radius.control))
                }
                .buttonStyle(.plain)
                .disabled(m == .previous && preview.previousText == nil)
                .help(m == .previous && preview.previousText == nil ? "This is the first recorded version." : m.title)
            }
        }
    }

    /// Old / new texts and labels for the current compare mode.
    /// Compare with latest: this revision vs the current note.
    /// vs previous: the older revision vs this one (what the commit changed).
    var sides: (old: String, new: String, oldLabel: String, newLabel: String)? {
        guard case .text(let selected) = preview.content else { return nil }
        switch compare {
        case .latest:
            return (selected, preview.currentText, preview.entry.shortHash, "current")
        case .previous:
            guard let prev = preview.previousText else { return nil }
            return (prev, selected, preview.previousHash ?? "previous", preview.entry.shortHash)
        }
    }

    @ViewBuilder var content: some View {
        switch preview.content {
        case .none:
            QuietEmpty(title: "Reading this version…")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .missing:
            QuietEmpty(title: "That version isn’t in the repository.", hint: "The file may have been renamed without a followable path.")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .binary:
            QuietEmpty(title: "This version isn’t text.", hint: "A rendered preview and a restore would not be meaningful here.")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .text(let text):
            switch tab {
            case .diff:
                if let s = sides {
                    richDiffView(old: s.old, new: s.new)
                } else {
                    QuietEmpty(title: "This is the first recorded version of this note.", hint: "There isn’t an earlier commit to compare with.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            case .raw:
                if let s = sides {
                    diffView(old: s.old, new: s.new, oldLabel: s.oldLabel, newLabel: s.newLabel)
                } else {
                    QuietEmpty(title: "This is the first recorded version of this note.", hint: "There isn’t an earlier commit to compare with.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            case .preview:
                ReaderView(ws: ws, fontSize: 16, measure: 56, source: (preview.notePath, text), preview: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    var matchMessage: String {
        compare == .latest ? "This version matches the current note." : "This version matches the previous one."
    }

    func richDiffView(old: String, new: String) -> some View {
        let blocks = displayRichBlocks(old: old, new: new)
        return Group {
            if !NoteDiff.richHasChanges(NoteDiff.rich(old: old, new: new)) {
                QuietEmpty(title: matchMessage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ReaderView(ws: ws, fontSize: 16, measure: 56, source: (preview.notePath, old), preview: true, richDiff: blocks, onDiffExpand: { expanded.insert($0) })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    func displayRichBlocks(old: String, new: String) -> [NoteDiff.RichBlock] {
        let blocks = NoteDiff.rich(old: old, new: new)
        let segs = NoteDiff.collapsed(blocks, isChange: \.isChange)
        var out: [NoteDiff.RichBlock] = []
        for (i, seg) in segs.enumerated() {
            switch seg {
            case .visible(let b):
                out.append(b)
            case .hunk(_, let items):
                if expanded.contains(i) {
                    out.append(contentsOf: items)
                } else {
                    let lines = items.reduce(0) { $0 + NoteDiff.lineCount(of: $1) }
                    out.append(NoteDiff.RichBlock(op: .collapsed, kind: .paragraph, text: "", hiddenCount: lines, segmentIndex: i))
                }
            }
        }
        return out
    }

    func diffView(old: String, new: String, oldLabel: String, newLabel: String) -> some View {
        let rows = NoteDiff.numbered(NoteDiff.lines(old: old, new: new))
        let segs = NoteDiff.collapsed(rows, isChange: \.isChange)
        let changed = rows.contains { $0.isChange }
        return Group {
            if !changed {
                QuietEmpty(title: matchMessage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                GeometryReader { geo in
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            Text("— \(oldLabel)    + \(newLabel)")
                                .font(.custom("IBMPlexMono", size: 10.5))
                                .foregroundStyle(Color.faint)
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                                .padding(.bottom, 6)
                            ForEach(Array(segs.enumerated()), id: \.offset) { i, seg in
                                switch seg {
                                case .visible(let line):
                                    diffLine(line)
                                case .hunk(let count, let items):
                                    if expanded.contains(i) {
                                        ForEach(Array(items.enumerated()), id: \.offset) { _, line in
                                            diffLine(line)
                                        }
                                    } else {
                                        collapseControl(count: count, index: i)
                                    }
                                }
                            }
                        }
                        .frame(minWidth: geo.size.width, maxWidth: .infinity, alignment: .leading)
                    }
                    .thinScrollers()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    func collapseControl(count: Int, index: Int) -> some View {
        Button { expanded.insert(index) } label: {
            Text("Show \(count) unchanged line\(count == 1 ? "" : "s")")
                .font(.system(size: 11.5))
                .foregroundStyle(Color.faint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Color.ink.opacity(0.05))
        }
        .buttonStyle(.plain)
        .help("Show the hidden unchanged lines")
    }

    func diffLine(_ line: NoteDiff.NumberedLine) -> some View {
        let (mark, color, bg): (String, Color, Color) = {
            switch line.line {
            case .same: return (" ", Color.ink.opacity(0.82), .clear)
            case .insert: return ("+", Self.add, Self.add.opacity(0.10))
            case .delete: return ("-", Color.danger, Color.danger.opacity(0.10))
            }
        }()
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(line.oldNumber.map(String.init) ?? " ")
                .font(.custom("IBMPlexMono", size: 10))
                .foregroundStyle(Color.faint)
                .frame(width: 36, alignment: .trailing)
            Text(line.newNumber.map(String.init) ?? " ")
                .font(.custom("IBMPlexMono", size: 10))
                .foregroundStyle(Color.faint)
                .frame(width: 36, alignment: .trailing)
            Text(mark)
                .font(.custom("IBMPlexMono", size: 11))
                .foregroundStyle(color)
                .frame(width: 12, alignment: .center)
            Text(line.line.text.isEmpty ? " " : line.line.text)
                .font(.custom("IBMPlexMono", size: 11.5))
                .foregroundStyle(color)
                .textSelection(.enabled)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bg)
    }

    var footer: some View {
        HStack {
            Text("Restore puts this text in the editor as an unsaved edit. It does not reset the repository.")
                .font(.system(size: 10.5)).foregroundStyle(Color.faint)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Button("Restore this version") { restore() }
                .disabled(!canRestore)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    var canRestore: Bool {
        if case .text(let t) = preview.content, t != preview.currentText, ws.currentPath != nil, !(ws.currentPath?.opensInFileView ?? true) {
            return true
        }
        return false
    }

    func restore() {
        guard case .text(let t) = preview.content else { return }
        ws.confirmRestoreNoteVersion(entry: preview.entry, content: t)
    }

    /// A quiet green that sits next to `Color.danger` on paper, light or dark.
    static let add = Color(nsColor: NSColor(name: nil, dynamicProvider: { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.62, green: 0.84, blue: 0.68, alpha: 1)
            : NSColor(srgbRed: 0.20, green: 0.47, blue: 0.32, alpha: 1)
    }))
}
