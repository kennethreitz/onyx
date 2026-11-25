import SwiftUI
import UniformTypeIdentifiers
import OnyxCore

struct ContentView: View {
    @EnvironmentObject private var vault: MobileVault
    @Environment(\.colorScheme) private var scheme
    @State private var picking = false

    var body: some View {
        NavigationSplitView {
            list
                .navigationTitle("Onyx")
                .searchable(text: $vault.query, prompt: "Search notes")
                .toolbar { toolbar }
                .refreshable { vault.scan() }
        } detail: {
            if let note = vault.selectedNote, let snap = vault.snapshot, let root = vault.root {
                ReaderScreen(note: note, snapshot: snap, vaultRoot: root, dark: scheme == .dark)
                    .navigationTitle(note.name)
                    .navigationBarTitleDisplayMode(.inline)
                    .id(note.path)
            } else if vault.root == nil {
                ContentUnavailableView("Open a vault", systemImage: "folder",
                                       description: Text("Choose the folder that holds your notes — an Obsidian vault on this device or in iCloud Drive."))
            } else {
                ContentUnavailableView("No note selected", systemImage: "doc")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .onyxOpenNote)) { n in
            if let p = n.object as? String { vault.selectedPath = p }
        }
        .onReceive(NotificationCenter.default.publisher(for: .onyxSearch)) { n in
            if let q = n.object as? String { vault.query = q }
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
    }

    @ViewBuilder
    private var list: some View {
        if vault.root == nil {
            ContentUnavailableView {
                Label("No vault", systemImage: "folder.badge.plus")
            } description: {
                Text("Open a folder of Markdown notes. iCloud Drive ▸ Obsidian works if the vault is there.")
            } actions: {
                Button("Open Vault") { picking = true }
            }
        } else if vault.visibleNotes.isEmpty {
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
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Button("Open Vault…", systemImage: "folder") { picking = true }
                if vault.dailyPath != nil {
                    Button("Today’s daily note", systemImage: "calendar") { vault.openDaily() }
                }
                if vault.root != nil {
                    Button("Refresh", systemImage: "arrow.clockwise") { vault.scan() }
                    Divider()
                    Button("Close Vault", systemImage: "xmark.circle", role: .destructive) { vault.forgetVault() }
                }
            } label: {
                Label("Vault", systemImage: "folder")
            }
        }
        if let name = vault.root?.lastPathComponent {
            ToolbarItem(placement: .principal) {
                Text(name).font(.headline)
            }
        }
    }
}
