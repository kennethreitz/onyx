import AppKit
import SwiftUI
import OnyxCore

/// Bookmarks at the top of the file sidebar. Always shown so a note can be
/// dropped here even when the list is still empty.
struct BookmarksSection: View {
    @Bindable var ws: Workspace
    @State private var headerArmed = false
    var body: some View {
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
                    if leafCount > 0 {
                        Text("\(leafCount)")
                            .font(.system(size: TypeScale.caption).monospacedDigit())
                            .foregroundStyle(Color.faint)
                    }
                }
                .padding(.leading, 8)
                .padding(.trailing, 12)
                .padding(.top, 6)
                .padding(.bottom, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: Radius.control)
                    .fill(headerArmed ? Color.cursorBlue.opacity(0.12) : Color.clear)
                    .padding(.horizontal, 5)
            )
            .overlay {
                if headerArmed {
                    RoundedRectangle(cornerRadius: Radius.control)
                        .stroke(Color.cursorBlue.opacity(0.55), lineWidth: 1.2)
                        .padding(.horizontal, 5)
                }
            }
            .overlay {
                BookmarksDropCatcher(ws: ws, parent: nil, before: nil) { headerArmed = $0 }
            }
            .help("Bookmarks from this vault, shared with Obsidian")

            if ws.bookmarksExpanded {
                BookmarksList(ws: ws, items: ws.bookmarkStore.items, parent: nil, depth: 0)
                if ws.bookmarkStore.items.isEmpty {
                    BookmarksEmptyDrop(ws: ws, parent: nil)
                }
                BookmarksAppendTarget(ws: ws, parent: nil, visibleWhenEmpty: false)
            }
        }
        Divider().overlay(Color.hairline).padding(.vertical, 4)
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

    var dropParent: UUID? { item.isGroup ? item.id : parent }
    var dropBefore: UUID? { item.isGroup ? nil : item.id }

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
            .contextMenu { menu }
            .overlay {
                BookmarksDropCatcher(
                    ws: ws,
                    parent: dropParent,
                    before: dropBefore,
                    itemID: item.id,
                    dragTitle: item.displayTitle,
                    onClick: { flags in activate(command: flags.contains(.command)) }
                ) { dropArmed = $0 }
            }

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

    func activate(command: Bool = false) {
        switch BookmarkActivation.action(type: item.type, command: command) {
        case .toggleGroup:
            withAnimation(Motion.quick) { groupOpen.toggle() }
        case .open:
            ws.openBookmark(item)
        case .openInNewPane:
            ws.openBookmark(item, inNewPane: true)
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
    var visibleWhenEmpty: Bool = true
    @State private var dropArmed = false
    var body: some View {
        if visibleWhenEmpty || !ws.bookmarkStore.items.isEmpty || parent != nil {
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 10)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control)
                        .fill(dropArmed ? Color.cursorBlue.opacity(0.12) : Color.clear)
                        .padding(.horizontal, 5)
                )
                .overlay {
                    if dropArmed {
                        RoundedRectangle(cornerRadius: Radius.control)
                            .stroke(Color.cursorBlue.opacity(0.55), lineWidth: 1.2)
                            .padding(.horizontal, 5)
                    }
                }
                .overlay {
                    BookmarksDropCatcher(ws: ws, parent: parent, before: nil) { dropArmed = $0 }
                }
        }
    }
}

/// Visible empty-list drop zone: "Drop notes here".
struct BookmarksEmptyDrop: View {
    @Bindable var ws: Workspace
    var parent: UUID?
    @State private var dropArmed = false
    var body: some View {
        Text("Drop notes here")
            .font(.system(size: 11.5).italic())
            .foregroundStyle(Color.faint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 24)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Radius.control)
                    .fill(dropArmed ? Color.cursorBlue.opacity(0.12) : Color.clear)
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
            .overlay {
                BookmarksDropCatcher(ws: ws, parent: parent, before: nil) { dropArmed = $0 }
            }
    }
}

/// AppKit click, reorder, and drop target for Bookmarks rows. SwiftUI's
/// `.draggable` was swallowing taps, and leftover drag-pasteboard types on the
/// drop overlay could steal a click after a previous drag. A row click is
/// deferred until mouse-up; a drag to reorder starts only after 4pt of movement.
/// File-tree, Finder, search, and backlinks drops still pin a note here.
struct BookmarksDropCatcher: NSViewRepresentable {
    var ws: Workspace
    var parent: UUID?
    var before: UUID?
    var itemID: UUID? = nil
    var dragTitle: String? = nil
    var onClick: ((NSEvent.ModifierFlags) -> Void)? = nil
    var onArmed: (Bool) -> Void

    func makeNSView(context: Context) -> Catcher {
        let v = Catcher()
        v.registerForDraggedTypes(Catcher.dropTypes)
        v.apply(self)
        return v
    }
    func updateNSView(_ v: Catcher, context: Context) { v.apply(self) }

    final class Catcher: NSView, NSDraggingSource {
        static let filenames = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        static let fileTypes: [NSPasteboard.PasteboardType] = [
            .onyxTreePaths, .onyxVaultPaths, .fileURL, filenames,
        ]
        static let dropTypes: [NSPasteboard.PasteboardType] = fileTypes + [.onyxBookmarkID]

        var ws: Workspace?
        var parent: UUID?
        var before: UUID?
        var itemID: UUID?
        var dragTitle: String?
        var onClick: ((NSEvent.ModifierFlags) -> Void)?
        var onArmed: ((Bool) -> Void)?
        private var pointer = TreePointerSession()
        private var pendingClick: NSEvent?
        private var pendingPoint: NSPoint = .zero
        private var armed = false {
            didSet { if armed != oldValue { onArmed?(armed) } }
        }

        func apply(_ s: BookmarksDropCatcher) {
            ws = s.ws
            parent = s.parent
            before = s.before
            itemID = s.itemID
            dragTitle = s.dragTitle
            onClick = s.onClick
            onArmed = s.onArmed
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard bounds.contains(point) else { return nil }
            let e = NSApp.currentEvent
            let claims = BookmarkPointerHit.claimsHit(
                isRow: onClick != nil,
                isLeftMouseDown: e?.type == .leftMouseDown,
                isLeftMouseUp: e?.type == .leftMouseUp,
                isControlClick: e?.modifierFlags.contains(.control) == true,
                mouseButtonHeld: NSEvent.pressedMouseButtons & 1 != 0,
                eventIsDrag: e?.type == .leftMouseDragged,
                pasteboardHasDrop: Self.hasDrop(NSPasteboard(name: .drag))
            )
            return claims ? self : nil
        }

        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) {
                pointer.cancel()
                pendingClick = nil
                nextResponder?.mouseDown(with: event)
                return
            }
            guard onClick != nil else { return }
            let loc = convert(event.locationInWindow, from: nil)
            switch pointer.mouseDown(deferClick: true, canDrag: itemID != nil) {
            case .deferClick, .clickNow:
                pendingClick = event
                pendingPoint = loc
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start = pendingClick, let id = itemID else { return }
            let loc = convert(event.locationInWindow, from: nil)
            let dx = loc.x - pendingPoint.x, dy = loc.y - pendingPoint.y
            guard pointer.mouseDragged(distanceSquared: Double(dx * dx + dy * dy)) == .startDrag else { return }
            pendingClick = nil
            beginReorderDrag(id: id, event: start)
        }

        override func mouseUp(with event: NSEvent) {
            let fire = pointer.mouseUp() == .clickNow
            if fire, let start = pendingClick {
                onClick?(start.modifierFlags)
            }
            pendingClick = nil
        }

        override func rightMouseDown(with event: NSEvent) { nextResponder?.rightMouseDown(with: event) }

        private func beginReorderDrag(id: UUID, event: NSEvent) {
            let pb = NSPasteboardItem()
            pb.setString(id.uuidString, forType: .onyxBookmarkID)
            let item = NSDraggingItem(pasteboardWriter: pb)
            let title = dragTitle ?? "Bookmark"
            let img = Self.previewImage(title: title)
            let size = img.size
            let loc = convert(event.locationInWindow, from: nil)
            item.draggingFrame = NSRect(x: loc.x - 16, y: loc.y - size.height / 2, width: size.width, height: size.height)
            item.imageComponentsProvider = {
                let c = NSDraggingImageComponent(key: .icon)
                c.contents = img
                c.frame = NSRect(origin: .zero, size: size)
                return [c]
            }
            beginDraggingSession(with: [item], event: event, source: self)
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .move }
        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            pointer.cancel()
            pendingClick = nil
        }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { hover(sender) }
        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { hover(sender) }
        override func draggingExited(_ sender: NSDraggingInfo?) { armed = false }
        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { canDrop(sender) }
        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            armed = false
            guard let ws else { return false }
            let pb = sender.draggingPasteboard
            if let id = Self.bookmarkID(from: pb) {
                guard id != itemID else { return false }
                ws.moveBookmark(id: id, parent: parent, before: before)
                return true
            }
            guard let paths = items(from: pb), !paths.isEmpty else { return false }
            ws.bookmarkDropped(paths: paths, parent: parent, before: before)
            return true
        }
        override func draggingEnded(_ sender: NSDraggingInfo) { armed = false }

        private func hover(_ sender: NSDraggingInfo) -> NSDragOperation {
            if let id = Self.bookmarkID(from: sender.draggingPasteboard) {
                let ok = id != itemID
                armed = ok
                return ok ? .move : []
            }
            let ok = !(items(from: sender.draggingPasteboard)?.isEmpty ?? true)
            armed = ok
            return ok ? .copy : []
        }

        private func canDrop(_ sender: NSDraggingInfo) -> Bool {
            if let id = Self.bookmarkID(from: sender.draggingPasteboard) { return id != itemID }
            return !(items(from: sender.draggingPasteboard)?.isEmpty ?? true)
        }

        private func items(from pb: NSPasteboard) -> [(path: String, isFolder: Bool)]? {
            guard let ws else { return nil }
            let tree = pb.string(forType: .onyxTreePaths) ?? pb.string(forType: .onyxVaultPaths)
            return VaultFileDrop.items(treePaths: tree, urls: Self.urls(from: pb), vaultRoot: ws.root) { path, url in
                Self.isFolder(path, url: url, ws: ws)
            }
        }

        static func hasDrop(_ pb: NSPasteboard) -> Bool {
            pb.availableType(from: dropTypes) != nil
        }

        static func bookmarkID(from pb: NSPasteboard) -> UUID? {
            if let s = pb.string(forType: .onyxBookmarkID) { return UUID(uuidString: s) }
            return pb.pasteboardItems?.compactMap { item in
                item.string(forType: .onyxBookmarkID).flatMap(UUID.init(uuidString:))
            }.first
        }

        static func urls(from pb: NSPasteboard) -> [URL] {
            if let objs = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !objs.isEmpty {
                return objs
            }
            if let names = pb.propertyList(forType: filenames) as? [String], !names.isEmpty {
                return names.map { URL(fileURLWithPath: $0) }
            }
            var urls: [URL] = []
            for item in pb.pasteboardItems ?? [] {
                if let s = item.string(forType: .fileURL) {
                    if let url = URL(string: s), url.isFileURL {
                        urls.append(url)
                    } else if s.hasPrefix("/") {
                        urls.append(URL(fileURLWithPath: s))
                    }
                }
            }
            return urls
        }

        static func isFolder(_ path: String, url: URL?, ws: Workspace) -> Bool {
            if ws.snapshot?.folders.contains(path) == true { return true }
            if let url, (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { return true }
            if let root = ws.root {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path, isDirectory: &isDir) {
                    return isDir.boolValue
                }
            }
            return false
        }

        static func previewImage(title: String) -> NSImage {
            let font = NSFont.systemFont(ofSize: 12.5)
            let attr = NSAttributedString(string: title, attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor,
            ])
            let textSize = attr.size()
            let size = NSSize(width: min(textSize.width + 16, 260), height: 24)
            let img = NSImage(size: size)
            img.lockFocus()
            attr.draw(at: NSPoint(x: 8, y: (size.height - textSize.height) / 2))
            img.unlockFocus()
            img.isTemplate = false
            return img
        }
    }
}

extension NSPasteboard.PasteboardType {
    static let onyxVaultPaths = NSPasteboard.PasteboardType("app.onyx.vault-paths")
    static let onyxBookmarkID = NSPasteboard.PasteboardType("org.kennethreitz.onyx.bookmark-id")
}
