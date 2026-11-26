import SwiftUI
import OnyxCore

/// A compact command palette: jump to a note, or run an iOS command.
struct CommandPaletteScreen: View {
    @EnvironmentObject private var vault: MobileVault
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            List {
                let items = vault.paletteItems(query: query)
                if items.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    ForEach(items) { item in
                        Button {
                            item.action()
                            dismiss()
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).foregroundStyle(.primary).lineLimit(1)
                                    if !item.subtitle.isEmpty {
                                        Text(item.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            } icon: {
                                Image(systemName: item.symbol)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Command Palette")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, isPresented: .constant(true), prompt: "Go to a note or run a command")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear { focused = true }
        }
    }
}

struct MobilePaletteItem: Identifiable {
    var id: String
    var title: String
    var subtitle: String = ""
    var symbol: String
    var action: () -> Void
}

extension MobileVault {
    /// Notes (recent or matching) followed by the commands that work on iOS.
    func paletteItems(query: String) -> [MobilePaletteItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = paletteNotes(query: q)
        let commands = paletteCommands().compactMap { item -> MobilePaletteItem? in
            guard !q.isEmpty else { return item }
            guard Fuzzy.match(q, item.title) != nil || Fuzzy.match(q, item.subtitle) != nil else { return nil }
            return item
        }
        return notes + commands
    }

    /// Recent notes when `query` is empty, otherwise vault search hits — the same list as quick-open.
    func quickOpenItems(query: String) -> [MobilePaletteItem] {
        paletteNotes(query: query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func paletteNotes(query: String) -> [MobilePaletteItem] {
        guard let snap = snapshot else { return [] }
        func item(_ n: NoteRecord) -> MobilePaletteItem {
            MobilePaletteItem(id: "note:\(n.path)", title: n.name, subtitle: n.folder, symbol: "doc.text") { [weak self] in
                self?.openNote(n.path)
            }
        }
        if query.isEmpty {
            return snap.notes.values.sorted { $0.mtime > $1.mtime }.prefix(12).map(item)
        }
        return snap.search(query).compactMap { snap.notes[$0.path].map(item) }
    }

    private func paletteCommands() -> [MobilePaletteItem] {
        var items: [MobilePaletteItem] = []
        if canWrite {
            items.append(MobilePaletteItem(id: "new", title: "New note", symbol: "square.and.pencil") { [weak self] in self?.beginNewNote() })
            items.append(MobilePaletteItem(id: "newfolder", title: "New folder", symbol: "folder.badge.plus") { [weak self] in self?.beginNewFolder() })
        }
        if dailyPath != nil {
            items.append(MobilePaletteItem(id: "daily", title: "Open today’s daily note", symbol: "calendar") { [weak self] in self?.openDaily() })
        }
        items.append(MobilePaletteItem(id: "files", title: "Files", symbol: "folder") { [weak self] in
            self?.showGraph = false
            self?.libraryTab = .notes
            self?.prefersDetail = false
        })
        items.append(MobilePaletteItem(id: "bookmarks", title: "Bookmarks", symbol: "bookmark") { [weak self] in
            self?.showGraph = false
            self?.libraryTab = .bookmarks
            self?.prefersDetail = false
        })
        items.append(MobilePaletteItem(id: "tags", title: "Tags", symbol: "number") { [weak self] in
            self?.showGraph = false
            self?.libraryTab = .tags
            self?.prefersDetail = false
        })
        items.append(MobilePaletteItem(id: "outline", title: "Outline", symbol: "list.bullet.indent") { [weak self] in
            self?.showGraph = false
            self?.libraryTab = .outline
            self?.prefersDetail = false
        })
        items.append(MobilePaletteItem(id: "find", title: "Find in vault", symbol: "magnifyingglass") { [weak self] in
            self?.showGraph = false
            self?.libraryTab = .find
            self?.prefersDetail = false
        })
        if root != nil, snapshot != nil {
            items.append(MobilePaletteItem(id: "graph", title: "Graph: focus on this note", symbol: "point.3.connected.trianglepath.dotted") { [weak self] in
                self?.openGraph(atlas: false)
            })
            items.append(MobilePaletteItem(id: "atlas", title: "Graph: atlas of the vault", symbol: "globe") { [weak self] in
                self?.openGraph(atlas: true)
            })
        }
        if selectedNote != nil {
            items.append(MobilePaletteItem(id: "backlinks", title: "Backlinks", symbol: "arrow.uturn.backward") { [weak self] in self?.showBacklinks = true })
            items.append(MobilePaletteItem(id: "notehistory", title: "Version history", symbol: "clock.arrow.circlepath") { [weak self] in self?.showHistory = true })
            if canWrite, !bookmarksLocked, let p = selectedPath {
                let on = isBookmarked(p)
                items.append(MobilePaletteItem(id: "bookmark", title: on ? "Remove bookmark" : "Bookmark this note", symbol: on ? "bookmark.slash" : "bookmark") { [weak self] in
                    _ = self?.toggleBookmark(p)
                })
            }
        }
        if root != nil {
            items.append(MobilePaletteItem(id: "refresh", title: "Refresh vault", symbol: "arrow.clockwise") { [weak self] in self?.scan() })
            items.append(MobilePaletteItem(id: "reading", title: "Reading…", symbol: "textformat") { [weak self] in self?.showReadingSettings = true })
            if isSyncOnly {
                items.append(MobilePaletteItem(id: "syncnow", title: "Sync now", symbol: "arrow.triangle.2.circlepath") { [weak self] in self?.syncNow() })
            }
        }
        return items
    }
}
