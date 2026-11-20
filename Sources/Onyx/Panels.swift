import SwiftUI
import OnyxCore

/// The shared look of every summoned surface: paper, a hairline, a soft shadow.
struct PanelChrome: ViewModifier {
    var pinned: Bool
    func body(content: Content) -> some View {
        content
            .background(Color.secondaryPaper)
            .clipShape(RoundedRectangle(cornerRadius: pinned ? 0 : 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: pinned ? 0 : 12, style: .continuous).strokeBorder(Color.hairline, lineWidth: pinned ? 0 : 0.8))
            .shadow(color: .black.opacity(pinned ? 0 : 0.10), radius: 18, x: 0, y: 8)
    }
}
extension View { func panelChrome(pinned: Bool = false) -> some View { modifier(PanelChrome(pinned: pinned)) } }

struct PanelHeader<Tab: Identifiable & Hashable>: View {
    var tabs: [Tab]
    @Binding var selection: Tab
    var symbol: (Tab) -> String
    var label: (Tab) -> String
    @Binding var pinned: Bool
    var onPin: ((Bool) -> Void)? = nil
    var body: some View {
        // tabs compress (28pt → 17pt each) so the header still fits a 140pt sidebar
        HStack(spacing: 1) {
            ForEach(tabs) { t in
                Button { withAnimation(.easeOut(duration: 0.15)) { selection = t } } label: {
                    Image(systemName: symbol(t))
                        .font(.system(size: 12.5, weight: selection == t ? .semibold : .regular))
                        .frame(minWidth: 17, idealWidth: 28, maxWidth: 28, minHeight: 24, maxHeight: 24)
                        .foregroundStyle(selection == t ? Color.ink : Color.faint)
                        .background(selection == t ? Color.ink.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(label(t))
            }
            Spacer(minLength: 0)
            Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) { pinned.toggle() }; onPin?(pinned) } label: {
                Image(systemName: pinned ? "pin.fill" : "pin").font(.system(size: 11)).foregroundStyle(Color.faint).frame(width: 20, height: 24)
            }.buttonStyle(.plain).help(pinned ? "Unpin" : "Pin (three-pane layout)")
        }
        .padding(.horizontal, 6).padding(.top, 8).padding(.bottom, 4)
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Bindable var ws: Workspace
    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(tabs: SidebarTab.allCases, selection: $ws.sidebarTab, symbol: \.symbol, label: \.title, pinned: $ws.sidebarPinned, onPin: { UserDefaults.standard.set($0, forKey: "onyx.sidebarOpen") })
            Divider().overlay(Color.hairline)
            Group {
                switch ws.sidebarTab {
                case .files: FileTreeView(ws: ws)
                case .search: SearchPanel(ws: ws)
                case .recent: PathList(ws: ws, paths: ws.recent.filter { ws.snapshot?.notes[$0] != nil }, empty: "Nothing opened yet.")
                case .bookmarks: BookmarksPanel(ws: ws)
                case .tags: TagsPanel(ws: ws)
                case .git: GitPanel(ws: ws)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if ws.sidebarTab == .files, let snap = ws.snapshot {
                Divider().overlay(Color.hairline)
                HStack {
                    Text("\(snap.notes.count) notes").font(.system(size: 10.5)).foregroundStyle(Color.faint)
                    Spacer()
                    Button { ws.newNote() } label: { Image(systemName: "square.and.pencil") }.buttonStyle(.plain).foregroundStyle(Color.muted).help("New note (⌘N)")
                }.padding(.horizontal, 12).padding(.vertical, 7)
            }
        }
    }
}

struct FileTreeView: View {
    @Bindable var ws: Workspace
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let tree = ws.snapshot?.tree {
                        ForEach(tree.children ?? []) { node in TreeNodeView(ws: ws, node: node, depth: 0) }
                    } else {
                        ProgressView().controlSize(.small).padding()
                    }
                }
                .padding(.vertical, 6)
            }
            .onAppear { if let p = ws.selectedFolder ?? ws.currentPath { DispatchQueue.main.async { proxy.scrollTo(p, anchor: .center) } } }
            .onChange(of: ws.revealToken) {
                guard let f = ws.selectedFolder else { return }
                // let the expansion lay out first, then glide to the folder
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(f, anchor: .center) } }
            }
        }
    }
}

struct TreeNodeView: View {
    @Bindable var ws: Workspace
    let node: FileNode
    let depth: Int
    @State private var hover = false

    var isOpen: Bool { ws.expanded.contains(node.path) }
    var isCurrent: Bool {
        ws.currentPath == node.path || (node.folderNote != nil && ws.currentPath == node.folderNote) || (node.isFolder && ws.selectedFolder == node.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                if node.isFolder {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .foregroundStyle(Color.faint)
                        .frame(width: 12)
                        .contentShape(Rectangle())
                        .onTapGesture { toggle() }
                } else {
                    Spacer().frame(width: 12)
                }
                Text(node.displayName)
                    .font(.system(size: 12.5, weight: node.isFolder ? .medium : .regular))
                    .foregroundStyle(node.isNote || node.isFolder ? Color.ink : Color.faint)
                    .underline(node.folderNote != nil, color: Color.faint.opacity(0.45))
                    .lineLimit(1).truncationMode(.middle)
                if !node.isFolder && !node.isNote {
                    Text((node.name as NSString).pathExtension.uppercased()).font(.system(size: 8.5, weight: .medium)).foregroundStyle(Color.faint)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(depth) * 13 + 8).padding(.trailing, 8)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 5).fill(isCurrent ? Color.ink.opacity(0.08) : (hover ? Color.ink.opacity(0.04) : .clear)).padding(.horizontal, 5))
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .onTapGesture { activate() }
            .id(node.path)
            .contextMenu {
                if node.isNote || node.folderNote != nil {
                    Button("Open") { activate() }
                    Button("Reveal in Finder") { if let r = ws.root { NSWorkspace.shared.activateFileViewerSelecting([r.appendingPathComponent(node.folderNote ?? node.path)]) } }
                }
                if node.isFolder { Button("New Note Here") { ws.createNote(named: "Untitled", folder: node.path) } }
            }
            if node.isFolder && isOpen {
                ForEach(node.children ?? []) { c in TreeNodeView(ws: ws, node: c, depth: depth + 1) }
            }
        }
    }

    func toggle() {
        withAnimation(.easeOut(duration: 0.12)) {
            if isOpen { ws.expanded.remove(node.path) } else { ws.expanded.insert(node.path) }
        }
    }
    func activate() {
        if node.isFolder {
            if let fn = node.folderNote { ws.expanded.insert(node.path); ws.openNote(fn) } else { toggle() }
        } else if node.isNote { ws.openNote(node.path) }
        else if let r = ws.root { NSWorkspace.shared.open(r.appendingPathComponent(node.path)) }
    }
}

struct PathList: View {
    @Bindable var ws: Workspace
    var paths: [String]
    var empty: String
    var body: some View {
        if paths.isEmpty {
            Text(empty).font(.system(size: 12)).foregroundStyle(Color.faint).padding(16).frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(paths, id: \.self) { p in NoteRow(ws: ws, path: p) }
                }.padding(.vertical, 6)
            }
        }
    }
}

struct NoteRow: View {
    @Bindable var ws: Workspace
    var path: String
    var detail: String? = nil
    @State private var hover = false
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(((path as NSString).lastPathComponent as NSString).deletingPathExtension).font(.system(size: 12.5)).foregroundStyle(Color.ink).lineLimit(1)
            Text(detail ?? (path as NSString).deletingLastPathComponent).font(.system(size: 10.5)).foregroundStyle(Color.faint).lineLimit(detail == nil ? 1 : 3)
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 5).fill(ws.currentPath == path ? Color.ink.opacity(0.08) : (hover ? Color.ink.opacity(0.04) : .clear)).padding(.horizontal, 5))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { ws.openNote(path) }
    }
}

struct SearchPanel: View {
    @Bindable var ws: Workspace
    @State private var hits: [SearchHit] = []
    @State private var task: Task<Void, Never>?
    @State private var millis = 0
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Color.faint)
                TextField("Search vault  ·  tag:  path:  \"phrase\"", text: $ws.searchQuery)
                    .textFieldStyle(.plain).font(.system(size: 12.5)).focused($focused)
            }
            .padding(8).background(Color.paper, in: RoundedRectangle(cornerRadius: 7)).overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.hairline))
            .padding(10)
            if !ws.searchQuery.isEmpty {
                Text("\(hits.count == 200 ? "200+" : String(hits.count)) results · \(millis) ms").font(.system(size: 10.5)).foregroundStyle(Color.faint)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.bottom, 4)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(hits) { h in NoteRow(ws: ws, path: h.path, detail: h.snippets.first ?? (h.path as NSString).deletingLastPathComponent) }
                }
            }
        }
        .onAppear { focused = true; run() }
        .onChange(of: ws.searchQuery) { run() }
        .onChange(of: ws.focusSearch) { focused = true }
    }
    func run() {
        task?.cancel()
        let q = ws.searchQuery
        guard let snap = ws.snapshot, !q.trimmingCharacters(in: .whitespaces).isEmpty else { hits = []; return }
        task = Task {
            try? await Task.sleep(nanoseconds: 90_000_000)
            if Task.isCancelled { return }
            let t0 = Date()
            let r = await Task.detached { snap.search(q) }.value
            if !Task.isCancelled { hits = r; millis = Int(Date().timeIntervalSince(t0) * 1000) }
        }
    }
}

struct BookmarksPanel: View {
    @Bindable var ws: Workspace
    var body: some View {
        VStack(spacing: 0) {
            PathList(ws: ws, paths: ws.bookmarks, empty: "No bookmarks yet.")
            if let p = ws.currentPath {
                Divider().overlay(Color.hairline)
                Button { ws.toggleBookmark() } label: {
                    Label(ws.bookmarks.contains(p) ? "Remove bookmark" : "Bookmark this note", systemImage: ws.bookmarks.contains(p) ? "bookmark.slash" : "bookmark")
                        .font(.system(size: 11.5)).frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).foregroundStyle(Color.muted).padding(10)
            }
        }
    }
}

struct TagsPanel: View {
    @Bindable var ws: Workspace
    func sortedTags() -> [(String, Int)] {
        let pairs: [(String, Int)] = (ws.snapshot?.tags ?? [:]).map { (k, v) in (k, v.count) }
        return pairs.sorted { (a: (String, Int), b: (String, Int)) -> Bool in a.1 == b.1 ? a.0 < b.0 : a.1 > b.1 }
    }
    var body: some View {
        let tags = sortedTags()
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(tags, id: \.0) { t in
                    HStack {
                        Text("#" + t.0).font(.custom("IBMPlexMono", size: 11.5)).foregroundStyle(Color.ink)
                        Spacer()
                        Text("\(t.1)").font(.system(size: 10.5)).foregroundStyle(Color.faint)
                    }
                    .padding(.horizontal, 12).frame(height: 24).contentShape(Rectangle())
                    .onTapGesture { ws.searchQuery = "tag:" + t.0; ws.sidebarTab = .search }
                }
            }.padding(.vertical, 6)
        }
    }
}

// MARK: - Inspector

struct InspectorView: View {
    @Bindable var ws: Workspace
    @State private var showUnlinked = false
    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(tabs: InspectorTab.allCases, selection: $ws.inspectorTab, symbol: \.symbol, label: { $0.rawValue.capitalized }, pinned: $ws.inspectorPinned)
            Divider().overlay(Color.hairline)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let note = ws.currentNote, let snap = ws.snapshot {
                        switch ws.inspectorTab {
                        case .outline: outline(note)
                        case .backlinks: backlinks(note, snap)
                        case .properties: properties(note, snap)
                        }
                    }
                }.padding(.vertical, 8)
            }
        }
    }

    func sectionTitle(_ s: String) -> some View {
        Text(s.uppercased()).font(.system(size: 9.5, weight: .semibold)).tracking(0.8).foregroundStyle(Color.faint).padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 4)
    }

    @ViewBuilder func outline(_ note: NoteRecord) -> some View {
        let hs = NoteParser.parseHeadings(ws.text)
        if hs.isEmpty { Text("No headings.").font(.system(size: 12)).foregroundStyle(Color.faint).padding(14) }
        let minLevel = hs.map(\.level).min() ?? 1
        ForEach(Array(hs.enumerated()), id: \.offset) { i, h in
            Text(h.text)
                .font(Theme.serif(h.level == minLevel ? 14 : 13, bold: h.level == minLevel))
                .foregroundStyle(h.level <= minLevel + 1 ? Color.ink : Color.muted)
                .lineLimit(2)
                .padding(.leading, 14 + CGFloat(h.level - minLevel) * 12).padding(.trailing, 12).padding(.vertical, 3.5)
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                .onTapGesture { ws.readerJump = i; ws.editorJump = h.line }
        }
    }

    @ViewBuilder func backlinks(_ note: NoteRecord, _ snap: VaultSnapshot) -> some View {
        let links = snap.backlinks(to: note.path)
        sectionTitle("Linked mentions · \(links.count)")
        if links.isEmpty { Text("Nothing links here yet.").font(.system(size: 12)).foregroundStyle(Color.faint).padding(.horizontal, 14).padding(.vertical, 4) }
        ForEach(links, id: \.self) { b in
            NoteRow(ws: ws, path: b.source, detail: b.context.isEmpty ? nil : NoteParser.stripInline(b.context))
        }
        Button { showUnlinked.toggle() } label: {
            HStack { Image(systemName: "chevron.right").rotationEffect(.degrees(showUnlinked ? 90 : 0)).font(.system(size: 8)); Text("UNLINKED MENTIONS").font(.system(size: 9.5, weight: .semibold)).tracking(0.8) }
                .foregroundStyle(Color.faint)
        }.buttonStyle(.plain).padding(.horizontal, 14).padding(.top, 14)
        if showUnlinked {
            ForEach(snap.unlinkedMentions(of: note.path), id: \.self) { b in NoteRow(ws: ws, path: b.source, detail: b.context) }
        }
    }

    @ViewBuilder func properties(_ note: NoteRecord, _ snap: VaultSnapshot) -> some View {
        let fm = Frontmatter.parse(ws.text)
        sectionTitle("Properties")
        if fm.properties.isEmpty { Text("No properties.").font(.system(size: 12)).foregroundStyle(Color.faint).padding(.horizontal, 14) }
        ForEach(fm.properties, id: \.self) { p in
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: icon(p.value)).font(.system(size: 10)).foregroundStyle(Color.faint).frame(width: 14)
                Text(p.key).font(.system(size: 11.5)).foregroundStyle(Color.muted).frame(width: 84, alignment: .leading).lineLimit(1)
                Text(p.value.display).font(.system(size: 11.5)).foregroundStyle(Color.ink).textSelection(.enabled).lineLimit(4)
                Spacer(minLength: 0)
            }.padding(.horizontal, 14).padding(.vertical, 3)
        }
        sectionTitle("Note")
        let s = NoteParser.summarize(ws.text)
        info("Words", "\(s.wordCount)")
        info("Links out", "\(s.links.count)")
        info("Backlinks", "\(snap.backlinks[note.path]?.count ?? 0)")
        if !s.tags.isEmpty { info("Tags", s.tags.map { "#" + $0 }.joined(separator: " ")) }
        info("Modified", note.mtime.formatted(date: .abbreviated, time: .shortened))
        info("Created", note.ctime.formatted(date: .abbreviated, time: .omitted))
        info("Path", note.path)
    }
    func info(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k).font(.system(size: 11.5)).foregroundStyle(Color.muted).frame(width: 98, alignment: .leading)
            Text(v).font(.system(size: 11.5)).foregroundStyle(Color.ink).textSelection(.enabled).lineLimit(3)
            Spacer(minLength: 0)
        }.padding(.horizontal, 14).padding(.vertical, 2.5)
    }
    func icon(_ v: PropertyValue) -> String {
        switch v { case .list: return "list.bullet"; case .number: return "number"; case .bool: return "checkmark.square"; case .string: return "text.alignleft" }
    }
}

// MARK: - Git (obsidian-git, the essentials)

struct GitPanel: View {
    @Bindable var ws: Workspace
    @State private var branch = ""
    @State private var changes: [(String, String)] = []
    @State private var message = ""
    @State private var status = ""
    @State private var isRepo = true
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !isRepo {
                Text("This vault isn’t a git repository.").font(.system(size: 12)).foregroundStyle(Color.faint).padding(14)
            } else {
                HStack {
                    Image(systemName: "arrow.triangle.branch").foregroundStyle(Color.faint)
                    Text(branch).font(.custom("IBMPlexMono", size: 11.5))
                    Spacer()
                    Button { refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).foregroundStyle(Color.muted)
                }.padding(.horizontal, 12).padding(.top, 10)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(changes, id: \.1) { c in
                            HStack(spacing: 8) {
                                Text(c.0).font(.custom("IBMPlexMono", size: 10.5)).foregroundStyle(Color.muted).frame(width: 20, alignment: .leading)
                                Text(c.1).font(.system(size: 11.5)).lineLimit(1).truncationMode(.middle)
                            }.padding(.horizontal, 12).padding(.vertical, 3)
                        }
                    }
                }
                if changes.isEmpty { Text("Working tree clean.").font(.system(size: 12)).foregroundStyle(Color.faint).padding(.horizontal, 12) }
                TextField("Commit message", text: $message).textFieldStyle(.roundedBorder).font(.system(size: 12)).padding(.horizontal, 10)
                HStack {
                    Button("Commit all") { commit() }.disabled(changes.isEmpty)
                    Spacer()
                    Text(status).font(.system(size: 10.5)).foregroundStyle(Color.faint).lineLimit(2)
                }.padding(.horizontal, 10).padding(.bottom, 10)
            }
        }
        .onAppear { refresh() }
    }
    func git(_ args: [String]) -> (Int32, String) {
        guard let root = ws.root else { return (1, "") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", root.path] + args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return (1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }
    func refresh() {
        let (code, out) = git(["rev-parse", "--abbrev-ref", "HEAD"])
        isRepo = code == 0
        guard isRepo else { return }
        branch = out.trimmingCharacters(in: .whitespacesAndNewlines)
        changes = git(["status", "--porcelain"]).1.split(separator: "\n").map { l in
            (String(l.prefix(2)).trimmingCharacters(in: .whitespaces), String(l.dropFirst(3)))
        }
    }
    func commit() {
        ws.flushSave()
        let msg = message.isEmpty ? "vault backup: \(Workspace.stamp())" : message
        _ = git(["add", "-A"])
        let (code, out) = git(["commit", "-m", msg])
        status = code == 0 ? "Committed." : out
        message = ""
        refresh()
    }
}
