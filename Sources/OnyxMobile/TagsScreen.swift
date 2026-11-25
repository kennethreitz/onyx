import SwiftUI
import OnyxCore

/// The vault's tags as a nested tree (OnyxCore `TagTree`), like the Mac Tags pane:
/// disclosure per node, counts that include nested tags, sort, a filter, and the notes
/// of the selected tag (nested by default, or exact).
struct TagsScreen: View {
    @EnvironmentObject private var vault: MobileVault

    var body: some View {
        let full = vault.tagTree
        let (tree, autoExpand) = full.filtered(vault.tagFilter)
        let expanded = vault.tagFilter.isEmpty ? vault.tagExpanded : vault.tagExpanded.union(autoExpand)
        let rows = tree.rows(expanded: expanded)
        Group {
            if full.roots.isEmpty {
                ContentUnavailableView("No tags", systemImage: "number",
                                       description: Text("Tags like #tag or #parent/child in your notes, or tags: in their properties, show up here as a tree."))
            } else {
                List {
                    if let sel = vault.tagSelected, let node = full.node(sel) {
                        Section {
                            let notes = vault.taggedNotes(node.key)
                            if notes.isEmpty {
                                Text(vault.tagExact ? "No notes tagged exactly here." : "No notes.").foregroundStyle(.secondary)
                            }
                            ForEach(notes, id: \.path) { n in
                                Button { vault.openNote(n.path) } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(n.name).foregroundStyle(.primary).lineLimit(1)
                                        if !n.folder.isEmpty { Text(n.folder).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                    }
                                }
                            }
                        } header: {
                            HStack {
                                Text("#" + node.path).textCase(nil).font(.system(.footnote, design: .monospaced))
                                Spacer()
                                if !node.children.isEmpty || vault.tagExact {
                                    Button(vault.tagExact ? "Exact" : "+ Nested") { vault.tagExact.toggle() }
                                        .font(.caption).textCase(nil)
                                }
                                Button { vault.tagSelected = nil } label: { Image(systemName: "xmark.circle.fill") }
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section {
                        if rows.isEmpty {
                            Text("No tags match.").foregroundStyle(.secondary)
                        }
                        ForEach(rows) { r in
                            TagTreeRowMobile(row: r, tree: full)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .searchable(text: $vault.tagFilter, prompt: "Filter tags")
            }
        }
        .navigationTitle("Tags")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $vault.tagSort) {
                        Text("By Name").tag(TagTree.Sort.name)
                        Text("By Count").tag(TagTree.Sort.count)
                    }
                    Toggle("Exact Matches Only", isOn: $vault.tagExact)
                    Divider()
                    Button("Expand All") { vault.tagExpanded = Set(full.roots.flatMap { full.subtreeKeys($0.key) }) }
                    Button("Collapse All") { vault.tagExpanded = [] }
                } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
            }
        }
    }
}

private struct TagTreeRowMobile: View {
    @EnvironmentObject private var vault: MobileVault
    var row: TagTree.Row
    var tree: TagTree

    var body: some View {
        let n = row.node
        HStack(spacing: 6) {
            Color.clear.frame(width: CGFloat(row.depth) * 16, height: 1)
            if row.hasChildren {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        if row.expanded { vault.tagExpanded.remove(n.key) } else { vault.tagExpanded.insert(n.key) }
                    }
                } label: {
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(row.expanded ? 90 : 0))
                        .frame(width: 22, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 22, height: 28)
            }
            Button { vault.tagSelected = vault.tagSelected == n.key ? nil : n.key } label: {
                HStack {
                    (Text("#").foregroundStyle(.secondary) + Text(n.name).foregroundStyle(n.ownCount == 0 ? .secondary : .primary))
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(vault.tagSelected == n.key ? .semibold : .regular)
                        .lineLimit(1)
                    Spacer()
                    if !vault.tagExact, row.hasChildren, n.ownCount > 0, n.ownCount != n.totalCount {
                        Text("\(n.ownCount) ·").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                    }
                    Text("\(vault.tagExact ? n.ownCount : n.totalCount)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 16))
        .contextMenu {
            Button("Copy #\(n.path)", systemImage: "doc.on.doc") { UIPasteboard.general.string = "#" + n.path }
            Button("Search Notes", systemImage: "magnifyingglass") { vault.query = "tag:" + n.path; vault.libraryTab = .notes }
            if row.hasChildren {
                Button("Expand All Nested") { vault.tagExpanded.formUnion(tree.subtreeKeys(n.key)) }
                Button("Collapse All Nested") { vault.tagExpanded.subtract(tree.subtreeKeys(n.key)) }
            }
        }
    }
}

extension MobileVault {
    /// The tag tree for the current snapshot, cached until it changes or the sort does.
    var tagTree: TagTree {
        if let c = tagCache, c.gen == snapshotGeneration, c.sort == tagSort { return c.tree }
        let t = TagTree(tags: snapshot?.tags ?? [:], sort: tagSort)
        tagCache = (snapshotGeneration, tagSort, t)
        return t
    }

    func taggedNotes(_ key: String) -> [NoteRecord] {
        guard let snap = snapshot else { return [] }
        return tagTree.notes(for: key, exact: tagExact).compactMap { snap.notes[$0] }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// What tapping a #tag in the reader does: the Tags tab, on that tag, with its parents open.
    func revealTag(_ raw: String) {
        guard let n = TagName.normalize(raw) else { return }
        let key = n.lowercased()
        for a in TagName.ancestry(key).dropLast() { tagExpanded.insert(a) }
        tagSelected = key
        tagFilter = ""
        libraryTab = .tags
    }

    static let tagExpandedKey = "onyx.ios.tags.expanded"
}

extension Notification.Name {
    static let onyxRevealTag = Notification.Name("onyx.ios.revealTag")
}
