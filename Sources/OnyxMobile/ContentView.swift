import SwiftUI
import UniformTypeIdentifiers
import OnyxCore

struct ContentView: View {
    @EnvironmentObject private var vault: MobileVault
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL
    @State private var picking = false
    @State private var connectingSync = false
    @State private var managingSync = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationTitle(vault.libraryTab.title)
                .modifier(NotesSearch(text: $vault.query, enabled: vault.libraryTab == .notes))
                .toolbar { toolbar }
                .refreshable { vault.scan() }
        } detail: {
            if let note = vault.selectedNote, let snap = vault.snapshot, let root = vault.root {
                ReaderScreen(note: note, snapshot: snap, vaultRoot: root, dark: scheme == .dark,
                             typesetRevision: vault.typesetRevision, jumpLine: vault.jumpLine, jumpToken: vault.jumpToken)
                    .navigationTitle(note.name)
                    .navigationBarTitleDisplayMode(.inline)
                    .id(note.path)
                    .toolbar { noteToolbar(note) }
            } else if vault.root == nil {
                ContentUnavailableView("Open a vault", systemImage: "folder",
                                       description: Text("Choose the folder that holds your notes — an Obsidian vault on this device or in iCloud Drive — or connect an Obsidian Sync vault."))
            } else {
                ContentUnavailableView("No note selected", systemImage: "doc")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .onyxOpenNote)) { n in
            if let info = n.userInfo, let p = info["path"] as? String {
                vault.openNote(p, line: info["line"] as? Int)
            } else if let p = n.object as? String {
                vault.openNote(p)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .onyxSearch)) { n in
            if let q = n.object as? String { vault.query = q; vault.libraryTab = .notes }
        }
        .onReceive(NotificationCenter.default.publisher(for: .onyxRevealTag)) { n in
            if let t = n.object as? String { vault.revealTag(t) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .onyxOpenURL)) { n in
            if let u = n.object as? URL { openURL(u) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .onyxLinkMention)) { n in
            guard let info = n.userInfo,
                  let source = info["source"] as? String,
                  let loc = info["loc"] as? Int,
                  let len = info["len"] as? Int,
                  let title = info["title"] as? String else { return }
            let matched = (info["matched"] as? String) ?? ""
            let mention = UnlinkedMention(source: source, line: 0, context: "", range: NSRange(location: loc, length: len), matched: matched, needle: title)
            _ = vault.linkMention(mention, title: title)
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { vault.open(url) }
            case .failure(let error):
                vault.error = error.localizedDescription
            }
        }
        .alert("Vault", isPresented: Binding(
            get: { vault.error != nil },
            set: { if !$0 { vault.error = nil } }
        )) {
            Button("OK", role: .cancel) { vault.error = nil }
        } message: {
            Text(vault.error ?? "")
        }
        .sheet(isPresented: $connectingSync) {
            NavigationStack { SyncConnectScreen().environmentObject(vault) }
        }
        .sheet(isPresented: $managingSync) {
            NavigationStack {
                ManageSyncScreen().environmentObject(vault)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { managingSync = false } } }
            }
        }
        .sheet(isPresented: $vault.showReadingSettings) {
            NavigationStack {
                ReadingSettingsScreen { vault.typesetRevision += 1 }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { vault.showReadingSettings = false } } }
            }
        }
        .sheet(isPresented: $vault.showHistory) {
            NavigationStack {
                HistoryScreen(noteName: vault.selectedNote?.name)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { vault.showHistory = false } } }
            }
        }
        .sheet(isPresented: $vault.showBacklinks) {
            NavigationStack {
                BacklinksScreen()
                    .environmentObject(vault)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { vault.showBacklinks = false } } }
            }
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        VStack(spacing: 0) {
            Picker("Library", selection: $vault.libraryTab) {
                ForEach(MobileVault.LibraryTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.symbol).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            Group {
                if vault.root == nil {
                    ContentUnavailableView {
                        Label("No vault", systemImage: "folder.badge.plus")
                    } description: {
                        Text("Open a folder of Markdown notes (iCloud Drive ▸ Obsidian works if the vault is there), or keep a sync-only copy of an Obsidian Sync vault inside Onyx.")
                    } actions: {
                        Button("Open Vault") { picking = true }
                        Button("Connect Obsidian Sync Vault") { connectingSync = true }
                        let local = vault.managedVaults
                        if !local.isEmpty {
                            Menu("Sync-only Vaults on This Device") {
                                ForEach(local) { v in Button(v.name) { vault.openManaged(v) } }
                                Divider()
                                Button("Manage…") { managingSync = true }
                            }
                        }
                    }
                } else {
                    switch vault.libraryTab {
                    case .notes: notesList
                    case .bookmarks: BookmarksScreen()
                    case .tags: TagsScreen()
                    case .outline: OutlineScreen()
                    case .find: FindScreen()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var notesList: some View {
        if let folder = vault.folderFilter {
            HStack {
                Text(folder.isEmpty ? "Vault root" : folder)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Clear") { vault.folderFilter = nil }
                    .font(.caption)
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
        if vault.visibleNotes.isEmpty {
            ContentUnavailableView.search(text: vault.query)
        } else {
            List(vault.visibleNotes, id: \.path, selection: $vault.selectedPath) { note in
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.name).lineLimit(1)
                    if !note.folder.isEmpty {
                        Text(note.folder)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .tag(note.path)
                .swipeActions(edge: .trailing) {
                    if vault.canWrite && !vault.bookmarksLocked {
                        let on = vault.isBookmarked(note.path)
                        Button { _ = vault.toggleBookmark(note.path) } label: {
                            Label(on ? "Unpin" : "Pin", systemImage: on ? "bookmark.slash" : "bookmark")
                        }
                        .tint(.orange)
                    }
                }
                .contextMenu {
                    Button(vault.isBookmarked(note.path) ? "Remove Bookmark" : "Bookmark") {
                        _ = vault.toggleBookmark(note.path)
                    }
                    .disabled(!vault.canWrite || vault.bookmarksLocked)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Button("Open Vault…", systemImage: "folder") { picking = true }
                Button("Connect Obsidian Sync Vault…", systemImage: "icloud") { connectingSync = true }
                if vault.isSyncOnly || !vault.managedVaults.isEmpty {
                    Button("Manage Sync…", systemImage: "arrow.triangle.2.circlepath.icloud") { managingSync = true }
                }
                if vault.isSyncOnly {
                    Button("Sync Now", systemImage: "arrow.triangle.2.circlepath") { vault.syncNow() }
                }
                if vault.dailyPath != nil {
                    Button("Today’s daily note", systemImage: "calendar") { vault.openDaily() }
                }
                if vault.root != nil {
                    Button("Refresh", systemImage: "arrow.clockwise") { vault.scan() }
                    Button("Reading…", systemImage: "textformat") { vault.showReadingSettings = true }
                    Divider()
                    Button("Close Vault", systemImage: "xmark.circle", role: .destructive) { vault.forgetVault() }
                }
            } label: {
                Label("Vault", systemImage: "folder")
            }
        }
        if let name = vault.root?.lastPathComponent {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Text(name).font(.headline)
                    if vault.isSyncOnly {
                        let s = vault.syncStatus
                        Button { managingSync = true } label: {
                            Image(systemName: s?.symbol ?? "icloud").font(.caption)
                                .foregroundStyle(s?.isProblem == true ? Color.orange : Color.secondary)
                        }
                        .accessibilityLabel("Obsidian Sync: \(s?.text ?? "not running")")
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private func noteToolbar(_ note: NoteRecord) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button(vault.isBookmarked(note.path) ? "Remove Bookmark" : "Bookmark",
                       systemImage: vault.isBookmarked(note.path) ? "bookmark.slash" : "bookmark") {
                    _ = vault.toggleBookmark(note.path)
                }
                .disabled(!vault.canWrite || vault.bookmarksLocked)
                Button("Backlinks", systemImage: "arrow.uturn.backward") { vault.showBacklinks = true }
                Button("Outline", systemImage: "list.bullet.indent") { vault.libraryTab = .outline }
                Button("Version History", systemImage: "clock.arrow.circlepath") { vault.showHistory = true }
                Divider()
                Button("Reading…", systemImage: "textformat") { vault.showReadingSettings = true }
            } label: {
                Label("Note", systemImage: "ellipsis.circle")
            }
        }
    }
}


private struct NotesSearch: ViewModifier {
    @Binding var text: String
    var enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.searchable(text: $text, prompt: "Search notes")
        } else {
            content
        }
    }
}
