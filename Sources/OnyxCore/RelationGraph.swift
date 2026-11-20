import Foundation

/// The small graph in a link hover card: parents above, parts below, siblings faintly beside
/// the center and related notes to the side. Notes without fields fall back to plain links.
public struct RelationGraph: Sendable, Equatable {
    public enum Role: String, Sendable { case center, parent, part, sibling, related, link }
    public struct Node: Sendable, Equatable {
        public var path: String
        public var name: String
        public var role: Role
        public var x: Double
        public var y: Double
    }
    public var nodes: [Node] = []
    public var hiddenParts = 0
    public var hiddenSiblings = 0

    public static func build(_ snap: VaultSnapshot, center: String, maxRow: Int = 7) -> RelationGraph {
        var g = RelationGraph()
        func name(_ p: String) -> String { snap.notes[p]?.name ?? ((p as NSString).lastPathComponent as NSString).deletingPathExtension }
        func row(_ ps: [String], _ role: Role, y: Double, width: Double = 1) {
            for (k, p) in ps.enumerated() {
                let x = ps.count == 1 ? 0 : (Double(k) / Double(ps.count - 1) - 0.5) * 2 * width
                g.nodes.append(Node(path: p, name: name(p), role: role, x: x, y: y))
            }
        }
        g.nodes.append(Node(path: center, name: name(center), role: .center, x: 0, y: 0))
        let parents = snap.parents(of: center), parts = snap.parts(of: center)
        let hierarchy = Set(parents + parts)
        let related = snap.related(to: center).filter { !hierarchy.contains($0) }
        if parents.isEmpty && parts.isEmpty && related.isEmpty {
            var links = Set(snap.notes[center]?.summary.links.compactMap { snap.resolve($0.target, from: center) } ?? [])
            links.formUnion(snap.backlinks[center] ?? [])
            let ps = links.subtracting([center]).filter { snap.notes[$0] != nil }.sorted { name($0).localizedStandardCompare(name($1)) == .orderedAscending }
            for (k, p) in ps.prefix(12).enumerated() {
                let a = Double(k) / Double(min(ps.count, 12)) * 2 * .pi - .pi / 2
                g.nodes.append(Node(path: p, name: name(p), role: .link, x: cos(a) * 0.82, y: sin(a) * 0.72))
            }
            g.hiddenParts = max(0, ps.count - 12)
            return g
        }
        row(Array(parents.prefix(3)), .parent, y: -0.72, width: 0.42)
        row(Array(parts.prefix(maxRow)), .part, y: 0.62, width: 0.9)
        // stagger a crowded row so its labels get two lanes
        if parts.count > 3 { var k = 0; for i in g.nodes.indices where g.nodes[i].role == .part { if k % 2 == 1 { g.nodes[i].y = 0.9 }; k += 1 } }
        g.hiddenParts = max(0, parts.count - maxRow)
        let used = Set(parents + parts + related + [center])
        let sibs = snap.siblings(of: center).filter { !used.contains($0) }
        // siblings sit faintly beside the center; the right side belongs to related notes when there are any
        let oneSide = !related.isEmpty, cap = oneSide ? 3 : 4
        for (k, p) in sibs.prefix(cap).enumerated() {
            let side = oneSide || k % 2 == 0 ? -1.0 : 1.0
            let lane = oneSide ? k : k / 2
            g.nodes.append(Node(path: p, name: name(p), role: .sibling, x: side * (0.5 + Double(lane % 2) * 0.3), y: -0.24 + Double(lane) * 0.2))
        }
        g.hiddenSiblings = max(0, sibs.count - cap)
        for (k, p) in related.prefix(4).enumerated() {
            g.nodes.append(Node(path: p, name: name(p), role: .related, x: 0.9, y: -0.36 + Double(k) * 0.24))
        }
        return g
    }
}
