import Foundation
import simd

/// Link structure of the vault, built once per index change, off the main thread.
public struct GraphIndex: Sendable {
    public var ids: [String] = []
    public var names: [String] = []
    public var folders: [String] = []
    public var mtimes: [Date] = []
    public var tags: [[String]] = []
    public var out: [[Int]] = []
    public var inn: [[Int]] = []
    public var degree: [Int] = []
    public var index: [String: Int] = [:]
    /// Directed `partOf` edges (child -> parents) and symmetric related edges.
    public var partOf: [[Int]] = []
    public var related: [Set<Int>] = []

    public init() {}

    public static func build(_ snap: VaultSnapshot) -> GraphIndex {
        var g = GraphIndex()
        // Canvases join the graph as nodes linking to their file cards (as in Obsidian).
        g.ids = (Array(snap.notes.keys) + snap.canvases.keys.filter { snap.notes[$0] == nil }).sorted()
        for (i, p) in g.ids.enumerated() { g.index[p] = i }
        g.out = Array(repeating: [], count: g.ids.count)
        g.inn = Array(repeating: [], count: g.ids.count)
        g.partOf = Array(repeating: [], count: g.ids.count)
        g.related = Array(repeating: [], count: g.ids.count)
        for (i, p) in g.ids.enumerated() {
            guard let n = snap.notes[p] else {
                g.names.append(((p as NSString).lastPathComponent as NSString).deletingPathExtension)
                g.folders.append((p as NSString).deletingLastPathComponent)
                g.mtimes.append(snap.attachments[p] ?? .distantPast)
                g.tags.append([])
                g.out[i] = Set((snap.canvasLinks[p] ?? []).compactMap { g.index[$0] }).subtracting([i]).sorted()
                continue
            }
            g.names.append(n.name)
            g.folders.append(n.folder)
            g.mtimes.append(n.mtime)
            g.tags.append(n.summary.tags)
            var seen = Set<Int>()
            for l in n.summary.links {
                guard let t = snap.resolve(l.target, from: p), let j = g.index[t], j != i else { continue }
                seen.insert(j)
                switch l.fieldKey.map(InlineField.kind) {
                case "partof": g.partOf[i].append(j)
                case "related", "relatesto": g.related[i].insert(j); g.related[j].insert(i)
                default: break
                }
            }
            g.out[i] = seen.sorted()
        }
        for i in g.ids.indices { for j in g.out[i] { g.inn[j].append(i) } }
        g.degree = g.ids.indices.map { Set(g.out[$0]).union(g.inn[$0]).count }
        return g
    }

    public func neighbors(_ i: Int) -> Set<Int> { Set(out[i]).union(inn[i]) }
    public enum EdgeKind: Sendable { case link, partOf, related }
    public func edgeKind(_ a: Int, _ b: Int) -> EdgeKind {
        if partOf[a].contains(b) || partOf[b].contains(a) { return .partOf }
        if related[a].contains(b) { return .related }
        return .link
    }
    public var count: Int { ids.count }
}

// MARK: - Focus graph: the current note at the center, rings of context around it

public struct FocusNode: Sendable, Equatable {
    public var node: Int
    public var ring: Int            // 0 center, 1 direct, 2 second hop
    public var pos: SIMD2<Double>
    public var outgoing: Bool       // center links to it
    public var incoming: Bool       // it links to the center
    public var parents: [Int]       // ring-1 nodes it hangs off (ring 2)
}

public enum FocusLayout {
    public static func layout(_ g: GraphIndex, center: Int, include: (Int) -> Bool = { _ in true }, maxFirst: Int = 72, maxSecond: Int = 64) -> [FocusNode] {
        var nodes = [FocusNode(node: center, ring: 0, pos: .zero, outgoing: false, incoming: false, parents: [])]
        let outs = Set(g.out[center]), ins = Set(g.inn[center])
        var first = Array(outs.union(ins)).filter(include)
        // keep the most connected if a hub has a huge neighborhood
        if first.count > maxFirst { first = Array(first.sorted { g.degree[$0] > g.degree[$1] }.prefix(maxFirst)) }
        // group by folder so related notes sit together around the ring
        first.sort { (g.folders[$0], g.names[$0].lowercased()) < (g.folders[$1], g.names[$1].lowercased()) }
        let n1 = first.count
        let minSpacing = 34.0
        let r1 = max(150, Double(n1) * minSpacing / (2 * .pi) * (n1 > 28 ? 0.58 : 1))
        var angle: [Int: Double] = [:]
        for (k, i) in first.enumerated() {
            let a = Double(k) / Double(max(n1, 1)) * 2 * .pi - .pi / 2
            let r = n1 > 28 ? (k % 2 == 0 ? r1 : r1 + 58) : r1
            angle[i] = a
            nodes.append(FocusNode(node: i, ring: 1, pos: SIMD2(cos(a) * r, sin(a) * r), outgoing: outs.contains(i), incoming: ins.contains(i), parents: []))
        }
        // second hop: notes linked from the first ring, scored by how many ring-1 notes reach them
        let firstSet = Set(first)
        var reach: [Int: [Int]] = [:]
        for i in first { for j in g.neighbors(i) where j != center && !firstSet.contains(j) && include(j) { reach[j, default: []].append(i) } }
        let second = reach.keys.sorted { (reach[$0]!.count, g.degree[$0], g.names[$1]) > (reach[$1]!.count, g.degree[$1], g.names[$0]) }.prefix(maxSecond)
        let rOuter = (n1 > 28 ? r1 + 58 : r1) + 150
        var placed: [(Int, Double)] = second.map { j in
            let ps = reach[j]!
            let sx = ps.reduce(0.0) { $0 + cos(angle[$1]!) }, sy = ps.reduce(0.0) { $0 + sin(angle[$1]!) }
            return (j, atan2(sy, sx))
        }
        // spread angularly so labels don't pile up
        placed.sort { $0.1 < $1.1 }
        let minGap = 30.0 / rOuter
        if placed.count > 1 && Double(placed.count) * minGap < 2 * .pi {
            for _ in 0..<6 {
                for k in 1..<placed.count where placed[k].1 - placed[k - 1].1 < minGap { placed[k].1 = placed[k - 1].1 + minGap }
                let overflow = placed.last!.1 - (placed.first!.1 + 2 * .pi - minGap)
                if overflow > 0 { for k in placed.indices { placed[k].1 -= overflow * Double(k) / Double(placed.count) } }
            }
        } else if placed.count > 1 {
            for k in placed.indices { placed[k].1 = Double(k) / Double(placed.count) * 2 * .pi - .pi / 2 }
        }
        for (k, (j, a)) in placed.enumerated() {
            let r = rOuter + (placed.count > 40 ? Double(k % 2) * 46 : 0)
            nodes.append(FocusNode(node: j, ring: 2, pos: SIMD2(cos(a) * r, sin(a) * r), outgoing: false, incoming: false, parents: reach[j]!))
        }
        return nodes
    }
}

// MARK: - Atlas: the vault as clusters, expanding into notes as you zoom

public struct AtlasCluster: Sendable {
    public var key: String
    public var label: String
    public var level: Int          // 0 top, 1 sub
    public var parent: Int?
    public var center: SIMD2<Double>
    public var radius: Double
    public var members: [Int]      // note indices
}

public struct Atlas: Sendable {
    public enum Grouping: String, Sendable, CaseIterable { case folders, tags }
    public var clusters: [AtlasCluster] = []
    public var notePos: [Int: SIMD2<Double>] = [:]
    public var noteCluster: [Int: Int] = [:]
    public var topEdges: [(Int, Int, Int)] = []     // (cluster, cluster, weight)
    public var subEdges: [(Int, Int, Int)] = []
    public var orphans: [Int] = []
    public static let spacing = 13.0

    public static func build(_ g: GraphIndex, grouping: Grouping, include: (Int) -> Bool, includeOrphans: Bool) -> Atlas {
        var atlas = Atlas()
        let all = g.ids.indices.filter(include)
        let allSet = Set(all)
        let linked = all.filter { i in g.neighbors(i).contains { allSet.contains($0) } }
        atlas.orphans = all.filter { i in !g.neighbors(i).contains { allSet.contains($0) } }.sorted { g.names[$0] < g.names[$1] }
        let members = includeOrphans ? all : linked

        // grouping keys
        var topKey: [Int: String] = [:], subKey: [Int: String] = [:]
        switch grouping {
        case .folders:
            for i in members {
                let parts = g.folders[i].split(separator: "/").map(String.init)
                topKey[i] = parts.first ?? ""
                subKey[i] = parts.count > 1 ? parts[0] + "/" + parts[1] : (parts.first ?? "")
            }
        case .tags:
            var freq: [String: Int] = [:]
            for i in members { for t in g.tags[i] { freq[t.split(separator: "/").first.map(String.init) ?? t, default: 0] += 1 } }
            let top = Set(freq.sorted { $0.value > $1.value }.prefix(14).map(\.key))
            for i in members {
                let roots = g.tags[i].map { $0.split(separator: "/").first.map(String.init) ?? $0 }
                let best = roots.filter { top.contains($0) }.max { freq[$0]! < freq[$1]! }
                topKey[i] = best.map { "#" + $0 } ?? "untagged"
                let sub = g.tags[i].first { $0.hasPrefix((best ?? "") + "/") }
                subKey[i] = sub.map { "#" + $0 } ?? topKey[i]!
            }
        }

        // sub-clusters: notes on a sunflower, hubs in the middle
        var subMembers: [String: [Int]] = [:]
        for i in members { subMembers[subKey[i]!, default: []].append(i) }
        var subLocal: [String: (radius: Double, pos: [Int: SIMD2<Double>])] = [:]
        for (k, ms) in subMembers {
            let sorted = ms.sorted { (g.degree[$0], g.names[$1]) > (g.degree[$1], g.names[$0]) }
            var pos: [Int: SIMD2<Double>] = [:]
            for (n, i) in sorted.enumerated() {
                let r = spacing * sqrt(Double(n) + 0.5)
                let a = Double(n) * 2.399963
                pos[i] = SIMD2(r * cos(a), r * sin(a))
            }
            subLocal[k] = (spacing * sqrt(Double(sorted.count) + 0.5) + 16, pos)
        }

        // top clusters: pack their sub-clusters
        var topSubs: [String: [String]] = [:]
        for (k, ms) in subMembers { topSubs[topKey[ms[0]]!, default: []].append(k) }
        struct TopTmp { var key: String; var radius: Double; var subs: [(String, SIMD2<Double>, Double)] }
        var tops: [TopTmp] = []
        for (t, subs) in topSubs {
            let circles = pack(subs.map { ($0, subLocal[$0]!.radius) }, gap: 10)
            let extent = circles.map { simd_length($0.1) + $0.2 }.max() ?? 20
            tops.append(TopTmp(key: t, radius: extent + 26, subs: circles))
        }
        tops.sort { $0.radius > $1.radius }

        // place top clusters: weighted attraction by cross-links, hard collision
        var topIndex: [String: Int] = [:]
        for (k, t) in tops.enumerated() { topIndex[t.key] = k }
        var w = [[Int]](repeating: [Int](repeating: 0, count: tops.count), count: tops.count)
        for i in members { for j in g.out[i] where topKey[j] != nil {
            let a = topIndex[topKey[i]!]!, b = topIndex[topKey[j]!]!
            if a != b { w[a][b] += 1; w[b][a] += 1 }
        } }
        var centers: [SIMD2<Double>] = pack(tops.map { ($0.key, $0.radius) }, gap: 40).map { $0.1 }
        for _ in 0..<500 {
            var d = [SIMD2<Double>](repeating: .zero, count: tops.count)
            for a in tops.indices { for b in tops.indices where a < b {
                var v = centers[b] - centers[a]
                var dist = simd_length(v); if dist < 1 { v = SIMD2(1, 0); dist = 1 }
                let minD = tops[a].radius + tops[b].radius + 40
                var f = 0.0
                if dist < minD { f = (dist - minD) * 0.5 } else { f = Double(w[a][b]) > 0 ? min(4, log(1 + Double(w[a][b]))) * 0.6 : -0.0 }
                d[a] += v / dist * f; d[b] -= v / dist * f
            } }
            for a in tops.indices { d[a] -= centers[a] * 0.004; centers[a] += d[a] }
        }
        // emit clusters
        for (k, t) in tops.enumerated() {
            let label = t.key.isEmpty ? "Vault" : t.key
            let ms = t.subs.flatMap { subMembers[$0.0]! }
            atlas.clusters.append(AtlasCluster(key: t.key, label: label, level: 0, parent: nil, center: centers[k], radius: t.radius, members: ms))
        }
        for (k, t) in tops.enumerated() {
            for (sk, off, r) in t.subs {
                let c = centers[k] + off
                let label = sk == t.key ? (t.key.isEmpty ? "Vault" : t.key) + " ·" : String(sk.split(separator: "/").last ?? Substring(sk))
                let ci = atlas.clusters.count
                atlas.clusters.append(AtlasCluster(key: sk, label: label, level: 1, parent: k, center: c, radius: r, members: subMembers[sk]!))
                for (i, p) in subLocal[sk]!.pos { atlas.notePos[i] = c + p; atlas.noteCluster[i] = ci }
            }
        }
        // weighted edges between clusters
        var topW: [Int: Int] = [:], subW: [Int: Int] = [:]
        let n = atlas.clusters.count
        for i in members { for j in g.out[i] {
            guard let ci = atlas.noteCluster[i], let cj = atlas.noteCluster[j], ci != cj else { continue }
            let ti = atlas.clusters[ci].parent!, tj = atlas.clusters[cj].parent!
            if ti != tj { topW[min(ti, tj) * n + max(ti, tj), default: 0] += 1 }
            subW[min(ci, cj) * n + max(ci, cj), default: 0] += 1
        } }
        atlas.topEdges = topW.map { ($0.key / n, $0.key % n, $0.value) }.sorted { $0.2 > $1.2 }
        atlas.subEdges = subW.map { ($0.key / n, $0.key % n, $0.value) }.sorted { $0.2 > $1.2 }
        return atlas
    }

    /// Greedy circle packing around the origin, largest first.
    static func pack(_ items: [(String, Double)], gap: Double) -> [(String, SIMD2<Double>, Double)] {
        let sorted = items.sorted { $0.1 > $1.1 }
        var out: [(String, SIMD2<Double>, Double)] = []
        for (key, r) in sorted {
            if out.isEmpty { out.append((key, .zero, r)); continue }
            var best: SIMD2<Double>? = nil
            var bestDist = Double.infinity
            var radius = 0.0
            while best == nil || radius < bestDist + r * 2 {
                radius += max(6, r * 0.3)
                let steps = max(12, Int(radius / 6))
                for s in 0..<steps {
                    let a = Double(s) / Double(steps) * 2 * .pi
                    let p = SIMD2(cos(a) * radius, sin(a) * radius * 0.82)
                    if out.allSatisfy({ simd_length($0.1 - p) >= $0.2 + r + gap }) {
                        let dd = simd_length(p)
                        if dd < bestDist { bestDist = dd; best = p }
                    }
                }
                if radius > 50000 { break }
            }
            out.append((key, best ?? .zero, r))
        }
        return out
    }
}
