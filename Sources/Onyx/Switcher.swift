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
    var dismiss: () -> Void
    @State private var query = ""
    @State private var results: [PaletteItem] = []
    @State private var selection = 0
    @State private var monitor: Any?
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
                                Text("RECENT").font(.system(size: 9.5, weight: .semibold)).tracking(1.2).foregroundStyle(Color.faint)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 2)
                            }
                            // keyed by position, matching the .id used for scrollTo (two identities confuse LazyVStack)
                            ForEach(Array(results.enumerated()), id: \.offset) { i, item in
                                row(item, selected: i == selection).id(i)
                                    .onTapGesture { selection = i; activate(split: NSEvent.modifierFlags.contains(.command)) }
                            }
                            if showCreate {
                                createRow(selected: selection == createIndex).id(createIndex)
                                    .onTapGesture { create() }
                            }
                        }.padding(.vertical, 5)
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
        // Nothing found: the Create row is the thing to do
        selection = results.isEmpty && showCreate ? createIndex : 0
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
            Text(k).font(.system(size: 10.5, weight: .medium, design: .rounded)).foregroundStyle(Color.muted)
            Text(label).font(.system(size: 10.5)).foregroundStyle(Color.faint)
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

    func row(_ item: PaletteItem, selected: Bool) -> some View {
        HStack(spacing: 10) {
            if let s = item.symbol { Image(systemName: s).font(.system(size: 12)).foregroundStyle(Color.muted).frame(width: 18) }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Self.highlighted(item.title, item.titleHits, base: .ink.opacity(0.82), hit: .ink, size: 13.5).lineLimit(1)
                    if !item.badge.isEmpty {
                        Self.highlighted(item.badge, item.badgeHits, base: .faint, hit: .muted, size: 11).lineLimit(1)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.hairline))
                    }
                }
                if !item.subtitle.isEmpty {
                    Self.highlighted(item.subtitle, item.subtitleHits, base: .faint, hit: .muted, size: 11).lineLimit(1).truncationMode(.head)
                }
            }
            Spacer()
            if !item.shortcut.isEmpty { Text(item.shortcut).font(.system(size: 11.5, design: .rounded)).foregroundStyle(Color.faint) }
        }
        .padding(.horizontal, 18).padding(.vertical, item.subtitle.isEmpty ? 8 : 6)
        .background(selected ? Color.ink.opacity(0.07) : .clear)
        .contentShape(Rectangle())
    }

    func createRow(selected: Bool) -> some View {
        let (folder, name) = Self.split(trimmed)
        return HStack(spacing: 10) {
            Image(systemName: "plus").font(.system(size: 12)).foregroundStyle(Color.muted).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                (Text("Create ").foregroundColor(.muted) + Text(name).foregroundColor(.ink).fontWeight(.medium)).font(.system(size: 13.5)).lineLimit(1)
                Text(folder.isEmpty ? "new \(noun) in the vault root" : "new \(noun) in \(folder)").font(.system(size: 11)).foregroundStyle(Color.faint).lineLimit(1)
            }
            Spacer()
            Text("⇧↩").font(.system(size: 11.5, design: .rounded)).foregroundStyle(Color.faint)
        }
        .padding(.horizontal, 18).padding(.vertical, 6)
        .background(selected ? Color.ink.opacity(0.07) : .clear)
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
        [
            PaletteItem(id: "switcher", title: "Quick switcher", symbol: "doc.text.magnifyingglass", shortcut: "⌘O") { DispatchQueue.main.async { ws.show(.switcher) } },
            PaletteItem(id: "rename", title: "Rename note…", symbol: "pencil.line") { DispatchQueue.main.async { ws.confirmRenameCurrent() } },
            PaletteItem(id: "move", title: "Move note to…", symbol: "folder", shortcut: "⇧⌘M") { DispatchQueue.main.async { ws.beginMoveCurrent() } },
            PaletteItem(id: "delete", title: "Delete note…", symbol: "trash", shortcut: "⌘⌫") { DispatchQueue.main.async { ws.confirmTrashCurrent() } },
            PaletteItem(id: "split", title: "Split side by side", symbol: "rectangle.split.2x1", shortcut: "⌘D") { ws.split(.vertical) },
            PaletteItem(id: "splitdown", title: "Split stacked", symbol: "rectangle.split.1x2", shortcut: "⇧⌘D") { ws.split(.horizontal) },
            PaletteItem(id: "closepane", title: "Close pane", symbol: "xmark.square", shortcut: "⌘W") { ws.closePane() },
            PaletteItem(id: "nextpane", title: "Next pane", symbol: "arrow.right.square", shortcut: "⌃⇥") { ws.focusNextPane() },
            PaletteItem(id: "daily", title: "Open today’s daily note", symbol: "calendar", shortcut: "⌘T  ⌘\\") { ws.openDaily() },
            PaletteItem(id: "back", title: "Back", symbol: "chevron.left", shortcut: "⌘[") { ws.goBack() },
            PaletteItem(id: "forward", title: "Forward", symbol: "chevron.right", shortcut: "⌘]") { ws.goForward() },
            PaletteItem(id: "daily-prev", title: "Previous daily note", symbol: "calendar.badge.minus", shortcut: "⌥⌘[") { ws.openDaily(offset: -1) },
            PaletteItem(id: "daily-next", title: "Next daily note", symbol: "calendar.badge.plus", shortcut: "⌥⌘]") { ws.openDaily(offset: 1) },
            PaletteItem(id: "home", title: "Open homepage", symbol: "house", shortcut: "⌘⇧H") { ws.openHome() },
            PaletteItem(id: "mode", title: ws.mode == .read ? "Edit this note" : "Read this note", symbol: ws.mode == .read ? "pencil" : "book", shortcut: "⌘↩") { ws.toggleMode() },
            PaletteItem(id: "new", title: "New note", symbol: "square.and.pencil", shortcut: "⌘N") { ws.newNote() },
            PaletteItem(id: "files", title: "Show files", symbol: "folder", shortcut: "⌘K") { ws.toggleSidebar(.files) },
            PaletteItem(id: "search", title: "Search vault", symbol: "magnifyingglass", shortcut: "⌘⇧F") { ws.sidebarTab = .search; if !ws.sidebarVisible { ws.toggleSidebar() }; ws.focusSearch += 1 },
            PaletteItem(id: "recent", title: "Recent files", symbol: "clock") { ws.toggleSidebar(.recent) },
            PaletteItem(id: "bookmarks", title: "Bookmarks", symbol: "bookmark") { ws.toggleSidebar(.bookmarks) },
            PaletteItem(id: "bookmark", title: "Bookmark / unbookmark this note", symbol: "bookmark.fill") { ws.toggleBookmark() },
            PaletteItem(id: "tags", title: "Tags", symbol: "number") { ws.toggleSidebar(.tags) },
            PaletteItem(id: "git", title: "Source control", symbol: "arrow.triangle.branch") { ws.toggleSidebar(.git) },
            PaletteItem(id: "inspector", title: "Show inspector (outline, backlinks, properties)", symbol: "sidebar.right", shortcut: "⌘I") { ws.toggleInspector() },
            PaletteItem(id: "outline", title: "Outline", symbol: "list.bullet.indent") { ws.toggleInspector(.outline) },
            PaletteItem(id: "backlinks", title: "Backlinks", symbol: "arrow.uturn.backward") { ws.toggleInspector(.backlinks) },
            PaletteItem(id: "props", title: "Properties", symbol: "tablecells") { ws.toggleInspector(.properties) },
            PaletteItem(id: "graph", title: "Graph: focus on this note", symbol: "point.3.connected.trianglepath.dotted", shortcut: "⌘G") { DispatchQueue.main.async { ws.graphAtlas = false; ws.show(.graph) } },
            PaletteItem(id: "atlas", title: "Graph: atlas of the vault", symbol: "circle.hexagongrid", shortcut: "⇧⌘G") { DispatchQueue.main.async { ws.graphAtlas = true; ws.show(.graph) } },
            PaletteItem(id: "focus", title: ws.focusMode ? "Leave focus mode" : "Focus mode (just the text)", symbol: "arrow.up.left.and.arrow.down.right", shortcut: "⌃⌘F") { ws.toggleFocusMode() },
            PaletteItem(id: "layout", title: "Toggle three-pane workspace", symbol: "rectangle.split.3x1", shortcut: "⌘⌥0") { ws.toggleWorkspaceLayout() },
            PaletteItem(id: "rhymes", title: ws.rhymesOn ? "Turn rhyme view off" : "Toggle rhyme view (RhymePad)", symbol: "music.note", shortcut: "⌘⌥R") { ws.rhymesOn.toggle(); if ws.rhymesOn { ws.mode = .edit } },
            PaletteItem(id: "sidenotes", title: ws.sidenotes ? "Footnotes at the end" : "Footnotes as sidenotes", symbol: "text.append") { ws.sidenotes.toggle() },
            PaletteItem(id: "light", title: "Appearance: light", symbol: "sun.max") { appearance("light") },
            PaletteItem(id: "dark", title: "Appearance: dark", symbol: "moon") { appearance("dark") },
            PaletteItem(id: "system", title: "Appearance: match system", symbol: "circle.lefthalf.filled") { appearance("system") },
            PaletteItem(id: "copy", title: "Copy wikilink to this note", symbol: "link") { ws.copyWikilink() },
            PaletteItem(id: "finder", title: "Reveal in Finder", symbol: "folder.badge.gearshape") { ws.revealInFinder() },
            PaletteItem(id: "obsidian", title: "Open in Obsidian", symbol: "arrow.up.forward.app") { ws.openInObsidian() },
            PaletteItem(id: "reindex", title: "Rebuild index", symbol: "arrow.clockwise") { ws.reindex() },
        ]
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
            var paths = ws.recent.filter { snap.notes[$0] != nil || snap.canvases[$0] != nil }
            if paths.count < 12 {
                let edited = snap.notes.values.sorted { $0.mtime > $1.mtime }.map(\.path)
                for p in edited where !paths.contains(p) { paths.append(p); if paths.count >= 12 { break } }
            }
            return paths.prefix(12).compactMap { p in
                if let n = snap.notes[p] { return item(p, n.name, n.folder) }
                return snap.canvases[p] == nil ? nil : item(p, ((p as NSString).lastPathComponent as NSString).deletingPathExtension, (p as NSString).deletingLastPathComponent)
            }
        }
        return ws.quickIndex.search(q, recent: ws.recent).map { h in
            var i = item(h.entry.path, h.entry.name.text, h.entry.folder.text)
            i.titleHits = h.nameHits; i.subtitleHits = h.folderHits
            if let a = h.alias { i.badge = a; i.badgeHits = h.aliasHits }
            return i
        }
    }
}
