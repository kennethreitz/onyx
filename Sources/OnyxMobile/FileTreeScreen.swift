import SwiftUI
import OnyxCore

/// Hierarchical folder and note tree for the Files tab, built from the vault snapshot.
struct FileTreeScreen: View {
    @EnvironmentObject private var vault: MobileVault

    var body: some View {
        let rows = vault.visibleTreeRows()
        ScrollViewReader { proxy in
            List(selection: $vault.selectedPath) {
                if rows.isEmpty {
                    ContentUnavailableView("Empty vault", systemImage: "folder",
                                           description: Text("Create a note or a folder to get started."))
                } else {
                    ForEach(rows) { row in
                        FileTreeRowView(row: row)
                            .id(row.node.path)
                            .tag(row.node.isNote ? Optional(row.node.path) : nil)
                            .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    }
                }
            }
            .listStyle(.plain)
            .onAppear { scroll(proxy) }
            .onChange(of: vault.treeRevealToken) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { scroll(proxy) }
            }
            .onChange(of: vault.selectedPath) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { scroll(proxy) }
            }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard let p = vault.selectedPath else { return }
        proxy.scrollTo(p, anchor: .center)
    }
}

private struct FileTreeRowView: View {
    @EnvironmentObject private var vault: MobileVault
    let row: FileTreeRow

    var node: FileNode { row.node }
    var isOpen: Bool { vault.treeExpanded.contains(node.path) }
    var isCurrent: Bool {
        vault.selectedPath == node.path || (node.folderNote != nil && vault.selectedPath == node.folderNote)
    }

    var body: some View {
        HStack(spacing: 4) {
            Color.clear.frame(width: CGFloat(row.depth) * 16)
            if node.isFolder {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 28)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) { vault.toggleFolder(node.path) }
                    }
                    .accessibilityLabel(isOpen ? "Collapse \(node.displayName)" : "Expand \(node.displayName)")
                    .accessibilityAddTraits(.isButton)
            } else {
                Color.clear.frame(width: 22, height: 28)
            }
            Button {
                activate()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundStyle(node.isFolder ? Color.accentColor : Color.secondary)
                        .frame(width: 20)
                    Text(node.displayName)
                        .font(.body.weight(node.isFolder ? .medium : .regular))
                        .underline(node.folderNote != nil, color: Color.secondary.opacity(0.5))
                        .foregroundStyle(node.isNote || node.isFolder ? Color.primary : Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 8)
                .fill(isCurrent ? Color.accentColor.opacity(0.15) : Color.clear)
                .padding(.horizontal, 4)
        )
        .contextMenu { menu }
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private var icon: String {
        if node.isFolder { return isOpen ? "folder.fill" : "folder" }
        if node.isNote { return "doc.text" }
        return "doc"
    }

    private func activate() {
        if node.isFolder {
            withAnimation(.easeInOut(duration: 0.15)) { vault.handleFolderTap(node) }
        } else {
            vault.handleFileTap(node)
        }
    }

    @ViewBuilder
    private var menu: some View {
        if vault.canWrite {
            Button("New Note", systemImage: "square.and.pencil") {
                vault.beginNewNote(in: node.isFolder ? node.path : (node.path as NSString).deletingLastPathComponent)
            }
            Button("New Folder", systemImage: "folder.badge.plus") {
                vault.beginNewFolder(in: node.isFolder ? node.path : (node.path as NSString).deletingLastPathComponent)
            }
            Divider()
            Button("Rename", systemImage: "pencil") { vault.beginRename(node.path) }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { vault.beginDelete(node.path) }
        }
        if node.isNote || node.folderNote != nil {
            let path = node.isFolder ? (node.folderNote ?? node.path) : node.path
            Button(vault.isBookmarked(path) ? "Remove Bookmark" : "Bookmark") {
                _ = vault.toggleBookmark(path)
            }
            .disabled(!vault.canWrite || vault.bookmarksLocked)
        } else if node.isFolder {
            Button(vault.isBookmarked(node.path, isFolder: true) ? "Remove Bookmark" : "Bookmark") {
                _ = vault.toggleBookmark(node.path, isFolder: true)
            }
            .disabled(!vault.canWrite || vault.bookmarksLocked)
        }
    }
}
