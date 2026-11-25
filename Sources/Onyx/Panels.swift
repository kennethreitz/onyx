import SwiftUI
import OnyxCore

/// The shared look of every summoned surface: paper, a hairline, a soft shadow.
struct PanelChrome: ViewModifier {
    var pinned: Bool
    func body(content: Content) -> some View {
        content
            .background(Color.secondaryPaper)
            .clipShape(RoundedRectangle(cornerRadius: pinned ? 0 : Radius.panel, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: pinned ? 0 : Radius.panel, style: .continuous).strokeBorder(Color.hairline, lineWidth: pinned ? 0 : 0.8))
            .shadow(color: .black.opacity(pinned ? 0 : 0.10), radius: 18, x: 0, y: 8)
    }
}
extension View { func panelChrome(pinned: Bool = false) -> some View { modifier(PanelChrome(pinned: pinned)) } }

/// Empty states share one quiet voice: a line of italic serif, and an optional hint of what fills it.
struct QuietEmpty: View {
    var title: String
    var hint: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text(title).font(Theme.serif(13.5, italic: true)).foregroundStyle(Color.muted)
            if let hint { Text(hint).font(.system(size: TypeScale.caption)).foregroundStyle(Color.faint).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(.horizontal, 14).padding(.vertical, Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PanelHeader<Tab: Identifiable & Hashable>: View {
    var tabs: [Tab]
    @Binding var selection: Tab
    var symbol: (Tab) -> String
    var label: (Tab) -> String
    @Binding var pinned: Bool
    var onPin: ((Bool) -> Void)? = nil
    var showsPin: Bool = true
    var accessory: AnyView? = nil
    var body: some View {
        // tabs compress (28pt → 17pt each) so the header still fits a 140pt sidebar
        HStack(spacing: 1) {
            ForEach(tabs) { t in
                Button { withAnimation(Motion.quick) { selection = t } } label: {
                    Image(systemName: symbol(t))
                        .font(.system(size: 12.5, weight: selection == t ? .semibold : .regular))
                        .frame(minWidth: 17, idealWidth: 28, maxWidth: 28, minHeight: 24, maxHeight: 24)
                        .foregroundStyle(selection == t ? Color.ink : Color.faint)
                        .background(selection == t ? Color.ink.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: Radius.control))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(label(t))
            }
            Spacer(minLength: 0)
            if let accessory { accessory }
            if showsPin {
                Button { withAnimation(Motion.layout) { pinned.toggle() }; onPin?(pinned) } label: {
                    Image(systemName: pinned ? "pin.fill" : "pin").font(.system(size: 11)).foregroundStyle(Color.faint).frame(width: 20, height: 24)
                }.buttonStyle(.plain).help(pinned ? "Unpin" : "Pin (three-pane layout)")
            }
        }
        .padding(.horizontal, 6).padding(.top, 8).padding(.bottom, 4)
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Bindable var ws: Workspace
    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(tabs: SidebarTab.allCases, selection: $ws.sidebarTab, symbol: \.symbol, label: \.title, pinned: $ws.sidebarPinned,
                        showsPin: false, accessory: ws.sidebarTab == .files ? AnyView(SortMenu(ws: ws)) : nil)

            Divider().overlay(Color.hairline)
            Group {
                switch ws.sidebarTab {
                case .files: FileTreeView(ws: ws)
                case .search: SearchPanel(ws: ws)
                case .recent: PathList(ws: ws, paths: ws.recent.filter { ws.snapshot?.notes[$0] != nil || ws.snapshot?.attachments[$0] != nil }, empty: "Nothing opened yet.", hint: "Notes you open land here, newest first.")
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
                    Button { ws.newNote() } label: { Image(systemName: "square.and.pencil") }.buttonStyle(.plain).foregroundStyle(Color.muted).help("New note (⌘N)").accessibilityIdentifier("new-note-button")
                    Button { ws.newFolder() } label: { Image(systemName: "folder.badge.plus") }.buttonStyle(.plain).foregroundStyle(Color.muted).help("New folder (⇧⌘N)")
                }.padding(.horizontal, 12).padding(.vertical, 7)
            }
        }
    }
}

/// A transparent AppKit view that receives left clicks and reports the event's own
/// modifier flags. SwiftUI's `onTapGesture` often doesn't fire for ⌘-click on macOS,
/// and reading `NSEvent.modifierFlags` in the gesture callback can miss the key
/// because the callback runs after the event has ended.
struct TreeClickCatcher: NSViewRepresentable {
    var path: String
    var isFolder: Bool = false
    /// When true, the view only participates in an in-flight ⌘-drag (the empty area at the
    /// bottom of the tree, used as a vault-root drop zone). Clicks pass through.
    var dropOnly: Bool = false
    /// Leading strip reserved for the disclosure chevron (0 for files). Clicks here
    /// toggle expansion and are not treated as a row activation, so a folder with
    /// an index note can still be collapsed.
    var chevronWidth: CGFloat = 0
    var onChevron: (() -> Void)? = nil
    var onClick: (NSEvent.ModifierFlags) -> Void
    var onCommandDrag: ((String) -> [String])? = nil
    var isFolderPath: ((String) -> Bool)? = nil
    var onDragHover: ((String, Bool) -> Bool)? = nil
    var onDrop: ((String, Bool) -> Void)? = nil
    var onDragEnded: (() -> Void)? = nil

    func makeNSView(context: Context) -> Catcher {
        let v = Catcher()
        v.registerForDraggedTypes([.onyxTreePaths])
        v.apply(self)
        return v
    }
    func updateNSView(_ v: Catcher, context: Context) { v.apply(self) }

    final class Catcher: NSView, NSDraggingSource {
        static var moving = false
        static let pasteboardType = NSPasteboard.PasteboardType.onyxTreePaths

        var path = ""
        var isFolder = false
        var dropOnly = false
        var onClick: ((NSEvent.ModifierFlags) -> Void)?
        var onChevron: (() -> Void)?
        var chevronWidth: CGFloat = 0
        var onCommandDrag: ((String) -> [String])?
        var isFolderPath: ((String) -> Bool)?
        var onDragHover: ((String, Bool) -> Bool)?
        var onDrop: ((String, Bool) -> Void)?
        var onDragEnded: (() -> Void)?
        private var pendingClick: NSEvent?
        private var pendingPoint: NSPoint = .zero
        private var startedDrag = false

        func apply(_ s: TreeClickCatcher) {
            path = s.path
            isFolder = s.isFolder
            dropOnly = s.dropOnly
            onClick = s.onClick
            onChevron = s.onChevron
            chevronWidth = s.chevronWidth
            onCommandDrag = s.onCommandDrag
            isFolderPath = s.isFolderPath
            onDragHover = s.onDragHover
            onDrop = s.onDrop
            onDragEnded = s.onDragEnded
            let id = s.dropOnly ? "tree-root-drop" : "tree-row:\(s.path)"
            identifier = NSUserInterfaceItemIdentifier(id)
            setAccessibilityIdentifier(id)
        }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        /// Steal only a plain left mouse-down (including ⌘/⇧). Right-click, control-click,
        /// and hover pass through so the SwiftUI context menu and `onHover` keep working.
        /// During a tree-move drag, stay in the hit path so we can highlight and accept the drop.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard bounds.contains(point) else { return nil }
            if Self.moving { return self }
            if dropOnly { return nil }
            guard let e = NSApp.currentEvent else { return nil }
            if e.type == .leftMouseDown && !e.modifierFlags.contains(.control) { return self }
            return nil
        }
        override func mouseDown(with event: NSEvent) {
            if dropOnly { return }
            if event.modifierFlags.contains(.control) { nextResponder?.mouseDown(with: event); return }
            let loc = convert(event.locationInWindow, from: nil)
            if chevronWidth > 0 && loc.x < chevronWidth {
                onChevron?()
                return
            }
            // ⌘-click vs ⌘-drag: wait to see whether this is a drag before toggling selection,
            // so we don't deselect a row the user is about to move.
            if event.modifierFlags.contains(.command), onCommandDrag != nil {
                pendingClick = event
                pendingPoint = loc
                startedDrag = false
                return
            }
            onClick?(event.modifierFlags)
        }
        override func mouseDragged(with event: NSEvent) {
            guard let start = pendingClick, !startedDrag, let onCommandDrag else { return }
            let loc = convert(event.locationInWindow, from: nil)
            let dx = loc.x - pendingPoint.x, dy = loc.y - pendingPoint.y
            guard (dx * dx + dy * dy) >= 16 else { return }
            guard start.modifierFlags.contains(.command) || event.modifierFlags.contains(.command) else { return }
            let paths = onCommandDrag(path)
            guard !paths.isEmpty else { return }
            startedDrag = true
            pendingClick = nil
            beginMoveDrag(paths: paths, event: event)
        }
        override func mouseUp(with event: NSEvent) {
            if let start = pendingClick, !startedDrag {
                pendingClick = nil
                onClick?(start.modifierFlags)
            }
            pendingClick = nil
            startedDrag = false
        }
        override func rightMouseDown(with event: NSEvent) { nextResponder?.rightMouseDown(with: event) }

        private func beginMoveDrag(paths: [String], event: NSEvent) {
            let pb = NSPasteboardItem()
            pb.setString(paths.joined(separator: "\n"), forType: .onyxTreePaths)
            let item = NSDraggingItem(pasteboardWriter: pb)
            let img = TreeDragPreview.image(paths: paths, isFolder: isFolderPath ?? { _ in false })
            let size = img.size
            let loc = convert(event.locationInWindow, from: nil)
            // Frame must match the image size. A wider row-sized frame stretches a
            // short image and leaves a black slab around the name.
            item.draggingFrame = NSRect(x: loc.x - 16, y: loc.y - size.height / 2, width: size.width, height: size.height)
            item.imageComponentsProvider = {
                let c = NSDraggingImageComponent(key: .icon)
                c.contents = img
                c.frame = NSRect(origin: .zero, size: size)
                return [c]
            }
            Self.moving = true
            beginDraggingSession(with: [item], event: event, source: self)
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }
        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            Self.moving = false
            onDragEnded?()
        }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { hover(sender) }
        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { hover(sender) }
        override func draggingExited(_ sender: NSDraggingInfo?) {}
        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { hasTreePaths(sender) }
        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            guard hasTreePaths(sender) else { return false }
            onDrop?(path, isFolder)
            return true
        }

        private func hover(_ sender: NSDraggingInfo) -> NSDragOperation {
            guard hasTreePaths(sender) else { return [] }
            return (onDragHover?(path, isFolder) ?? false) ? .move : []
        }

        private func hasTreePaths(_ sender: NSDraggingInfo) -> Bool {
            sender.draggingPasteboard.availableType(from: [.onyxTreePaths]) != nil
        }
    }
}

extension NSPasteboard.PasteboardType {
    static let onyxTreePaths = NSPasteboard.PasteboardType("app.onyx.tree-paths")
}


struct FileTreeView: View {
    @Bindable var ws: Workspace
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    BookmarksSection(ws: ws)
                    if let tree = ws.snapshot?.tree {
                        ForEach(ws.treeChildren(tree)) { node in TreeNodeView(ws: ws, node: node, depth: 0) }
                    } else {
                        ProgressView().controlSize(.small).padding()
                    }
                    // Empty area at the bottom of the list, for a vault-root New Note / New Folder menu,
                    // and as a drop zone for ⌘-drag to the vault root.
                    Color.clear
                        .frame(maxWidth: .infinity, minHeight: 80)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: Radius.control)
                                .fill(ws.dropTarget == ""
                                      ? (ws.dropForbidden ? Color.warn.opacity(0.10) : Color.cursorBlue.opacity(0.10))
                                      : Color.clear)
                                .padding(.horizontal, 5)
                        )
                        .overlay(
                            TreeClickCatcher(
                                path: "",
                                isFolder: true,
                                dropOnly: true,
                                onClick: { _ in },
                                onDragHover: { path, isFolder in ws.treeDragHover(on: path, isFolder: isFolder) },
                                onDrop: { path, isFolder in ws.performTreeDrop(on: path, isFolder: isFolder) },
                                onDragEnded: { ws.endTreeDrag() }
                            )
                        )
                        .contextMenu {
                            Button("New Note") { ws.createNote(named: "Untitled", folder: "") }
                            Button("New Folder") { ws.newFolder(in: "") }
                        }
                }.thinScrollers()
                .padding(.vertical, 6)
            }
            .onAppear { if let p = ws.selectedFolder ?? ws.currentPath { DispatchQueue.main.async { proxy.scrollTo(p, anchor: .center) } } }
            .onChange(of: ws.revealToken) {
                let target = ws.renamingPath ?? ws.selectedFolder ?? ws.currentPath
                guard let f = target else { return }
                // let the expansion lay out first, then glide to the row
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { withAnimation(Motion.reduced ? nil : .easeInOut(duration: 0.25)) { proxy.scrollTo(f, anchor: .center) } }
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
    var isSelected: Bool { ws.treeSelection.contains(node.path) }
    /// The Homepage plugin's note when set, otherwise Home.md at the vault root.
    var isHome: Bool { node.path == ws.homePath || node.folderNote == ws.homePath }
    var treeNameWeight: Font.Weight { isHome ? .semibold : (node.isFolder ? .medium : .regular) }
    /// Selected rows get the full highlight; with a multi-selection the open note (if not part
    /// of it) keeps only a faint one so it's clear what a menu or ⌘⌫ will act on.
    var fill: Double {
        if node.isFolder, ws.dropTarget == node.path { return ws.dropForbidden ? 0.10 : 0.14 }
        if isSelected { return 0.16 }
        if isCurrent { return ws.treeSelection.isMulti ? 0.04 : 0.08 }
        return hover ? 0.04 : 0
    }
    var dropFill: Color {
        if node.isFolder, ws.dropTarget == node.path {
            return (ws.dropForbidden ? Color.warn : Color.cursorBlue).opacity(fill)
        }
        return Color.ink.opacity(fill)
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
                } else {
                    Spacer().frame(width: 12)
                }
                if ws.renamingPath == node.path {
                    InlineRenameField(
                        text: Binding(
                            get: { ws.renameDraft },
                            set: { ws.renameDraft = $0; if ws.renameError != nil { ws.renameError = nil } }
                        ),
                        wholeName: node.isNote || node.isFolder,
                        onCommit: { ws.commitInlineRename() },
                        onCancel: { ws.cancelInlineRename() }
                    )
                    .frame(maxWidth: .infinity, minHeight: 18, maxHeight: 22)
                } else {
                    Text(node.displayName)
                        .font(.system(size: 12.5, weight: treeNameWeight))
                        .foregroundStyle(node.isNote || node.isFolder || node.path.isCanvasPath || node.path.isBasePath ? Color.ink : Color.faint)
                        .underline(node.folderNote != nil, color: Color.faint.opacity(0.45))
                        .lineLimit(1).truncationMode(.middle)
                    if !node.isFolder && !node.isNote {
                        Text((node.name as NSString).pathExtension.uppercased()).font(.system(size: 8.5, weight: .medium)).foregroundStyle(Color.faint)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(depth) * 13 + 8).padding(.trailing, 8)
            .frame(minHeight: 24, maxHeight: ws.renamingPath == node.path ? 26 : 24)
            .background(
                RoundedRectangle(cornerRadius: Radius.control)
                    .fill(dropFill)
                    .padding(.horizontal, 5)
            )
            .overlay {
                if node.isFolder, ws.dropTarget == node.path {
                    RoundedRectangle(cornerRadius: Radius.control)
                        .stroke((ws.dropForbidden ? Color.warn : Color.cursorBlue).opacity(0.55), lineWidth: 1.2)
                        .padding(.horizontal, 5)
                }
            }
            .overlay(alignment: .leading) {
                if isSelected && ws.renamingPath != node.path {
                    RoundedRectangle(cornerRadius: 1).fill(Color.ink.opacity(0.5)).frame(width: 2, height: 14).padding(.leading, 8)
                }
            }
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .overlay {
                if ws.renamingPath != node.path {
                    TreeClickCatcher(
                        path: node.path,
                        isFolder: node.isFolder,
                        chevronWidth: node.isFolder ? CGFloat(depth) * 13 + 8 + 12 : 0,
                        onChevron: node.isFolder ? { handleChevron() } : nil,
                        onClick: { flags in
                            ws.treeClick(node.path, modifiers: flags) { activate() }
                        },
                        onCommandDrag: { path in
                            guard ws.renamingPath == nil else { return [] }
                            let paths = ws.pathsForTreeDrag(from: path)
                            ws.beginTreeDrag(paths)
                            return paths
                        },
                        isFolderPath: { ws.snapshot?.folders.contains($0) == true },
                        onDragHover: { path, isFolder in ws.treeDragHover(on: path, isFolder: isFolder) },
                        onDrop: { path, isFolder in ws.performTreeDrop(on: path, isFolder: isFolder) },
                        onDragEnded: { ws.endTreeDrag() }
                    )
                }
            }
            .id(node.path)
            .contextMenu {
                if ws.renamingPath == node.path {
                    // Keep the menu off the field while editing.
                } else if ws.treeSelection.isMulti && isSelected {
                    SelectionMenu(ws: ws, paths: ws.targets(for: node.path))
                } else {
                    FileMenu(ws: ws, path: node.path, isFolder: node.isFolder, folderNote: node.folderNote)
                }
            }
            if ws.renamingPath == node.path, let err = ws.renameError, !err.isEmpty {
                Text(err)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.warn)
                    .padding(.leading, CGFloat(depth) * 13 + 24)
                    .padding(.trailing, 8)
                    .padding(.bottom, 3)
            }
            if node.isFolder && isOpen {
                ForEach(ws.treeChildren(node)) { c in TreeNodeView(ws: ws, node: c, depth: depth + 1) }
            }
        }
    }

    func toggle() {
        withAnimation(Motion.quick) {
            if isOpen { ws.expanded.remove(node.path) } else { ws.expanded.insert(node.path) }
        }
    }
    func handleChevron() {
        let a = FolderTreeClick.action(.chevron, hasFolderNote: node.folderNote != nil)
        if a.toggleExpansion { toggle() }
    }
    func activate() {
        if node.isFolder {
            let a = FolderTreeClick.action(.row, hasFolderNote: node.folderNote != nil)
            if a.toggleExpansion { toggle() }
            if a.openFolderNote, let fn = node.folderNote { ws.openNote(fn, revealInTree: false) }
        } else { ws.openNote(node.path) }   // notes, canvases, bases, and attachments (FileView)
    }
}

/// The right-click menu wherever a note, file or folder appears (tree, recent, bookmarks, search).
/// The sidebar header's sort control (vault default).
struct SortMenu: View {
    var ws: Workspace
    var body: some View {
        Menu { SortChoices(ws: ws, folder: nil) } label: {
            Image(systemName: "arrow.up.arrow.down").font(.system(size: 10.5)).foregroundStyle(ws.treeOrder.base == .standard ? Color.faint : Color.ink)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().frame(width: 22, height: 24)
        .help("Sort: \(ws.treeOrder.base.key.title), \(ws.treeOrder.base.ascending ? "ascending" : "descending")")
    }
}

/// Name / Modified / Created, direction and folders-on-top, for the vault or for one folder.
struct SortChoices: View {
    var ws: Workspace
    var folder: String?
    var body: some View {
        let cur = folder.map { ws.treeOrder.sort(for: $0) } ?? ws.treeOrder.base
        ForEach(TreeSort.Key.allCases, id: \.self) { k in
            Toggle(k.title, isOn: Binding(get: { cur.key == k }, set: { _ in ws.setSort(TreeSort(key: k, foldersFirst: cur.foldersFirst), folder: folder) }))
        }
        Divider()
        Toggle(cur.key == .name ? "A → Z" : "Oldest First", isOn: Binding(get: { cur.ascending }, set: { _ in var s = cur; s.ascending = true; ws.setSort(s, folder: folder) }))
        Toggle(cur.key == .name ? "Z → A" : "Newest First", isOn: Binding(get: { !cur.ascending }, set: { _ in var s = cur; s.ascending = false; ws.setSort(s, folder: folder) }))
        Divider()
        Toggle("Folders on Top", isOn: Binding(get: { cur.foldersFirst }, set: { v in var s = cur; s.foldersFirst = v; ws.setSort(s, folder: folder) }))
        if let f = folder, ws.treeOrder.overrides[f] != nil {
            Divider()
            Button("Use Vault Order") { ws.clearSortOverride(f) }
        }
    }
}

struct FileMenu: View {
    var ws: Workspace
    var path: String
    var isFolder = false
    var folderNote: String? = nil
    var body: some View {
        let note = isFolder ? folderNote : (path.lowercased().hasSuffix(".md") || path.isCanvasPath || path.isBasePath ? path : nil)
        if let note {
            Button("Open") { ws.openNote(note) }
            Button("Open in Split") { ws.split(.vertical); ws.openNote(note) }
        }
        Button(ws.isBookmarked(path, isFolder: isFolder) ? "Remove Bookmark" : "Bookmark") {
            ws.toggleBookmark(path: path, isFolder: isFolder)
        }
        if isFolder {
            Button("New Note Here") { ws.createNote(named: "Untitled", folder: path) }
            if folderNote == nil, FolderIndex.notePath(forFolder: path) != nil {
                Button("New Index Here") { ws.createIndex(in: path) }
            }
            Button("New Folder") { ws.newFolder(in: path) }
            Menu("Sort This Folder By") { SortChoices(ws: ws, folder: path) }
            Button("Lint Notes in Folder…") { DispatchQueue.main.async { ws.previewLintFolder(path) } }
            Button("Export Folder as PDF…") { NoteBookPrinter.run([path], ws: ws) }
        }
        Divider()
        Button("Rename…") { DispatchQueue.main.async { ws.confirmRename(path) } }
        Button("Move to…") { ws.beginMove(path) }
        Divider()
        // Adjacent on purpose: Open in Obsidian is a hidden Option-alternate of Reveal in Finder.
        Button("Reveal in Finder") { ws.revealInFinder(path) }
        if let note { Button("Open in Obsidian") { ws.openInObsidian(note) } }
        Divider()
        Button(isFolder ? "Delete Folder…" : "Delete…", role: .destructive) { DispatchQueue.main.async { ws.confirmTrash(path) } }
    }
}

/// Right-click on a row that's part of a multi-selection: batch actions; one-item actions are
/// shown but disabled so the menu doesn't change shape under the pointer.
struct SelectionMenu: View {
    var ws: Workspace
    var paths: [String]
    var body: some View {
        Button("Open") {}.disabled(true)
        Button(selectionAllBookmarked(paths) ? "Remove Bookmarks" : "Bookmark \(paths.count) Items") {
            let pinned = !selectionAllBookmarked(paths)
            ws.setBookmarked(paths.map { ($0, ws.snapshot?.folders.contains($0) == true) }, pinned: pinned)
        }
        Button("Export Selection as PDF…") { NoteBookPrinter.run(paths, ws: ws) }
        Divider()
        Button("Rename…") {}.disabled(true)
        Button("Move \(paths.count) Items to…") { ws.beginMove(paths) }
        Divider()
        // Adjacent on purpose: the disabled Open in Obsidian item is a hidden Option-alternate of Reveal.
        Button("Reveal \(paths.count) Items in Finder") {
            if let r = ws.root { NSWorkspace.shared.activateFileViewerSelecting(paths.map { r.appendingPathComponent($0) }) }
        }
        Button("Open in Obsidian") {}.disabled(true)
        Divider()
        Button("Delete \(paths.count) Items…", role: .destructive) { DispatchQueue.main.async { ws.confirmTrash(paths) } }
    }

    func selectionAllBookmarked(_ paths: [String]) -> Bool {
        paths.allSatisfy { ws.isBookmarked($0, isFolder: ws.snapshot?.folders.contains($0) == true) }
    }
}

struct PathList: View {
    @Bindable var ws: Workspace
    var paths: [String]
    var empty: String
    var hint: String? = nil
    var body: some View {
        if paths.isEmpty {
            QuietEmpty(title: empty, hint: hint).padding(.top, Space.xs)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(paths, id: \.self) { p in NoteRow(ws: ws, path: p) }
                }.padding(.vertical, 6).thinScrollers()
            }
        }
    }
}

struct NoteRow: View {
    @Bindable var ws: Workspace
    var path: String
    var detail: String? = nil
    var preview = false
    /// 0-based source line to open at, when set.
    var line: Int? = nil
    var linkTitle: String? = nil
    var onLink: (() -> Void)? = nil
    @State private var hover = false
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(((path as NSString).lastPathComponent as NSString).deletingPathExtension).font(.system(size: 12.5)).foregroundStyle(Color.ink).lineLimit(1)
                Text(detail ?? (path as NSString).deletingLastPathComponent).font(.system(size: 10.5)).foregroundStyle(Color.faint).lineLimit(detail == nil ? 1 : 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let onLink, let linkTitle {
                Button(linkTitle, action: onLink)
                    .font(.system(size: 10.5, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.muted)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.control).fill(ws.currentPath == path ? Color.ink.opacity(0.08) : (hover ? Color.ink.opacity(0.04) : .clear)).padding(.horizontal, 5))
        .contentShape(Rectangle())
        .background { if preview { GraphPreviewTrigger(ws: ws, path: path) } }
        .contextMenu { FileMenu(ws: ws, path: path) }
        .onHover { hover = $0 }
        .onTapGesture {
            GraphPreviewController.shared.close()
            if let line { ws.openNote(path, line: line + 1) } else { ws.openNote(path) }
        }
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
                Button {
                    ws.openVaultReplace(query: ws.searchQuery)
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11)).foregroundStyle(Color.muted)
                        .frame(width: 18, height: 18).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Replace in vault (⌥⇧⌘F)")
            }
            .padding(8).background(Color.paper, in: RoundedRectangle(cornerRadius: Radius.control))
            .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(focused ? Color.cursorBlue.opacity(0.55) : Color.hairline, lineWidth: focused ? 1 : 0.8))
            .animation(Motion.hover, value: focused)
            .padding(10)
            if !ws.searchQuery.isEmpty {
                Text("\(hits.count == 200 ? "200+" : String(hits.count)) results · \(millis) ms").font(.system(size: 10.5)).foregroundStyle(Color.faint)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.bottom, 4)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(hits) { h in NoteRow(ws: ws, path: h.path, detail: h.snippets.first ?? (h.path as NSString).deletingLastPathComponent) }
                    if ws.searchQuery.isEmpty {
                        QuietEmpty(title: "Search every note.", hint: "tag:name  ·  path:folder  ·  \"exact phrase\"")
                    } else if hits.isEmpty && task == nil {
                        QuietEmpty(title: "Nothing matches.", hint: "Try fewer words, or ⌘O to find a note by name.")
                    }
                }.thinScrollers()
            }
        }
        .onAppear { focused = true; run() }
        .onChange(of: ws.searchQuery) { run() }
        .onChange(of: ws.focusSearch) { focused = true }
    }
    func run() {
        task?.cancel()
        let q = ws.searchQuery
        guard let snap = ws.snapshot, !q.trimmingCharacters(in: .whitespaces).isEmpty else { hits = []; task = nil; return }
        task = Task {
            try? await Task.sleep(nanoseconds: 90_000_000)
            if Task.isCancelled { return }
            let t0 = Date()
            let r = await Task.detached { snap.search(q) }.value
            if !Task.isCancelled { hits = r; millis = Int(Date().timeIntervalSince(t0) * 1000); task = nil }
        }
    }
}

struct BookmarksPanel: View {
    @Bindable var ws: Workspace
    var body: some View {
        VStack(spacing: 0) {
            if ws.bookmarkStore.items.isEmpty {
                QuietEmpty(title: "No bookmarks yet.", hint: "Bookmark a note from the context menu, the button below, or ⌥⌘D.").padding(.top, Space.xs)
            } else {
                ScrollView {
                    BookmarksList(ws: ws, items: ws.bookmarkStore.items, parent: nil, depth: 0)
                    BookmarksAppendTarget(ws: ws, parent: nil)
                }.padding(.vertical, 6).thinScrollers()
            }
            if let p = ws.currentPath {
                Divider().overlay(Color.hairline)
                Button { ws.toggleBookmark() } label: {
                    Label(ws.isBookmarked(p) ? "Remove bookmark" : "Bookmark this note", systemImage: ws.isBookmarked(p) ? "bookmark.slash" : "bookmark")
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
                    TagRow(name: t.0, count: t.1) { ws.searchQuery = "tag:" + t.0; ws.sidebarTab = .search }
                }
            }.padding(.vertical, 6).thinScrollers()
        }
    }
}

/// One tag in the Tags panel: the same hover wash as note rows, counts in tabular figures.
struct TagRow: View {
    var name: String
    var count: Int
    var action: () -> Void
    @State private var hover = false
    var body: some View {
        HStack {
            Text("#" + name).font(.custom("IBMPlexMono", size: 11.5)).foregroundStyle(Color.ink).lineLimit(1)
            Spacer()
            Text("\(count)").font(.system(size: TypeScale.caption).monospacedDigit()).foregroundStyle(Color.faint)
        }
        .padding(.horizontal, 12).frame(height: 24)
        .background(RoundedRectangle(cornerRadius: Radius.control).fill(Color.ink.opacity(hover ? 0.04 : 0)).padding(.horizontal, 5))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: action)
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
            if ws.inspectorTab == .outline {
                OutlinePane(ws: ws)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let note = ws.currentNote, let snap = ws.snapshot {
                            switch ws.inspectorTab {
                            case .outline: EmptyView()
                            case .backlinks: backlinks(note, snap)
                            case .properties: properties(note, snap)
                            }
                        }
                    }.padding(.vertical, 8).thinScrollers()
                }
            }
        }
    }

    func sectionTitle(_ s: String) -> some View {
        Text(s.uppercased()).font(.system(size: 9.5, weight: .semibold)).tracking(0.8).foregroundStyle(Color.faint).padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 4)
    }

    @ViewBuilder func relations(_ note: NoteRecord, _ snap: VaultSnapshot) -> some View {
        RelationshipsSection(ws: ws, note: note, snap: snap).id(note.path)
    }

    @ViewBuilder func backlinks(_ note: NoteRecord, _ snap: VaultSnapshot) -> some View {
        relations(note, snap)
        let links = snap.backlinks(to: note.path)
        sectionTitle("Linked mentions · \(links.count)")
        if links.isEmpty { QuietEmpty(title: "Nothing links here yet.", hint: "Write [[\(note.name)]] in another note.") }
        ForEach(links, id: \.self) { b in
            NoteRow(ws: ws, path: b.source, detail: b.context.isEmpty ? nil : NoteParser.stripInline(b.context), line: b.line)
        }
        let unlinked = snap.unlinkedMentions(of: note.path)
        HStack(spacing: Space.s) {
            Button { withAnimation(Motion.quick) { showUnlinked.toggle() } } label: {
                HStack(spacing: Space.xs) {
                    Image(systemName: "chevron.right").rotationEffect(.degrees(showUnlinked ? 90 : 0)).font(.system(size: 8, weight: .semibold))
                    Text("UNLINKED MENTIONS · \(unlinked.count)").font(.system(size: TypeScale.label, weight: .semibold)).tracking(0.8)
                }.foregroundStyle(Color.faint)
            }.buttonStyle(.plain)
            Spacer(minLength: 0)
            if showUnlinked && !unlinked.isEmpty {
                Button("Link all") { ws.linkAllUnlinkedMentions(of: note.path, mentions: unlinked) }
                    .font(.system(size: 10.5, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.muted)
            }
        }.padding(.horizontal, 14).padding(.top, 14)
        if showUnlinked {
            if unlinked.isEmpty { QuietEmpty(title: "No unlinked mentions.", hint: "Plain-text uses of this note's title or aliases, outside code and links.") }
            ForEach(unlinked, id: \.self) { m in
                NoteRow(ws: ws, path: m.source, detail: m.context, line: m.line, linkTitle: "Link") {
                    ws.linkUnlinkedMention(m, title: note.name)
                }
            }
        }
    }

    @ViewBuilder func properties(_ note: NoteRecord, _ snap: VaultSnapshot) -> some View {
        let fm = Frontmatter.parse(ws.settledText)
        sectionTitle("Properties")
        if fm.properties.isEmpty { QuietEmpty(title: "No properties.", hint: "Frontmatter between --- lines at the top shows here.") }
        ForEach(fm.properties, id: \.self) { p in
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: icon(p.value)).font(.system(size: 10)).foregroundStyle(Color.faint).frame(width: 14)
                Text(p.key).font(.system(size: 11.5)).foregroundStyle(Color.muted).frame(width: 84, alignment: .leading).lineLimit(1)
                Text(p.value.display).font(.system(size: 11.5)).foregroundStyle(Color.ink).textSelection(.enabled).lineLimit(4)
                Spacer(minLength: 0)
            }.padding(.horizontal, 14).padding(.vertical, 3)
        }
        sectionTitle("Note")
        let s = NoteParser.summarize(ws.settledText)
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
                QuietEmpty(title: "This vault isn’t a git repository.", hint: "Run git init in the vault folder to get history and auto-sync.").padding(.top, Space.xs)
            } else {
                HStack {
                    Image(systemName: "arrow.triangle.branch").foregroundStyle(Color.faint)
                    Text(branch).font(.custom("IBMPlexMono", size: 11.5))
                    Spacer()
                    Button { ws.git?.syncNow(); refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).foregroundStyle(Color.muted).help("Sync now")
                }.padding(.horizontal, 12).padding(.top, 10)
                sectionPicker
                if ws.gitPanelSection == .history {
                    NoteHistoryList(ws: ws, isRepo: isRepo)
                } else {
                    statusPane
                }
            }
        }
        .onAppear { refresh() }
    }

    var sectionPicker: some View {
        HStack(spacing: 1) {
            ForEach(GitPanelSection.allCases) { s in
                Button { withAnimation(Motion.quick) { ws.gitPanelSection = s } } label: {
                    Text(s.title)
                        .font(.system(size: 11, weight: ws.gitPanelSection == s ? .semibold : .regular))
                        .foregroundStyle(ws.gitPanelSection == s ? Color.ink : Color.faint)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(ws.gitPanelSection == s ? Color.ink.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: Radius.control))
                }.buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, 10)
    }

    @ViewBuilder var statusPane: some View {
        if let g = ws.git {
            Text(g.help).font(.system(size: 10.5)).foregroundStyle(Color.faint).lineLimit(4).padding(.horizontal, 12)
            ForEach(g.conflictCopies, id: \.self) { c in
                Button { ws.openNote(c) } label: {
                    Label((c as NSString).lastPathComponent, systemImage: "doc.on.doc").font(.system(size: 11.5)).lineLimit(1)
                }.buttonStyle(.plain).foregroundStyle(Color.ink).padding(.horizontal, 12)
                .help("Both versions were kept. Merge what you need into the original, then delete this copy.")
            }
        } else {
            Text("Auto-sync is off (git not found).").font(.system(size: 10.5)).foregroundStyle(Color.faint).padding(.horizontal, 12)
        }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(changes, id: \.1) { c in
                    HStack(spacing: 8) {
                        Text(c.0).font(.custom("IBMPlexMono", size: 10.5)).foregroundStyle(Color.muted).frame(width: 20, alignment: .leading)
                        Text(c.1).font(.system(size: 11.5)).lineLimit(1).truncationMode(.middle)
                    }.padding(.horizontal, 12).padding(.vertical, 3)
                }
            }.thinScrollers()
        }
        if changes.isEmpty { QuietEmpty(title: "Working tree clean.").padding(.horizontal, -2) }
        TextField("Commit message", text: $message).textFieldStyle(.roundedBorder).font(.system(size: 12)).padding(.horizontal, 10)
        HStack {
            Button("Commit all") { commit() }.disabled(changes.isEmpty)
            Spacer()
            Text(status).font(.system(size: 10.5)).foregroundStyle(Color.faint).lineLimit(2)
        }.padding(.horizontal, 10).padding(.bottom, 10)
    }

    func git(_ args: [String]) -> (Int32, String) {
        guard let root = ws.root else { return (1, "") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: NoteHistory.gitBinary() ?? "/usr/bin/git")
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
