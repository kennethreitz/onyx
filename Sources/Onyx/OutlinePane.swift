import SwiftUI
import OnyxCore

/// The inspector's Outline tab: the heading tree of the open note, or a wider scope
/// (folder, linked and partOf neighbors, or the whole vault) with notes as top-level
/// nodes and heading trees nested under them.
struct OutlinePane: View {
    @Bindable var ws: Workspace
    @State private var hover: String?
    @State private var revealedFor: String = ""

    var snap: VaultSnapshot? { ws.snapshot }
    var currentPath: String? { ws.currentPath }
    var currentText: String { ws.settledText }

    var headingsForCurrent: [Heading] {
        guard let p = currentPath, let snap else { return [] }
        return OutlineTree.headings(for: p, currentPath: p, currentText: currentText, in: snap)
    }

    var roots: [OutlineNode] {
        guard let snap else { return [] }
        return OutlineTree.build(scope: ws.outlineScope, currentPath: currentPath, currentText: currentText, snapshot: snap)
    }

    func headings(_ path: String) -> [Heading] {
        guard let snap else { return [] }
        return OutlineTree.headings(for: path, currentPath: currentPath, currentText: currentText, in: snap)
    }

    var rows: [OutlineRow] {
        OutlineTree.flatten(roots, expanded: ws.outlineExpanded, headings: headings, collapsedHeadings: ws.outlineCollapsed)
    }

    var activeId: String? {
        OutlineTree.activeId(path: currentPath, line: ws.outlineTop, headings: headingsForCurrent)
    }

    var emptyHint: (title: String, hint: String?) {
        switch ws.outlineScope {
        case .note:
            return ("No headings yet.", "Lines that start with # build the outline.")
        case .folder:
            return ("Nothing in this folder.", "Open a note to outline its folder.")
        case .neighbors:
            return ("No linked or partOf neighbors.", "Wikilinks and partOf:: notes show up here, with their headings.")
        case .vault:
            return ("No notes in this vault yet.", nil)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            scopeBar
            Divider().overlay(Color.hairline)
            if rows.isEmpty {
                QuietEmpty(title: emptyHint.title, hint: emptyHint.hint).padding(.top, Space.xs)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row in
                            OutlineRowView(ws: ws, row: row, active: row.id == activeId, hovering: hover == row.id,
                                           expanded: row.kind == .heading ? !ws.outlineCollapsed.contains(row.id) : ws.outlineExpanded.contains(row.id),
                                           onHover: { hover = $0 ? row.id : (hover == row.id ? nil : hover) },
                                           onToggle: { toggle(row) },
                                           onOpen: { open(row) })
                        }
                    }
                    .padding(.vertical, 6)
                    .thinScrollers()
                }
            }
        }
        .onAppear { syncReveal(force: true); applyFollow(); ws.syncOutlineTop() }
        .onChange(of: ws.outlineScope) { syncReveal(force: true); applyFollow() }
        .onChange(of: ws.currentPath) { syncReveal(force: true); applyFollow() }
        .onChange(of: activeId) { applyFollow() }
        .onChange(of: ws.inspectorVisible) { if ws.inspectorVisible { ws.syncOutlineTop() } }
        .onChange(of: ws.focusedPane) { ws.syncOutlineTop() }
    }

    var scopeBar: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(OutlineScope.allCases) { s in
                    Button {
                        ws.outlineScope = s
                    } label: {
                        if s == ws.outlineScope { Label(s.title, systemImage: "checkmark") }
                        else { Text(s.title) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(ws.outlineScope.title)
                        .font(.system(size: 11, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .semibold))
                }
                .foregroundStyle(Color.muted)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .help("Outline this note, its folder, its linked and partOf neighbors, or the whole vault.")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
    }

    func syncReveal(force: Bool) {
        let key = "\(ws.outlineScope.rawValue)|\(currentPath ?? "")"
        guard force || revealedFor != key else { return }
        revealedFor = key
        let add = OutlineTree.reveal(currentPath, in: roots, headings: headings)
        if !add.isEmpty { ws.outlineExpanded.formUnion(add) }
    }

    /// Expand only the active path (and a heading's own children); collapse off-path siblings.
    /// Does not scroll the document.
    func applyFollow() {
        guard let id = activeId else { return }
        let result = OutlineTree.follow(
            activeId: id, roots: roots, headings: headings,
            expanded: ws.outlineExpanded, heldOpen: ws.outlineHeldOpen,
            entered: ws.outlineHoldEntered, keepOpen: []
        )
        // Scroll-driven follow must not animate: collapsing off-path branches
        // with Motion.quick (or an inherited transaction) fights the highlight
        // and makes the list jump while you scroll.
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) {
            if result.expand != ws.outlineExpanded { ws.outlineExpanded = result.expand }
            if result.collapse != ws.outlineCollapsed { ws.outlineCollapsed = result.collapse }
            if result.heldOpen != ws.outlineHeldOpen { ws.outlineHeldOpen = result.heldOpen }
            if result.entered != ws.outlineHoldEntered { ws.outlineHoldEntered = result.entered }
        }
    }

    func toggle(_ row: OutlineRow) {
        withAnimation(Motion.quick) {
            if row.kind == .heading {
                if ws.outlineCollapsed.contains(row.id) {
                    ws.outlineCollapsed.remove(row.id)
                    ws.outlineHeldOpen.insert(row.id)
                } else {
                    ws.outlineCollapsed.insert(row.id)
                    ws.outlineHeldOpen.remove(row.id)
                    ws.outlineHoldEntered.remove(row.id)
                }
            } else if ws.outlineExpanded.contains(row.id) {
                ws.outlineExpanded.remove(row.id)
                ws.outlineHeldOpen.remove(row.id)
                ws.outlineHoldEntered.remove(row.id)
            } else {
                ws.outlineExpanded.insert(row.id)
                ws.outlineHeldOpen.insert(row.id)
            }
        }
    }

    func open(_ row: OutlineRow) {
        if row.kind == .heading, let path = row.path, let index = row.headingIndex, let line = row.headingLine {
            ws.jumpToOutlineHeading(path: path, index: index, line: line)
            return
        }
        if row.kind == .note, let path = row.path {
            if path != ws.currentPath { ws.openNote(path) }
            else { ws.scrollToNoteTop() }
            return
        }
        if row.kind == .folder {
            if let path = row.path { ws.openNote(path) }
            else { toggle(row) }
        }
    }
}

private struct OutlineRowView: View {
    var ws: Workspace
    let row: OutlineRow
    var active: Bool
    var hovering: Bool
    var expanded: Bool
    var onHover: (Bool) -> Void
    var onToggle: () -> Void
    var onOpen: () -> Void

    var fill: Double { active ? 0.10 : (hovering ? 0.04 : 0) }

    var titleFont: Font {
        switch row.kind {
        case .folder: return .system(size: 12.5, weight: .medium)
        case .note: return .system(size: 12.5, weight: .regular)
        case .heading:
            let top = (row.headingLevel ?? 1) <= 2
            return Theme.serif(top ? 13 : 12, bold: (row.headingLevel ?? 1) == 1)
        }
    }

    var titleColor: Color {
        switch row.kind {
        case .folder: return Color.ink
        case .note: return Color.ink
        case .heading:
            let level = row.headingLevel ?? 1
            return level <= 2 ? Color.ink : Color.muted
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            if row.expandable {
                Button(action: onToggle) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .foregroundStyle(Color.faint)
                        .frame(width: 12, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Spacer().frame(width: 12)
            }
            Text(row.title)
                .font(titleFont)
                .foregroundStyle(titleColor)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 8 + CGFloat(row.depth) * 12)
        .padding(.trailing, 10)
        .padding(.vertical, 2.5)
        .background(Color.ink.opacity(fill), in: RoundedRectangle(cornerRadius: Radius.control))
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover(perform: onHover)
        .contextMenu { bookmarkMenu }
        .help(row.kind == .heading ? "Jump to this heading" : (row.path != nil ? "Open this note" : "Expand"))
    }

    @ViewBuilder var bookmarkMenu: some View {
        if row.kind == .heading, let path = row.path {
            Button(ws.isBookmarked(path, subpath: row.title) ? "Remove Bookmark" : "Bookmark this heading") {
                ws.toggleBookmark(path: path, isFolder: false, subpath: row.title)
            }
        } else if row.kind == .note, let path = row.path {
            Button(ws.isBookmarked(path) ? "Remove Bookmark" : "Bookmark") {
                ws.toggleBookmark(path: path, isFolder: false)
            }
        }
    }
}
