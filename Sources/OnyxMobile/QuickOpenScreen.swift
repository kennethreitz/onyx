import SwiftUI
import OnyxCore

/// Obsidian-style quick-open: a search box and a list of recent or matching notes.
struct QuickOpenScreen: View {
    @EnvironmentObject private var vault: MobileVault
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                let items = vault.quickOpenItems(query: query)
                if items.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    Section(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Recent" : "Notes") {
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
            }
            .listStyle(.plain)
            .navigationTitle("Open a Note")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, isPresented: .constant(true), prompt: "Search notes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
