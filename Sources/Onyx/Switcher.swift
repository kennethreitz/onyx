import SwiftUI
import OnyxCore

struct PaletteItem: Identifiable {
    var id: String
    var title: String
    var subtitle: String = ""
    var symbol: String? = nil
    var shortcut: String = ""
    var action: () -> Void
}

/// Spotlight-like list used by both the quick switcher (⌘O) and the command palette (⌘P).
struct PaletteView: View {
    var placeholder: String
    var items: (String) -> [PaletteItem]
    var onCreate: ((String) -> Void)? = nil
    var dismiss: () -> Void
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    var body: some View {
        let results = items(query)
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: onCreate != nil ? "doc.text.magnifyingglass" : "command").font(.system(size: 15)).foregroundStyle(Color.faint)
                TextField(placeholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(Theme.serif(21))
                    .focused($focused)
                    .onSubmit { activate(results) }
                    .onKeyPress(.downArrow) { selection = min(selection + 1, max(0, results.count - 1)); return .handled }
                    .onKeyPress(.upArrow) { selection = max(selection - 1, 0); return .handled }
                    .onKeyPress(.escape) { dismiss(); return .handled }
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            if !results.isEmpty || (onCreate != nil && !query.isEmpty) {
                Divider().overlay(Color.hairline)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { i, item in
                                row(item, selected: i == selection).id(i)
                                    .onTapGesture { item.action(); dismiss() }
                            }
                            if results.isEmpty, onCreate != nil {
                                HStack { Image(systemName: "plus").foregroundStyle(Color.faint); Text("Create “\(query)”").font(.system(size: 13)); Spacer(); Text("↩").foregroundStyle(Color.faint) }
                                    .padding(.horizontal, 18).padding(.vertical, 9)
                            }
                        }.padding(.vertical, 5)
                    }
                    .frame(maxHeight: 380)
                    .onChange(of: selection) { proxy.scrollTo(selection) }
                }
            }
        }
        .frame(width: 620)
        .panelChrome()
        .onAppear { focused = true }
        .onChange(of: query) { selection = 0 }
    }

    func row(_ item: PaletteItem, selected: Bool) -> some View {
        HStack(spacing: 10) {
            if let s = item.symbol { Image(systemName: s).font(.system(size: 12)).foregroundStyle(Color.muted).frame(width: 18) }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 13.5)).foregroundStyle(Color.ink).lineLimit(1)
                if !item.subtitle.isEmpty { Text(item.subtitle).font(.system(size: 11)).foregroundStyle(Color.faint).lineLimit(1) }
            }
            Spacer()
            if !item.shortcut.isEmpty { Text(item.shortcut).font(.system(size: 11.5, design: .rounded)).foregroundStyle(Color.faint) }
        }
        .padding(.horizontal, 18).padding(.vertical, item.subtitle.isEmpty ? 8 : 6)
        .background(selected ? Color.ink.opacity(0.07) : .clear)
        .contentShape(Rectangle())
    }

    func activate(_ results: [PaletteItem]) {
        if results.indices.contains(selection) { results[selection].action(); dismiss() }
        else if let c = onCreate, !query.isEmpty { c(query); dismiss() }
    }
}

enum PaletteCommands {
    @MainActor static func all(_ ws: Workspace, appearance: @escaping (String) -> Void) -> [PaletteItem] {
        [
            PaletteItem(id: "switcher", title: "Quick switcher", symbol: "doc.text.magnifyingglass", shortcut: "⌘O") { DispatchQueue.main.async { ws.show(.switcher) } },
            PaletteItem(id: "split", title: "Split side by side", symbol: "rectangle.split.2x1", shortcut: "⌘D") { ws.split(.vertical) },
            PaletteItem(id: "splitdown", title: "Split stacked", symbol: "rectangle.split.1x2", shortcut: "⇧⌘D") { ws.split(.horizontal) },
            PaletteItem(id: "closepane", title: "Close pane", symbol: "xmark.square", shortcut: "⌘W") { ws.closePane() },
            PaletteItem(id: "nextpane", title: "Next pane", symbol: "arrow.right.square", shortcut: "⌃⇥") { ws.focusNextPane() },
            PaletteItem(id: "daily", title: "Open today’s daily note", symbol: "calendar", shortcut: "⌘T  ⌘\\") { ws.openDaily() },
            PaletteItem(id: "daily-prev", title: "Previous daily note", symbol: "chevron.left", shortcut: "⌘[") { ws.openDaily(offset: -1) },
            PaletteItem(id: "daily-next", title: "Next daily note", symbol: "chevron.right", shortcut: "⌘]") { ws.openDaily(offset: 1) },
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
        return items.compactMap { i in Fuzzy.score(q, i.title).map { (i, $0) } }.sorted { $0.1 > $1.1 }.map(\.0)
    }

    @MainActor static func notes(_ ws: Workspace, _ q: String) -> [PaletteItem] {
        guard let snap = ws.snapshot else { return [] }
        if q.isEmpty {
            return ws.recent.prefix(12).compactMap { p in snap.notes[p].map { n in PaletteItem(id: p, title: n.name, subtitle: n.folder) { ws.openNote(p) } } }
        }
        var scored: [(NoteRecord, Int, String?)] = []
        for n in snap.notes.values {
            var best = Fuzzy.score(q, n.name).map { $0 + 10 }
            var via: String? = nil
            for a in n.aliases { if let s = Fuzzy.score(q, a), s > (best ?? Int.min) { best = s; via = a } }
            if best == nil, q.contains("/"), let s = Fuzzy.score(q, n.path) { best = s - 10 }
            if let b = best { scored.append((n, b, via)) }
        }
        scored.sort { $0.1 == $1.1 ? $0.0.path.count < $1.0.path.count : $0.1 > $1.1 }
        return scored.prefix(60).map { n, _, via in
            PaletteItem(id: n.path, title: n.name, subtitle: via.map { "alias: \($0) · " + n.folder } ?? n.folder) { ws.openNote(n.path) }
        }
    }
}
