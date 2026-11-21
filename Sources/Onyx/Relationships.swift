import SwiftUI
import OnyxCore

/// The inspector's relationship rows, above the backlinks: Part of, Parts (a collapsible tree),
/// Siblings (folded), Related, then any other link-valued field grouped by key, both directions.
struct RelationshipsSection: View {
    @Bindable var ws: Workspace
    let note: NoteRecord
    let snap: VaultSnapshot
    @State private var showSiblings = false
    @State private var open: Set<String> = []

    var body: some View {
        let path = note.path
        let parents = snap.parents(of: path), parts = snap.parts(of: path), related = snap.related(to: path)
        let siblings = snap.siblings(of: path)
        let unresolved = note.summary.links.filter { $0.fieldKey.map(InlineField.kind) == "partof" && snap.resolve($0.target, from: path) == nil }
        let fields = snap.fieldRelations(of: path)
        VStack(alignment: .leading, spacing: 0) {
            if !parents.isEmpty || !unresolved.isEmpty {
                title("Part of")
                ForEach(parents, id: \.self) { NoteRow(ws: ws, path: $0, preview: true) }
                ForEach(unresolved, id: \.target) { l in
                    Button { ws.openLink(l.target) } label: { Text("\(l.alias ?? l.target)  · create").font(.system(size: 12)).foregroundStyle(Color.muted) }
                        .buttonStyle(.plain).padding(.horizontal, 17).padding(.vertical, 4)
                }
            }
            if !parts.isEmpty {
                let total = Ancestry.descendantCount(of: path, parts: { snap.parts(of: $0) })
                title(total > parts.count ? "Parts · \(parts.count) · \(total) in all" : "Parts · \(parts.count)")
                tree(Ancestry.partsTree(of: path, parts: { snap.parts(of: $0) }), depth: 0, trail: path)
            }
            if !siblings.isEmpty {
                Button { withAnimation(.easeOut(duration: 0.15)) { showSiblings.toggle() } } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right").rotationEffect(.degrees(showSiblings ? 90 : 0)).font(.system(size: 7.5, weight: .semibold))
                        Text("SIBLINGS · \(siblings.count)").font(.system(size: 9.5, weight: .semibold)).tracking(0.8)
                    }.foregroundStyle(Color.faint).contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 4)
                if showSiblings { ForEach(siblings, id: \.self) { NoteRow(ws: ws, path: $0, preview: true) } }
            }
            if !related.isEmpty {
                title("Related · \(related.count)")
                ForEach(related, id: \.self) { NoteRow(ws: ws, path: $0, preview: true) }
            }
            ForEach(fields, id: \.kind) { f in
                if !f.outgoing.isEmpty {
                    title(f.key)
                    ForEach(f.outgoing, id: \.self) { NoteRow(ws: ws, path: $0, preview: true) }
                }
                if !f.incoming.isEmpty {
                    title("\(f.key) · from")
                    ForEach(f.incoming, id: \.self) { NoteRow(ws: ws, path: $0, preview: true) }
                }
            }
        }
    }

    func title(_ s: String) -> some View {
        Text(s.uppercased()).font(.system(size: 9.5, weight: .semibold)).tracking(0.8).foregroundStyle(Color.faint)
            .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 4)
    }

    /// Parts with their own parts get a disclosure chevron; a note that loops back is marked ↻.
    func tree(_ nodes: [Ancestry.Node], depth: Int, trail: String) -> AnyView {
        AnyView(ForEach(nodes, id: \.path) { n in
            let id = trail + "›" + n.path
            let kids = !n.children.isEmpty
            HStack(spacing: 0) {
                Group {
                    if kids {
                        Image(systemName: "chevron.right").font(.system(size: 7.5, weight: .semibold)).foregroundStyle(Color.faint)
                            .rotationEffect(.degrees(open.contains(id) ? 90 : 0))
                            .frame(width: 14, height: 22).contentShape(Rectangle())
                            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { if open.contains(id) { open.remove(id) } else { open.insert(id) } } }
                            .help(open.contains(id) ? "Hide parts" : "Show \(n.children.count) parts")
                    } else { Color.clear.frame(width: 14, height: 1) }
                }.padding(.leading, CGFloat(depth) * 12)
                PartRow(ws: ws, path: n.path, note: n.cycle ? "↻ loops back" : (n.hidden > 0 ? "+\(n.hidden) more" : (kids && !open.contains(id) ? "\(n.children.count)" : nil)))
            }.padding(.leading, 4)
            if kids && open.contains(id) { tree(n.children, depth: depth + 1, trail: id) }
        })
    }
}

/// A one-line parts-tree row: the note name, a faint count or note on the right.
struct PartRow: View {
    @Bindable var ws: Workspace
    let path: String
    var note: String?
    @State private var hover = false
    var body: some View {
        HStack(spacing: 6) {
            Text(((path as NSString).lastPathComponent as NSString).deletingPathExtension).font(.system(size: 12.5)).foregroundStyle(Color.ink).lineLimit(1)
            Spacer(minLength: 4)
            if let note { Text(note).font(.system(size: 10.5)).foregroundStyle(Color.faint).lineLimit(1) }
        }
        .padding(.leading, 2).padding(.trailing, 12).frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 5).fill(ws.currentPath == path ? Color.ink.opacity(0.08) : (hover ? Color.ink.opacity(0.04) : .clear)).padding(.trailing, 5))
        .contentShape(Rectangle())
        .background { GraphPreviewTrigger(ws: ws, path: path) }
        .contextMenu { FileMenu(ws: ws, path: path) }
        .onHover { hover = $0 }
        .onTapGesture { GraphPreviewController.shared.close(); ws.openNote(path) }
        .help((path as NSString).deletingLastPathComponent)
    }
}
