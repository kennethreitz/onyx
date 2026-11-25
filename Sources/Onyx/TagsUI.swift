import AppKit
import SwiftUI
import Observation
import OnyxCore

// The Tags sidebar: the vault's #tags as a tree (parent/child/grandchild), with counts,
// a filter box, sort, remembered expansion, the notes of the selected tag, rename/move with
// a preview, and drag-to-re-parent. The logic lives in OnyxCore (Tags.swift).

/// What the Tags pane remembers. Expansion is kept per vault.
@MainActor @Observable
final class TagsModel {
    var sort: TagTree.Sort = TagTree.Sort(rawValue: UserDefaults.standard.string(forKey: "onyx.tags.sort") ?? "") ?? .name {
        didSet { UserDefaults.standard.set(sort.rawValue, forKey: "onyx.tags.sort") }
    }
    /// Show only notes tagged exactly (not with nested tags) for the selected tag.
    var exactOnly = UserDefaults.standard.bool(forKey: "onyx.tags.exact") {
        didSet { UserDefaults.standard.set(exactOnly, forKey: "onyx.tags.exact") }
    }
    var expanded: Set<String> = [] { didSet { if expanded != oldValue { saveExpanded() } } }
    /// The selected node's lowercased path.
    var selected: String?
    var filter = ""
    var rename: TagRenameDraft?
    /// The notes the last rename wrote, for Undo Rename.
    var lastUndo: [TagRename.FileChange]?
    var lastUndoLabel = ""
    /// Bumped to scroll the tree to `selected`.
    var scrollToken = 0
    @ObservationIgnored var cache: (gen: Int, sort: TagTree.Sort, tree: TagTree)?
    @ObservationIgnored private var vault = ""

    func attach(vault path: String) {
        guard path != vault else { return }
        vault = path
        expanded = Set(UserDefaults.standard.stringArray(forKey: expandedKey) ?? [])
        selected = nil; filter = ""; lastUndo = nil; cache = nil
    }
    private var expandedKey: String { "onyx.tags.expanded." + vault }
    private func saveExpanded() {
        guard !vault.isEmpty else { return }
        UserDefaults.standard.set(expanded.sorted(), forKey: expandedKey)
    }
}

struct TagRenameDraft: Identifiable {
    let id = UUID()
    var from: String       // display path
    var to: String
    var title = "Rename Tag"
}

@MainActor
extension Workspace {
    /// The tag tree for the current snapshot, cached until the vault changes.
    func tagTree() -> TagTree {
        if let r = root { tags.attach(vault: r.path) }
        if let c = tags.cache, c.gen == snapshotGen, c.sort == tags.sort { return c.tree }
        let t = TagTree(tags: snapshot?.tags ?? [:], sort: tags.sort)
        tags.cache = (snapshotGen, tags.sort, t)
        return t
    }

    /// Open the Tags pane on `tag`: select it, open its parents, scroll to it.
    func revealTag(_ raw: String) {
        guard let n = TagName.normalize(raw) else { return }
        _ = tagTree()
        let key = n.lowercased()
        for a in TagName.ancestry(key).dropLast() { tags.expanded.insert(a) }
        tags.selected = key
        tags.filter = ""
        tags.scrollToken += 1
        sidebarTab = .tags
        if !sidebarVisible { toggleSidebar() }
    }

    /// The selected tag's notes, by name.
    func taggedNotes(_ tag: String, exact: Bool) -> [NoteRecord] {
        guard let snap = snapshot else { return [] }
        return tagTree().notes(for: tag, exact: exact).compactMap { snap.notes[$0] }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func searchTag(_ path: String) {
        searchQuery = "tag:" + path
        sidebarTab = .search
        if !sidebarVisible { toggleSidebar() }
    }

    func beginTagRename(_ from: String, to: String? = nil, title: String = "Rename Tag") {
        tags.rename = TagRenameDraft(from: from, to: to ?? from, title: title)
    }

    /// The rename's preview: only notes that carry the tag (or a nested one), plus open buffers.
    func planTagRename(from: String, to: String) -> TagRename.Plan {
        let (texts, tree) = tagRenameInputs(from: from)
        return TagRename.plan(texts: texts, from: from, to: to, existing: tree)
    }

    /// What a rename reads: the live text of every note under the tag, and the tree.
    func tagRenameInputs(from: String) -> ([String: String], TagTree) {
        let tree = tagTree()
        let all = replaceContents()
        var paths = tree.notes(for: from)
        if let p = currentPath { paths.insert(p) }
        for pane in panes { if let p = pane.path { paths.insert(p) } }
        var texts: [String: String] = [:]
        for p in paths { if let t = all[p] { texts[p] = t } }
        return (texts, tree)
    }

    @discardableResult
    func applyTagRename(_ plan: TagRename.Plan) -> Bool {
        flushSave()
        var written: [TagRename.FileChange] = []
        for c in plan.changes where writeReplacedNote(c.path, from: c.before, to: c.after) { written.append(c) }
        guard !written.isEmpty else { toast = "Couldn’t rename #\(plan.from)."; return false }
        // carry expansion and selection over to the new names
        let to = plan.to
        tags.expanded = Set(tags.expanded.map { TagName.moved($0, from: plan.from, to: to)?.lowercased() ?? $0 })
        for a in TagName.ancestry(to.lowercased()).dropLast() { tags.expanded.insert(a) }
        if let s = tags.selected { tags.selected = TagName.moved(s, from: plan.from, to: to)?.lowercased() ?? s }
        tags.lastUndo = written
        tags.lastUndoLabel = "#\(plan.from) → #\(to)"
        let notes = written.count == 1 ? "1 note" : "\(written.count) notes"
        toast = "Renamed #\(plan.from) to #\(to) in \(notes)."
        tags.scrollToken += 1
        return true
    }

    @discardableResult
    func undoTagRename() -> Bool {
        guard let edits = tags.lastUndo else { return false }
        flushSave()
        var n = 0
        for c in edits where writeReplacedNote(c.path, from: c.after, to: c.before) { n += 1 }
        tags.lastUndo = nil
        toast = n == 1 ? "Undid tag rename in 1 note." : "Undid tag rename in \(n) notes."
        return n > 0
    }

    /// Tag completion rows for the editor.
    func tagSuggestions(_ q: String) -> [LinkSuggestion] {
        let tree = tagTree()
        return TagCompletion.suggestions(q, paths: tree.allPaths).enumerated().map { i, s in
            let chars = Self.characterOffsets(s.path, utf16: s.hits)
            let n = s.count == 1 ? "1 note" : "\(s.count) notes"
            return LinkSuggestion(id: i, title: "#" + s.path, detail: s.hasChildren ? "\(n)  ▸" : n,
                                  titleHits: chars.map { $0 + 1 }, insert: TagCompletion.insertText(s), exact: s.exact)
        }
    }

    static func characterOffsets(_ s: String, utf16 offs: [Int]) -> [Int] {
        guard !offs.isEmpty else { return [] }
        let want = Set(offs)
        var out: [Int] = [], u = 0
        for (i, ch) in s.enumerated() {
            if want.contains(u) { out.append(i) }
            u += ch.utf16.count
        }
        return out
    }
}

// MARK: - Panel

struct TagsPanel: View {
    @Bindable var ws: Workspace
    @FocusState private var filterFocused: Bool

    var body: some View {
        let m = ws.tags
        let full = ws.tagTree()
        let (tree, autoExpand) = full.filtered(m.filter)
        let expanded = m.filter.isEmpty ? m.expanded : m.expanded.union(autoExpand)
        let rows = tree.rows(expanded: expanded)
        VStack(spacing: 0) {
            filterBar(m, full)
            if full.roots.isEmpty {
                QuietEmpty(title: "No tags yet.", hint: "Type #tag or #parent/child in a note, or add tags: to its properties.")
                Spacer(minLength: 0)
            } else if rows.isEmpty {
                QuietEmpty(title: "No tags match.", hint: "Filter by any part of a tag’s path.")
                Spacer(minLength: 0)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(rows) { r in
                                TagTreeRow(ws: ws, row: r, tree: full, selected: m.selected == r.node.key, exactOnly: m.exactOnly)
                                    .id(r.node.key)
                            }
                        }
                        .padding(.vertical, 4)
                        .thinScrollers()
                        Color.clear.frame(height: 36).contentShape(Rectangle())
                            .dropDestination(for: String.self) { items, _ in dropToTop(items, full) }
                    }
                    .onChange(of: m.scrollToken) {
                        guard let s = m.selected else { return }
                        DispatchQueue.main.async { withAnimation(Motion.quick) { proxy.scrollTo(s, anchor: .center) } }
                    }
                    .onAppear { if let s = m.selected { proxy.scrollTo(s, anchor: .center) } }
                }
            }
            if let sel = m.selected, let node = full.node(sel) {
                Divider().overlay(Color.hairline)
                TagNotesSection(ws: ws, node: node)
            }
        }
        .sheet(item: Bindable(m).rename) { d in TagRenameSheet(ws: ws, draft: d) }
    }

    func filterBar(_ m: TagsModel, _ full: TagTree) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal.decrease").font(.system(size: 10)).foregroundStyle(Color.faint)
            TextField(full.count == 0 ? "Filter tags" : "Filter \(full.count) tags", text: Bindable(m).filter)
                .textFieldStyle(.plain).font(.system(size: 11.5)).focused($filterFocused)
                .onSubmit {   // ↩ selects the first tag that matches
                    let f = full.filtered(m.filter)
                    let words = m.filter.lowercased().split(separator: " ").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
                    if let hit = f.tree.rows(expanded: f.expand).first(where: { r in words.allSatisfy { r.node.key.contains($0) } }) {
                        m.expanded.formUnion(f.expand); m.selected = hit.node.key; m.filter = ""; m.scrollToken += 1
                    }
                }
                .onExitCommand { m.filter = ""; filterFocused = false }
            if !m.filter.isEmpty {
                Button { m.filter = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 10.5)).foregroundStyle(Color.faint) }
                    .buttonStyle(.plain).help("Clear filter")
            }
            Menu {
                Picker("Sort", selection: Bindable(m).sort) {
                    Text("By Name").tag(TagTree.Sort.name)
                    Text("By Count").tag(TagTree.Sort.count)
                }.pickerStyle(.inline)
                Divider()
                Toggle("Exact Matches Only", isOn: Bindable(m).exactOnly)
                Divider()
                Button("Expand All") { m.expanded = Set(full.roots.flatMap { full.subtreeKeys($0.key) }) }
                Button("Collapse All") { m.expanded = [] }
                if m.lastUndo != nil {
                    Divider()
                    Button("Undo Rename \(m.lastUndoLabel)") { ws.undoTagRename() }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down").font(.system(size: 10.5)).foregroundStyle(m.sort == .name ? Color.faint : Color.ink)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().frame(width: 22, height: 22)
            .help("Sort \(m.sort == .name ? "by name" : "by count")\(m.exactOnly ? " · exact matches only" : "")")
        }
        .padding(.horizontal, 8).frame(height: 26)
        .background(RoundedRectangle(cornerRadius: Radius.control).fill(Color.ink.opacity(0.04)))
        .padding(.horizontal, 8).padding(.top, 4).padding(.bottom, 2)
    }

    func dropToTop(_ items: [String], _ tree: TagTree) -> Bool {
        guard let from = TagDrag.tag(items), TagName.parent(from) != nil else { return false }
        ws.beginTagRename(from, to: TagName.reparented(from, onto: nil), title: "Move Tag")
        return true
    }
}

enum TagDrag {
    static let prefix = "onyx-tag:"
    static func payload(_ path: String) -> String { prefix + path }
    static func tag(_ items: [String]) -> String? {
        guard let s = items.first, s.hasPrefix(prefix) else { return nil }
        return String(s.dropFirst(prefix.count))
    }
    /// Whether dropping `from` onto `target` means anything: not onto itself, its own subtree,
    /// or the parent it already has.
    static func canDrop(_ from: String, onto target: String) -> Bool {
        let f = from.lowercased(), t = target.lowercased()
        if t == f || t.hasPrefix(f + "/") { return false }
        return TagName.parent(f) != t
    }
}

/// One row of the tree: disclosure, name, counts. Click selects, double-click (or the
/// triangle) opens; ⌥-click opens everything beneath. Drag onto another tag to nest it there.
struct TagTreeRow: View {
    var ws: Workspace
    var row: TagTree.Row
    var tree: TagTree
    var selected: Bool
    var exactOnly: Bool
    @State private var hover = false
    @State private var targeted = false

    var node: TagNode { row.node }

    var body: some View {
        HStack(spacing: 2) {
            Color.clear.frame(width: CGFloat(row.depth) * 13, height: 1)
            Group {
                if row.hasChildren {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Color.faint)
                        .rotationEffect(.degrees(row.expanded ? 90 : 0))
                        .frame(width: 14, height: 22)
                        .contentShape(Rectangle())
                        .onTapGesture { toggle(deep: NSEvent.modifierFlags.contains(.option)) }
                } else {
                    Color.clear.frame(width: 14, height: 22)
                }
            }
            (Text("#").foregroundColor(Color.faint) + Text(node.name).foregroundColor(node.ownCount == 0 && !selected ? Color.muted : Color.ink))
                .font(.custom("IBMPlexMono", size: 11.5))
                .fontWeight(selected ? .semibold : .regular)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 6)
            counts
        }
        .padding(.leading, 6).padding(.trailing, 12).frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: Radius.control)
                .fill(Color.ink.opacity(selected ? 0.08 : hover ? 0.04 : 0))
                .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Color.cursorBlue.opacity(targeted ? 0.7 : 0), lineWidth: 1.2))
                .padding(.horizontal, 5)
        )
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { if row.hasChildren { toggle(deep: false) } }
        .onTapGesture { ws.tags.selected = selected ? nil : node.key }
        .help(help)
        .draggable(TagDrag.payload(node.path)) {
            Text("#" + node.path).font(.custom("IBMPlexMono", size: 11.5)).padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: Radius.control).fill(Color.paper))
        }
        .dropDestination(for: String.self) { items, _ in
            guard let from = TagDrag.tag(items), TagDrag.canDrop(from, onto: node.path) else { return false }
            ws.beginTagRename(from, to: TagName.reparented(from, onto: node.path), title: "Move Tag")
            return true
        } isTargeted: { targeted = $0 }
        .contextMenu { menu }
        .animation(Motion.quick, value: row.expanded)
    }

    @ViewBuilder var counts: some View {
        let total = exactOnly ? node.ownCount : node.totalCount
        HStack(spacing: 3) {
            if !exactOnly, row.hasChildren, node.ownCount > 0, node.ownCount != node.totalCount {
                Text("\(node.ownCount)").foregroundStyle(Color.faint.opacity(0.75))
                Text("·").foregroundStyle(Color.faint.opacity(0.5))
            }
            Text("\(total)").foregroundStyle(Color.faint)
        }
        .font(.system(size: TypeScale.caption).monospacedDigit())
    }

    var help: String {
        let own = node.ownCount == 1 ? "1 note tagged here" : "\(node.ownCount) notes tagged here"
        guard row.hasChildren else { return "#\(node.path) · \(own)" }
        return "#\(node.path) · \(own), \(node.totalCount) including nested tags"
    }

    func toggle(deep: Bool) {
        let m = ws.tags
        if row.expanded {
            if deep { m.expanded.subtract(tree.subtreeKeys(node.key)) } else { m.expanded.remove(node.key) }
        } else {
            if deep { m.expanded.formUnion(tree.subtreeKeys(node.key)) } else { m.expanded.insert(node.key) }
        }
    }

    @ViewBuilder var menu: some View {
        Button("Show Notes") { ws.tags.selected = node.key }
        Button("Search in Vault") { ws.searchTag(node.path) }
        Divider()
        Button("Rename…") { ws.beginTagRename(node.path) }
        if TagName.parent(node.path) != nil {
            Button("Move to Top Level") { ws.beginTagRename(node.path, to: TagName.leaf(node.path), title: "Move Tag") }
        }
        Button("Copy #\(node.path)") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("#" + node.path, forType: .string)
        }
        if row.hasChildren {
            Divider()
            Button("Expand All Nested") { ws.tags.expanded.formUnion(tree.subtreeKeys(node.key)) }
            Button("Collapse All Nested") { ws.tags.expanded.subtract(tree.subtreeKeys(node.key)) }
        }
    }
}

/// The notes under the selected tag, with nested/exact and a jump into Search.
struct TagNotesSection: View {
    var ws: Workspace
    var node: TagNode
    @State private var hover: String?

    var body: some View {
        let m = ws.tags
        let notes = ws.taggedNotes(node.key, exact: m.exactOnly)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("#" + node.path).font(.custom("IBMPlexMono", size: 11)).foregroundStyle(Color.ink).lineLimit(1).truncationMode(.head)
                Text("\(notes.count)").font(.system(size: TypeScale.caption).monospacedDigit()).foregroundStyle(Color.faint)
                Spacer(minLength: 4)
                if !node.children.isEmpty || m.exactOnly {
                    Button { m.exactOnly.toggle() } label: {
                        Text(m.exactOnly ? "Exact" : "+ Nested").font(.system(size: 10, weight: .medium))
                            .foregroundStyle(m.exactOnly ? Color.ink : Color.muted)
                            .padding(.horizontal, 6).frame(height: 18)
                            .background(RoundedRectangle(cornerRadius: Radius.small).fill(Color.ink.opacity(0.06)))
                    }.buttonStyle(.plain)
                    .help(m.exactOnly ? "Showing notes tagged exactly #\(node.path). Click to include nested tags." : "Including notes with nested tags (#\(node.path)/…). Click for exact matches only.")
                }
                Button { ws.searchTag(node.path) } label: { Image(systemName: "magnifyingglass").font(.system(size: 10.5)).foregroundStyle(Color.faint) }
                    .buttonStyle(.plain).help("Search for tag:\(node.path)")
                Button { m.selected = nil } label: { Image(systemName: "xmark").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Color.faint) }
                    .buttonStyle(.plain).help("Close")
            }
            .padding(.horizontal, 12).padding(.top, 7).padding(.bottom, 4)
            if notes.isEmpty {
                Text(m.exactOnly ? "No notes tagged exactly here." : "No notes.").font(.system(size: 11)).foregroundStyle(Color.faint).padding(.horizontal, 14).padding(.bottom, 8)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(notes, id: \.path) { n in
                            HStack(spacing: 6) {
                                Text(n.name).font(.system(size: 12)).foregroundStyle(ws.currentPath == n.path ? Color.ink : Color.muted)
                                    .fontWeight(ws.currentPath == n.path ? .medium : .regular).lineLimit(1)
                                Spacer(minLength: 4)
                                if !n.folder.isEmpty {
                                    Text(n.folder).font(.system(size: 10)).foregroundStyle(Color.faint).lineLimit(1).truncationMode(.head)
                                }
                            }
                            .padding(.horizontal, 12).frame(height: 22)
                            .background(RoundedRectangle(cornerRadius: Radius.control).fill(Color.ink.opacity(hover == n.path ? 0.04 : 0)).padding(.horizontal, 5))
                            .contentShape(Rectangle())
                            .onHover { hover = $0 ? n.path : (hover == n.path ? nil : hover) }
                            .onTapGesture { ws.openNote(n.path) }
                            .help(n.path)
                        }
                    }.padding(.bottom, 6).thinScrollers()
                }
                .frame(maxHeight: min(CGFloat(notes.count) * 22 + 8, 240))
            }
        }
        .background(Color.ink.opacity(0.015))
    }
}

// MARK: - Rename sheet

/// Rename or move a tag and everything nested under it, across the vault, with a preview of
/// every line that changes. Frontmatter `tags:` and inline `#tags` both; code never.
struct TagRenameSheet: View {
    var ws: Workspace
    var draft: TagRenameDraft
    @State private var name = ""
    @State private var plan: TagRename.Plan?
    @State private var task: Task<Void, Never>?
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var problem: String? { TagName.renameProblem(from: draft.from, to: name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(draft.title).font(.system(size: 13, weight: .semibold))
            Text("#\(draft.from) and every tag nested under it, in properties and in text.")
                .font(.system(size: 11)).foregroundStyle(Color.muted)
            HStack(spacing: 2) {
                Text("#").foregroundStyle(Color.faint)
                TextField("new/name", text: $name).textFieldStyle(.plain).focused($focused)
                    .onSubmit { if canApply { apply() } }
            }
            .font(.custom("IBMPlexMono", size: 12.5))
            .padding(.horizontal, 8).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: Radius.control).fill(Color.ink.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Color.hairline))
            summary
            preview
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(draft.title == "Move Tag" ? "Move" : "Rename") { apply() }
                    .keyboardShortcut(.defaultAction).disabled(!canApply)
            }
        }
        .padding(18)
        .frame(width: 500, height: 440)
        .onAppear { name = draft.to; focused = true; recompute() }
        .onChange(of: name) { recompute() }
    }

    var canApply: Bool { problem == nil && (plan?.changes.isEmpty == false) && plan?.to == TagName.normalize(name) }

    @ViewBuilder var summary: some View {
        if let p = problem, name != draft.from {
            Label(p, systemImage: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(Color.warn)
        } else if let plan, problem == nil {
            VStack(alignment: .leading, spacing: 3) {
                let tags = plan.renames.count == 1 ? "1 tag" : "\(plan.renames.count) tags"
                let notes = plan.changes.count == 1 ? "1 note" : "\(plan.changes.count) notes"
                Text(plan.changes.isEmpty ? "Nothing to change." : "Changes \(tags) in \(notes) (\(plan.occurrences) \(plan.occurrences == 1 ? "place" : "places")).")
                    .font(.system(size: 11)).foregroundStyle(Color.ink)
                if plan.merges {
                    Label("#\(plan.to) already exists. The tags will merge.", systemImage: "arrow.triangle.merge")
                        .font(.system(size: 11)).foregroundStyle(Color.warn)
                }
                ForEach(Array(plan.renames.prefix(5).enumerated()), id: \.offset) { _, r in
                    (Text("#" + r.0).foregroundColor(Color.faint) + Text("  →  ").foregroundColor(Color.faint) + Text("#" + r.1).foregroundColor(Color.ink))
                        .font(.custom("IBMPlexMono", size: 10.5)).lineLimit(1).truncationMode(.middle)
                }
                if plan.renames.count > 5 { Text("and \(plan.renames.count - 5) more").font(.system(size: 10.5)).foregroundStyle(Color.faint) }
            }
        } else {
            Text(" ").font(.system(size: 11))
        }
    }

    @ViewBuilder var preview: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if let plan, problem == nil {
                    ForEach(plan.changes, id: \.path) { c in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.path).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Color.muted).lineLimit(1).truncationMode(.head)
                            ForEach(Array(c.lines.prefix(4).enumerated()), id: \.offset) { _, l in
                                Text(clip(l.before)).strikethrough(color: Color.danger.opacity(0.6)).foregroundStyle(Color.faint)
                                    .font(.custom("IBMPlexMono", size: 10.5)).lineLimit(1)
                                Text(clip(l.after)).foregroundStyle(Color.ink)
                                    .font(.custom("IBMPlexMono", size: 10.5)).lineLimit(1)
                            }
                            if c.lines.count > 4 { Text("+\(c.lines.count - 4) more lines").font(.system(size: 10)).foregroundStyle(Color.faint) }
                        }
                    }
                }
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(RoundedRectangle(cornerRadius: Radius.control).fill(Color.ink.opacity(0.025)))
        .overlay(RoundedRectangle(cornerRadius: Radius.control).strokeBorder(Color.hairline))
    }

    func clip(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.count > 90 ? String(t.prefix(90)) + "…" : t
    }

    /// Re-plan as the name changes: debounced, off the main thread (a big tag touches 1000+ notes).
    func recompute() {
        task?.cancel()
        guard problem == nil, let n = TagName.normalize(name) else { plan = nil; return }
        let (texts, tree) = ws.tagRenameInputs(from: draft.from)
        let from = draft.from
        let first = plan == nil
        task = Task {
            if !first { try? await Task.sleep(for: .milliseconds(120)) }
            guard !Task.isCancelled else { return }
            let p = await Task.detached(priority: .userInitiated) { TagRename.plan(texts: texts, from: from, to: n, existing: tree) }.value
            guard !Task.isCancelled else { return }
            plan = p
        }
    }

    func apply() {
        guard let n = TagName.normalize(name), problem == nil else { return }
        let p = plan?.to == n ? plan! : ws.planTagRename(from: draft.from, to: n)
        if ws.applyTagRename(p) { dismiss() }
    }
}

// MARK: - Inspector chips

/// `#tag` chips that open the tag in the Tags pane.
struct TagChips: View {
    var ws: Workspace
    var tags: [String]
    var body: some View {
        TagFlow(spacing: 4) {
            ForEach(tags, id: \.self) { t in
                Button { ws.revealTag(t) } label: {
                    Text("#" + t).font(.custom("IBMPlexMono", size: 10.5)).foregroundStyle(Color.muted)
                        .padding(.horizontal, 5).frame(height: 18)
                        .background(RoundedRectangle(cornerRadius: Radius.small).fill(Color.ink.opacity(0.05)))
                }.buttonStyle(.plain).help("Show #\(t) in Tags")
            }
        }
    }
}

/// A minimal wrapping layout.
struct TagFlow: Layout {
    var spacing: CGFloat = 4
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > w { x = 0; y += line + spacing; line = 0 }
            x += sz.width + spacing; line = max(line, sz.height); maxX = max(maxX, x - spacing)
        }
        return CGSize(width: min(maxX, w), height: y + line)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + sz.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing; line = max(line, sz.height)
        }
    }
}
