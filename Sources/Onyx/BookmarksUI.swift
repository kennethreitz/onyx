import SwiftUI
import UniformTypeIdentifiers
import OnyxCore

/// In-app drag payload for reordering bookmarks. A private type so Finder drops
/// and file-tree moves aren't accepted as a reorder.
struct BookmarkDragID: Codable, Transferable, Equatable {
    var id: UUID
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: UTType(exportedAs: "org.kennethreitz.onyx.bookmark-id"))
    }
}

/// Bookmarks at the top of the file sidebar. Hidden when there aren't any.
struct BookmarksSection: View {
    @Bindable var ws: Workspace
    var body: some View {
        if !ws.bookmarkStore.items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(Motion.quick) { ws.setBookmarksExpanded(!ws.bookmarksExpanded) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8.5, weight: .semibold))
                            .rotationEffect(.degrees(ws.bookmarksExpanded ? 90 : 0))
                            .foregroundStyle(Color.faint)
                            .frame(width: 12)
                        Text("BOOKMARKS")
                            .font(.system(size: 9.5, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(Color.faint)
                        Spacer(minLength: 0)
                        Text("\(leafCount)")
                            .font(.system(size: TypeScale.caption).monospacedDigit())
                            .foregroundStyle(Color.faint)
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Bookmarks from this vault, shared with Obsidian")

                if ws.bookmarksExpanded {
                    BookmarksList(ws: ws, items: ws.bookmarkStore.items, parent: nil, depth: 0)
                    BookmarksAppendTarget(ws: ws, parent: nil)
                }
            }
            Divider().overlay(Color.hairline).padding(.vertical, 4)
        }
    }

    var leafCount: Int { countLeaves(ws.bookmarkStore.items) }
    func countLeaves(_ items: [BookmarkItem]) -> Int {
        items.reduce(0) { $0 + ($1.isGroup ? countLeaves($1.items ?? []) : 1) }
    }
}

struct BookmarksList: View {
    @Bindable var ws: Workspace
    var items: [BookmarkItem]
    var parent: UUID?
    var depth: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                BookmarkRow(ws: ws, item: item, parent: parent, depth: depth)
            }
        }
    }
}

struct BookmarkRow: View {
    @Bindable var ws: Workspace
    var item: BookmarkItem
    var parent: UUID?
    var depth: Int
    @State private var hover = false
    @State private var groupOpen = true
    @State private var dropArmed = false

    var isCurrent: Bool {
        switch item.type {
        case "file": return item.path == ws.currentPath && BookmarkSubpath.normalize(item.subpath) == nil
        case "folder": return item.path == ws.selectedFolder
        default: return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                if item.isGroup {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .rotationEffect(.degrees(groupOpen ? 90 : 0))
                        .foregroundStyle(Color.faint)
                        .frame(width: 12)
                } else if let symbol = symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.faint)
                        .frame(width: 12)
                } else {
                    Spacer().frame(width: 12)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.displayTitle)
                        .font(.system(size: 12.5, weight: item.isGroup ? .medium : .regular))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                    if let detail = item.displayDetail, !item.isGroup {
                        Text(detail)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color.faint)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(depth) * 13 + 8)
            .padding(.trailing, 8)
            .padding(.vertical, item.displayDetail == nil || item.isGroup ? 3 : 4)
            .frame(minHeight: 24)
            .background(
                RoundedRectangle(cornerRadius: Radius.control)
                    .fill(dropArmed ? Color.cursorBlue.opacity(0.12) : Color.ink.opacity(isCurrent ? 0.08 : (hover ? 0.04 : 0)))
                    .padding(.horizontal, 5)
            )
            .overlay {
                if dropArmed {
                    RoundedRectangle(cornerRadius: Radius.control)
                        .stroke(Color.cursorBlue.opacity(0.55), lineWidth: 1.2)
                        .padding(.horizontal, 5)
                }
            }
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .onTapGesture { activate() }
            .contextMenu { menu }
            .draggable(BookmarkDragID(id: item.id))
            .dropDestination(for: BookmarkDragID.self) { drops, _ in
                guard let drag = drops.first, drag.id != item.id else { return false }
                if item.isGroup {
                    ws.moveBookmark(id: drag.id, parent: item.id, before: nil)
                } else {
                    ws.moveBookmark(id: drag.id, parent: parent, before: item.id)
                }
                return true
            } isTargeted: { dropArmed = $0 }

            if item.isGroup, groupOpen {
                BookmarksList(ws: ws, items: item.items ?? [], parent: item.id, depth: depth + 1)
            }
        }
    }

    var symbol: String? {
        switch item.type {
        case "folder": return "folder"
        case "search": return "magnifyingglass"
        case "url": return "link"
        case "graph": return "point.3.connected.trianglepath.dotted"
        case "file" where BookmarkSubpath.normalize(item.subpath) != nil: return "text.alignleft"
        default: return nil
        }
    }

    func activate() {
        if item.isGroup {
            withAnimation(Motion.quick) { groupOpen.toggle() }
        } else {
            ws.openBookmark(item)
        }
    }

    @ViewBuilder var menu: some View {
        if !item.isGroup {
            Button("Open") { ws.openBookmark(item) }
        }
        Button("Remove Bookmark") { ws.removeBookmark(id: item.id) }
        if let path = item.path, item.type == "file" || item.type == "folder" {
            Divider()
            let folderNote = item.type == "folder" ? FolderIndex.notePath(forFolder: path).flatMap { ws.snapshot?.notes[$0] != nil ? $0 : nil } : nil
            FileMenu(ws: ws, path: path, isFolder: item.type == "folder", folderNote: folderNote)
        }
    }
}

/// Drop at the end of a list to append.
struct BookmarksAppendTarget: View {
    @Bindable var ws: Workspace
    var parent: UUID?
    @State private var dropArmed = false
    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: 10)
            .background(
                RoundedRectangle(cornerRadius: Radius.control)
                    .fill(dropArmed ? Color.cursorBlue.opacity(0.12) : Color.clear)
                    .padding(.horizontal, 5)
            )
            .dropDestination(for: BookmarkDragID.self) { drops, _ in
                guard let drag = drops.first else { return false }
                ws.moveBookmark(id: drag.id, parent: parent, before: nil)
                return true
            } isTargeted: { dropArmed = $0 }
    }
}
