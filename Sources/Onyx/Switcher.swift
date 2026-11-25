import SwiftUI
import OnyxCore

struct PaletteItem: Identifiable {
    var id: String
    var title: String
    var subtitle: String = ""
    var symbol: String? = nil
    var shortcut: String = ""
    var titleHits: [Int] = []         // Character offsets to highlight
    var subtitleHits: [Int] = []
    var badge: String = ""            // e.g. the alias that matched
    var badgeHits: [Int] = []
    var openInSplit: (() -> Void)? = nil
    var action: () -> Void
}

/// Spotlight-like list used by both the quick switcher (⌘O) and the command palette (⌘P).
/// ↑/↓ move, ↩ opens, ⌘↩ opens in a split, ⇧↩ (or the Create row) makes a note with the
/// typed name, Esc closes.
struct PaletteView: View {
    var placeholder: String
    var items: (String) -> [PaletteItem]
    var onCreate: ((String) -> Void)? = nil
    /// Whether a note with exactly this name already exists (hides the Create row).
    var exists: ((String) -> Bool)? = nil
    /// "note" or "folder": wording of the Create row and hints.
    var noun = "note"
    var openVerb = "open"
    var allowSplit = true
    /// Prefills the search field (extract offers the heading as a name).
    var initialQuery: String = ""
    /// When the typed name does not already exist, select the Create row first.
    var preferCreate: Bool = false
    var dismiss: () -> Void
    @State private var query = ""
    @State private var results: [PaletteItem] = []
    @State private var selection = 0
    @State private var monitor: Any?
    @State private var hovered: Int?
    @FocusState private var focused: Bool

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }
    private var showCreate: Bool { onCreate != nil && !trimmed.isEmpty && !(exists?(trimmed) ?? false) }
    private var rowCount: Int { results.count + (showCreate ? 1 : 0) }
    private var createIndex: Int { results.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: onCreate != nil ? "doc.text.magnifyingglass" : "command").font(.system(size: 15)).foregroundStyle(Color.faint)
                TextField(placeholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(Theme.serif(21))
                    .focused($focused)
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(.escape) { dismiss(); return .handled }
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            if rowCount > 0 {
                Divider().overlay(Color.hairline)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            if query.isEmpty, onCreate != nil, !results.isEmpty {
                                Text("RECENT").font(.system(size: TypeScale.label, weight: .semibold)).tracking(0.8).foregroundStyle(Color.faint)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.top, Space.s).padding(.bottom, Space.xs)
                            }
                            // keyed by position, matching the .id used for scrollTo (two identities confuse LazyVStack)
                            ForEach(Array(results.enumerated()), id: \.offset) { i, item in
                                row(item, selected: i == selection, hovered: hovered == i).id(i)
                                    .onHover { h in if h { hovered = i } else if hovered == i { hovered = nil } }
                                    .onTapGesture { selection = i; activate(split: NSEvent.modifierFlags.contains(.command)) }
                            }
                            if showCreate {
                                createRow(selected: selection == createIndex, hovered: hovered == createIndex).id(createIndex)
                                    .onHover { h in if h { hovered = createIndex } else if hovered == createIndex { hovered = nil } }
                                    .onTapGesture { create() }
                            }
                        }.padding(.vertical, Space.s)
                    }
                    .thinScrollers()
                    .frame(maxHeight: 400)
                    .onChange(of: selection) { proxy.scrollTo(selection) }
                }
                if onCreate != nil {
                    Divider().overlay(Color.hairline)
                    HStack(spacing: 14) {
                        hint("↩", openVerb); if allowSplit { hint("⌘↩", "open in split") }; if showCreate { hint("⇧↩", "create \(noun)") }; hint("esc", "close")
                        Spacer()
                    }
                    .padding(.horizontal, 18).padding(.vertical, 7)
                }
            }
        }
        .frame(width: 640)
        .panelChrome()
        .onAppear {
            if query.isEmpty, !initialQuery.isEmpty { query = initialQuery }
            if let q = ProcessInfo.processInfo.environment["ONYX_SWITCHER_QUERY"], onCreate != nil { query = q }
            focused = true; refresh(); install()
        }
        .onDisappear { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
        .onChange(of: query) { refresh() }
    }

    private func refresh() {
        results = items(query)
        if ProcessInfo.processInfo.environment["ONYX_DEBUG_KEYS"] != nil {
            print("[switcher] query=“\(query)” → \(results.count): \(results.prefix(3).map(\.title)) create=\(showCreate)"); fflush(stdout)
        }
        // Nothing found, or a new name we would rather create: the Create row is the thing to do.
        if showCreate, preferCreate || results.isEmpty {
            let exact = results.firstIndex { $0.title.compare(trimmed, options: .caseInsensitive) == .orderedSame }
            selection = exact ?? createIndex
        } else {
            selection = results.isEmpty && showCreate ? createIndex : 0
        }
    }

    private func move(_ d: Int) {
        guard rowCount > 0 else { return }
        selection = min(max(selection + d, 0), rowCount - 1)
    }

    /// ↩ / ⌘↩ / ⇧↩ arrive here before the menu bar (⌘↩ is also Read ⇄ Edit there).
    private func install() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            guard e.keyCode == 36 || e.keyCode == 76 else { return e }
            // an input method composing (e.g. kana → kanji) owns Return
            if let tv = e.window?.firstResponder as? NSTextView, tv.hasMarkedText() { return e }
            let mods = e.modifierFlags.intersection([.command, .shift, .option, .control])
            switch mods {
            case []: activate(split: false); return nil
            case [.command]: activate(split: true); return nil
            case [.shift]: if showCreate { create() } else { activate(split: false) }; return nil
            default: return e
            }
        }
    }

    private func activate(split: Bool) {
        if results.indices.contains(selection) {
            let item = results[selection]
            dismiss()
            if split, let s = item.openInSplit { s() } else { item.action() }
        } else if showCreate { create() }
    }

    private func create() {
        guard let c = onCreate, !trimmed.isEmpty else { return }
        dismiss(); c(trimmed)
    }

    func hint(_ k: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Keycaps(keys: k, size: TypeScale.label)
            Text(label).font(.system(size: TypeScale.caption)).foregroundStyle(Color.faint)
        }
    }

    /// The string with its matched characters drawn in ink and a touch heavier.
    static func highlighted(_ s: String, _ hits: [Int], base: Color, hit: Color, size: CGFloat, weight: Font.Weight = .regular) -> Text {
        guard !hits.isEmpty else { return Text(s).font(.system(size: size, weight: weight)).foregroundColor(base) }
        let set = Set(hits)
        var out = Text("")
        var run = "", runHit = false
        func flush() {
            guard !run.isEmpty else { return }
            out = out + Text(run).font(.system(size: size, weight: runHit ? .semibold : weight)).foregroundColor(runHit ? hit : base)
            run = ""
        }
        for (i, ch) in s.enumerated() {
            let h = set.contains(i)
            if h != runHit { flush(); runHit = h }
            run.append(ch)
        }
        flush()
        return out
    }

    /// Selection is an inset, rounded wash (not a full-bleed bar); hover is half as strong.
    func rowBackground(selected: Bool, hovered: Bool) -> some View {
        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            .fill(Color.ink.opacity(selected ? 0.075 : (hovered ? 0.035 : 0)))
            .padding(.horizontal, Space.s)
    }

    func row(_ item: PaletteItem, selected: Bool, hovered: Bool = false) -> some View {
        HStack(spacing: 10) {
            if let s = item.symbol { Image(systemName: s).font(.system(size: 12)).foregroundStyle(selected ? Color.ink : Color.muted).frame(width: 18) }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Self.highlighted(item.title, item.titleHits, base: .ink.opacity(0.82), hit: .ink, size: TypeScale.row).lineLimit(1)
                    if !item.badge.isEmpty {
                        Self.highlighted(item.badge, item.badgeHits, base: .faint, hit: .muted, size: 11).lineLimit(1)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: Radius.small).stroke(Color.hairline))
                    }
                }
                if !item.subtitle.isEmpty {
                    Self.highlighted(item.subtitle, item.subtitleHits, base: .faint, hit: .muted, size: 11).lineLimit(1).truncationMode(.head)
                }
            }
            Spacer()
            if !item.shortcut.isEmpty { Keycaps(keys: item.shortcut).opacity(selected ? 1 : 0.8) }
        }
        .padding(.horizontal, 18).padding(.vertical, item.subtitle.isEmpty ? 8 : 6)
        .frame(minHeight: 34)
        .background(rowBackground(selected: selected, hovered: hovered))
        .contentShape(Rectangle())
    }

    func createRow(selected: Bool, hovered: Bool = false) -> some View {
        let (folder, name) = Self.split(trimmed)
        return HStack(spacing: 10) {
            Image(systemName: "plus").font(.system(size: 12)).foregroundStyle(Color.muted).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                (Text("Create ").foregroundColor(.muted) + Text(name).foregroundColor(.ink).fontWeight(.medium)).font(.system(size: 13.5)).lineLimit(1)
                Text(folder.isEmpty ? "new \(noun) in the vault root" : "new \(noun) in \(folder)").font(.system(size: 11)).foregroundStyle(Color.faint).lineLimit(1)
            }
            Spacer()
            Keycaps(keys: "⇧↩").opacity(selected ? 1 : 0.8)
        }
        .padding(.horizontal, 18).padding(.vertical, 6)
        .frame(minHeight: 34)
        .background(rowBackground(selected: selected, hovered: hovered))
        .contentShape(Rectangle())
    }

    static func split(_ q: String) -> (folder: String, name: String) {
        var q = q
        if q.lowercased().hasSuffix(".md") { q = String(q.dropLast(3)) }
        guard let slash = q.lastIndex(of: "/") else { return ("", q) }
        return (String(q[..<slash]), String(q[q.index(after: slash)...]))
    }
}

enum PaletteCommands {
    @MainActor static func all(_ ws: Workspace, appearance: @escaping (String) -> Void) -> [PaletteItem] {
        func item(_ id: String, title: String? = nil, symbol: String? = nil, action: @escaping () -> Void) -> PaletteItem {
            let spec = CommandCatalog.spec(id)
            return PaletteItem(
                id: id,
                title: title ?? spec?.title ?? id,
                symbol: symbol ?? spec?.symbol,
                shortcut: ShortcutStore.shared.display(for: id),
                action: action
            )
        }
        return [
            item("switcher", title: "Quick switcher") { DispatchQueue.main.async { ws.show(.switcher) } },
            item("rename", title: "Rename file…") { DispatchQueue.main.async { ws.confirmRenameCurrent() } },
            item("move", title: "Move note to…") { DispatchQueue.main.async { ws.beginMoveCurrent() } },
            item("delete", title: "Delete note…") { DispatchQueue.main.async { ws.confirmTrashCurrent() } },
            item("split") { ws.split(.vertical) },
            item("splitdown") { ws.split(.horizontal) },
            item("closepane") { ws.closePane() },
            item("nextpane") { ws.focusNextPane() },
            item("daily", title: "Open today’s daily note") { ws.openDaily() },
            item("back") { ws.goBack() },
            item("forward") { ws.goForward() },
            item("daily-prev", title: "Previous daily note") { ws.openDaily(offset: -1) },
            item("daily-next", title: "Next daily note") { ws.openDaily(offset: 1) },
            item("home", title: "Open homepage") { ws.openHome() },
            item("random") { ws.openRandomNote() },
            item("mode", title: ws.mode == .read ? "Edit this note" : "Read this note", symbol: ws.mode == .read ? "pencil" : "book") { ws.toggleMode() },
            item("new", title: "New note") { ws.newNote() },
            item("newfolder") { ws.newFolder() },
            item("files", title: "Show files") { ws.toggleSidebar(.files) },
            item("search", title: "Search vault") { ws.sidebarTab = .search; if !ws.sidebarVisible { ws.toggleSidebar() }; ws.focusSearch += 1 },
            item("recent") { ws.toggleSidebar(.recent) },
            item("bookmarks") { ws.toggleSidebar(.bookmarks) },
            item("bookmark", title: "Bookmark / unbookmark this note") { ws.toggleBookmark() },
            item("tags") { ws.toggleSidebar(.tags) },
            item("git") { ws.toggleSidebar(.git) },
            item("notehistory", title: "Version history of this note") { ws.showNoteHistory() },
            item("synclog") { DispatchQueue.main.async { ws.show(.syncLog) } },
            item("inspector", title: "Show inspector (outline, backlinks, properties)") { ws.toggleInspector() },
            item("outline") { ws.toggleInspector(.outline) },
            item("backlinks") { ws.toggleInspector(.backlinks) },
            item("props") { ws.toggleInspector(.properties) },
            item("graph", title: "Graph: focus on this note") { DispatchQueue.main.async { ws.toggleGraph(atlas: false) } },
            item("atlas", title: "Graph: atlas of the vault") { DispatchQueue.main.async { ws.toggleGraph(atlas: true) } },
            item("focus", title: ws.focusMode ? "Leave focus mode" : "Focus mode (just the text)") { ws.toggleFocusMode() },
            item("layout", title: "Toggle three-pane workspace") { ws.toggleWorkspaceLayout() },
            item("exportpdf") { NotePrinter.run("export", ws: ws) },
            item("exportsel") { NoteBookPrinter.run(Array(ws.treeSelection.selected), ws: ws) },
            item("exportfolder") {
                if let f = ws.treeSelection.selected.count == 1 ? ws.treeSelection.selected.first : ws.selectedFolder {
                    NoteBookPrinter.run([f], ws: ws)
                } else { NSSound.beep() }
            },
            item("print") { NotePrinter.run("print", ws: ws) },
            item("lint") { ws.lintCurrentNote() },
            item("lintfolder") { DispatchQueue.main.async { ws.chooseLintFolder() } },
            item("readaloud") { ws.readAloud() },
            item("readpause", title: ws.speech.state == .paused ? "Resume Reading" : "Pause Reading", symbol: ws.speech.state == .paused ? "play.fill" : "pause.fill") { ws.toggleSpeechPause() },
            item("readstop") { ws.stopSpeech() },
            item("record", title: ws.recorder.isRecording ? "Stop Recording" : "Record Audio", symbol: ws.recorder.isRecording ? "stop.circle" : "mic") { ws.toggleRecording() },
            item("sidenotes", title: ws.sidenotes ? "Footnotes at the end" : "Footnotes as sidenotes") { ws.sidenotes.toggle() },
            item("light", title: "Appearance: light") { appearance("light") },
            item("dark", title: "Appearance: dark") { appearance("dark") },
            item("system", title: "Appearance: match system") { appearance("system") },
            item("copy", title: "Copy wikilink to this note") { ws.copyWikilink() },
            item("finder") { ws.revealInFinder() },
            item("obsidian") { ws.openInObsidian() },
            item("reindex", title: "Rebuild index") { ws.reindex() },
            // Obsidian parity: commands that were only in the menus, then the new ones
            item("save") { ws.flushSave() },
            item("openvault") { DispatchQueue.main.async { Workspace.openVaultPanel(ws) } },
            item("find") { DispatchQueue.main.async { ws.openFind() } },
            item("findreplace") { DispatchQueue.main.async { ws.openFind(replace: true) } },
            item("replacevault", title: "Replace in vault…") { DispatchQueue.main.async { ws.openVaultReplace() } },
            item("undoreplace") { _ = ws.undoLastVaultReplace() },
            item("searchsel") { ws.searchSelection() },
            item("graphpane", title: ws.graphPaneIndex == nil ? "Graph in a pane" : "Close graph pane") {
                ws.graphPaneIndex == nil ? ws.openGraphPane(atlas: ws.graphAtlas) : ws.closeGraphPane()
            },
            item("prevpane") { ws.focusNextPane(-1) },
            item("newpane") { ws.newNoteInPane() },
            item("daily-yesterday") { ws.openDaily(days: -1) },
            item("daily-tomorrow") { ws.openDaily(days: 1) },
            item("headings") { DispatchQueue.main.async { ws.show(.headings) } },
            item("revealtree") { ws.revealInSidebar() },
            item("duplicate") { ws.duplicateCurrent() },
            item("copypath") { ws.copyFilePath() },
            item("openexternal") { ws.openInDefaultApp() },
            item("clip") { DispatchQueue.main.async { ws.promptClip() } },
            item("zoomin") { ws.zoom(1) },
            item("zoomout") { ws.zoom(-1) },
            item("zoomreset") { ws.zoom(0) },
            item("spellcheck", title: EditorPrefs.spellcheckOn ? "Turn spellcheck off" : "Turn spellcheck on") { ws.toggleSpellcheck() },
            item("merge") { DispatchQueue.main.async { ws.beginMerge() } },
            item("extract") { DispatchQueue.main.async { ws.beginExtract() } },
            item("extractheading") { DispatchQueue.main.async { ws.beginExtract(heading: true) } },
            item("settings") { DispatchQueue.main.async { Workspace.openSettings() } },
            item("hints") { withAnimation(Motion.quick) { ws.showHints = true } },
        ] + Workspace.formatMenu.compactMap { $0 }.map { id in item(id) { ws.runEditCommand(id) } }
          + Workspace.foldMenu.map { id in item(id) { ws.runFold(id) } }
    }

    /// Jump to heading…: the open note's headings, indented by level.
    @MainActor static func headings(_ ws: Workspace, _ q: String) -> [PaletteItem] {
        let hs = ws.liveHeadings
        let minLevel = hs.map(\.level).min() ?? 1
        let items = hs.enumerated().map { i, h in
            PaletteItem(id: "h:\(i)", title: String(repeating: "  ", count: max(0, h.level - minLevel)) + h.text,
                        subtitle: String(repeating: "#", count: h.level), symbol: nil) { ws.jumpToHeading(i) }
        }
        return filter(items, q)
    }

    @MainActor static func filter(_ items: [PaletteItem], _ q: String) -> [PaletteItem] {
        if q.isEmpty { return items }
        return items.compactMap { i -> (PaletteItem, Int)? in
            guard let m = Fuzzy.match(q, i.title) else { return nil }
            var j = i; j.titleHits = m.positions
            return (j, m.score)
        }.sorted { $0.1 > $1.1 }.map(\.0)
    }

    /// Move to…: folders through the same matcher (on the full folder path).
    @MainActor static func folders(_ ws: Workspace, for srcs: [String], _ q: String) -> [PaletteItem] {
        let dests = ws.moveDestinations(for: srcs)
        let toks = QuickMatch.tokens(q)
        var scored: [(Int, PaletteItem)] = []
        for (i, f) in dests.enumerated() {
            let shown = f.isEmpty ? "Vault root" : f
            let key = MatchKey(shown)
            var score = 0, hits: [Int] = [], ok = true
            for t in toks {
                guard let m = QuickMatch.match(t, in: key) else { ok = false; break }
                score += m.score; hits += m.positions
            }
            guard ok else { continue }
            let item = PaletteItem(id: "folder:" + f, title: shown, subtitle: f.isEmpty ? "/" : "", symbol: "folder", titleHits: hits) {
                ws.show(.none); ws.move(srcs, toFolder: f)
            }
            scored.append((toks.isEmpty ? -i : score, item))
        }
        return scored.sorted { $0.0 > $1.0 }.prefix(60).map(\.1)
    }

    @MainActor static func notes(_ ws: Workspace, _ q: String) -> [PaletteItem] {
        guard let snap = ws.snapshot else { return [] }
        func item(_ path: String, _ title: String, _ folder: String) -> PaletteItem {
            PaletteItem(id: path, title: title, subtitle: folder,
                        openInSplit: { ws.split(.vertical); ws.openNote(path) }) { ws.openNote(path) }
        }
        if q.trimmingCharacters(in: .whitespaces).isEmpty {
            // recent notes; a fresh vault falls back to the most recently edited
            var paths = ws.recent.filter { snap.notes[$0] != nil || snap.attachments[$0] != nil }
            if paths.count < 12 {
                let edited = snap.notes.values.sorted { $0.mtime > $1.mtime }.map(\.path)
                for p in edited where !paths.contains(p) { paths.append(p); if paths.count >= 12 { break } }
            }
            return paths.prefix(12).compactMap { p in
                if let n = snap.notes[p] { return item(p, n.name, n.folder) }
                if p.opensInFileView, snap.attachments[p] != nil { return item(p, (p as NSString).lastPathComponent, (p as NSString).deletingLastPathComponent) }
                if snap.canvases[p] != nil || snap.bases[p] != nil {
                    return item(p, ((p as NSString).lastPathComponent as NSString).deletingPathExtension, (p as NSString).deletingLastPathComponent)
                }
                return nil
            }
        }
        return ws.quickIndex.search(q, recent: ws.recent).map { h in
            var i = item(h.entry.path, h.entry.name.text, h.entry.folder.text)
            i.titleHits = h.nameHits; i.subtitleHits = h.folderHits
            if let a = h.alias { i.badge = a; i.badgeHits = h.aliasHits }
            return i
        }
    }

    /// Notes to merge the open file into: Markdown only, excluding the current note.
    @MainActor static func mergeTargets(_ ws: Workspace, _ q: String) -> [PaletteItem] {
        noteChoices(ws, q, excluding: ws.currentPath, verb: "merge") { path in
            ws.confirmMerge(into: path)
        }
    }

    /// Notes that can receive an extracted selection: Markdown only, excluding the current note.
    @MainActor static func extractTargets(_ ws: Workspace, _ q: String) -> [PaletteItem] {
        noteChoices(ws, q, excluding: ws.currentPath, verb: "append") { path in
            ws.finishExtract(to: path, creating: false)
        }
    }

    @MainActor static func noteChoices(_ ws: Workspace, _ q: String, excluding: String?, verb: String, action: @escaping (String) -> Void) -> [PaletteItem] {
        guard let snap = ws.snapshot else { return [] }
        func item(_ path: String, _ title: String, _ folder: String) -> PaletteItem {
            PaletteItem(id: path, title: title, subtitle: folder.isEmpty ? verb : "\(folder) · \(verb)",
                        symbol: "doc") { action(path) }
        }
        let skip = excluding
        if q.trimmingCharacters(in: .whitespaces).isEmpty {
            var paths = ws.recent.filter { $0 != skip && snap.notes[$0] != nil }
            if paths.count < 12 {
                let edited = snap.notes.values.sorted { $0.mtime > $1.mtime }.map(\.path)
                for p in edited where p != skip && !paths.contains(p) { paths.append(p); if paths.count >= 12 { break } }
            }
            return paths.prefix(12).compactMap { p in
                snap.notes[p].map { item(p, $0.name, $0.folder) }
            }
        }
        return ws.quickIndex.search(q, recent: ws.recent).compactMap { h in
            let path = h.entry.path
            guard path != skip, snap.notes[path] != nil else { return nil }
            var i = item(path, h.entry.name.text, h.entry.folder.text)
            i.titleHits = h.nameHits; i.subtitleHits = h.folderHits
            if let a = h.alias { i.badge = a; i.badgeHits = h.aliasHits }
            return i
        }
    }
}
