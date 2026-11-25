import SwiftUI
import OnyxCore

/// The current note’s headings, or a wider scope up to the whole vault, flattened lazily.
struct OutlineScreen: View {
    @EnvironmentObject private var vault: MobileVault
    @State private var scope: OutlineScope = .note
    @State private var expanded: Set<String> = []
    @State private var collapsedHeadings: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            Picker("Scope", selection: $scope) {
                ForEach(OutlineScope.allCases) { s in
                    Text(s.title).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            if rows.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: "list.bullet.indent",
                                       description: Text(emptyHint))
            } else {
                List(rows) { row in
                    OutlineRowView(row: row, expanded: isOpen(row), toggle: { toggle(row) }) {
                        open(row)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 12 + CGFloat(row.depth) * 14, bottom: 4, trailing: 12))
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Outline")
        .onChange(of: scope) { revealCurrent() }
        .onChange(of: vault.selectedPath) { revealCurrent() }
        .onAppear { if expanded.isEmpty { revealCurrent() } }
    }

    var roots: [OutlineNode] {
        guard let snap = vault.snapshot else { return [] }
        return OutlineTree.build(scope: scope, currentPath: vault.selectedPath,
                                 currentText: vault.selectedNote?.content, snapshot: snap)
    }

    var rows: [OutlineRow] {
        guard let snap = vault.snapshot else { return [] }
        return OutlineTree.flatten(roots, expanded: expanded, headings: { path in
            OutlineTree.headings(for: path, currentPath: vault.selectedPath,
                                 currentText: vault.selectedNote?.content, in: snap)
        }, collapsedHeadings: collapsedHeadings)
    }

    var emptyTitle: String {
        if vault.selectedPath == nil && scope != .vault { return "No note selected" }
        return "No headings yet"
    }

    var emptyHint: String {
        switch scope {
        case .note: return "Lines that start with # build the outline."
        case .folder: return "This folder has no notes yet."
        case .neighbors: return "Nothing is linked or part of this note."
        case .vault: return "This vault has no notes yet."
        }
    }

    func isOpen(_ row: OutlineRow) -> Bool {
        guard row.expandable else { return false }
        if row.kind == .heading { return !collapsedHeadings.contains(row.id) }
        return expanded.contains(row.id)
    }

    func toggle(_ row: OutlineRow) {
        guard row.expandable else { return }
        if row.kind == .heading {
            if collapsedHeadings.contains(row.id) { collapsedHeadings.remove(row.id) }
            else { collapsedHeadings.insert(row.id) }
        } else if expanded.contains(row.id) {
            expanded.remove(row.id)
        } else {
            expanded.insert(row.id)
        }
    }

    func open(_ row: OutlineRow) {
        guard let path = row.path else { return }
        vault.openNote(path, line: row.headingLine)
    }

    func revealCurrent() {
        guard let snap = vault.snapshot else { return }
        let extra = OutlineTree.reveal(vault.selectedPath, in: roots, headings: { path in
            OutlineTree.headings(for: path, currentPath: vault.selectedPath,
                                 currentText: vault.selectedNote?.content, in: snap)
        })
        expanded.formUnion(extra)
        if let p = vault.selectedPath { expanded.insert(OutlineTree.noteId(p)) }
    }
}

private struct OutlineRowView: View {
    var row: OutlineRow
    var expanded: Bool
    var toggle: () -> Void
    var open: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if row.expandable {
                Button(action: toggle) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 18, height: 18)
            }
            Button(action: open) {
                HStack {
                    Text(row.title)
                        .font(row.kind == .heading ? .body : .body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
    }
}
