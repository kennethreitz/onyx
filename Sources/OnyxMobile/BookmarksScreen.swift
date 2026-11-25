import SwiftUI
import OnyxCore

/// Bookmarks from `.obsidian/bookmarks.json`, shared with Obsidian and the Mac app.
struct BookmarksScreen: View {
    @EnvironmentObject private var vault: MobileVault

    var body: some View {
        Group {
            if vault.bookmarksLocked {
                ContentUnavailableView("Bookmarks left alone", systemImage: "bookmark.slash",
                                       description: Text(".obsidian/bookmarks.json isn’t valid JSON, so Onyx won’t overwrite it."))
            } else if vault.bookmarkStore.items.isEmpty {
                ContentUnavailableView("No bookmarks", systemImage: "bookmark",
                                       description: Text("Swipe a note in the list, or use Pin in the note’s menu, to add one. The same file is shared with Obsidian."))
            } else {
                List {
                    BookmarkOutline(items: vault.bookmarkStore.items)
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Bookmarks")
    }
}

struct BookmarkOutline: View {
    @EnvironmentObject private var vault: MobileVault
    var items: [BookmarkItem]

    var body: some View {
        ForEach(items) { item in
            if item.isGroup {
                DisclosureGroup {
                    BookmarkOutline(items: item.items ?? [])
                } label: {
                    Label(item.displayTitle, systemImage: "folder")
                }
            } else {
                BookmarkRow(item: item)
            }
        }
    }
}

struct BookmarkRow: View {
    @EnvironmentObject private var vault: MobileVault
    var item: BookmarkItem

    var body: some View {
        Button { vault.openBookmark(item) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label(item.displayTitle, systemImage: symbol)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let detail = item.displayDetail, !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if vault.canWrite && !vault.bookmarksLocked {
                Button(role: .destructive) { vault.removeBookmark(id: item.id) } label: {
                    Label("Remove", systemImage: "bookmark.slash")
                }
            }
        }
        .contextMenu {
            Button("Open") { vault.openBookmark(item) }
            if vault.canWrite && !vault.bookmarksLocked {
                Button("Remove Bookmark", role: .destructive) { vault.removeBookmark(id: item.id) }
            }
        }
    }

    var symbol: String {
        switch item.type {
        case "file": return "doc.text"
        case "folder": return "folder"
        case "search": return "magnifyingglass"
        case "url": return "link"
        case "graph": return "point.3.connected.trianglepath.dotted"
        default: return "bookmark"
        }
    }
}
