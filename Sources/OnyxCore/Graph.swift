import Foundation
import simd

/// A force-directed layout for the wikilink graph. Repulsion uses a uniform
/// spatial grid (only nearby cells interact), so a 2,400-node vault settles
/// in well under a second off the main thread.
public struct GraphData: Sendable {
    public var ids: [String]
    public var labels: [String]
    public var edges: [(Int, Int)]
    public var degree: [Int]
    public var positions: [SIMD2<Float>]
    public var isUnresolved: [Bool]

    public static func build(_ snap: VaultSnapshot, focus: String? = nil, depth: Int = 1, includeOrphans: Bool = true) -> GraphData {
        var adj: [String: Set<String>] = [:]
        for (p, n) in snap.notes {
            for l in n.summary.links {
                guard let t = snap.resolve(l.target, from: p), t != p, snap.notes[t] != nil else { continue }
                adj[p, default: []].insert(t); adj[t, default: []].insert(p)
            }
        }
        var keep: [String]
        if let f = focus {
            var seen: Set<String> = [f]
            var frontier: Set<String> = [f]
            for _ in 0..<max(1, depth) {
                var next: Set<String> = []
                for x in frontier { for y in adj[x] ?? [] where !seen.contains(y) { next.insert(y) } }
                seen.formUnion(next); frontier = next
            }
            keep = seen.sorted()
        } else {
            keep = snap.notes.keys.filter { includeOrphans || !(adj[$0]?.isEmpty ?? true) }.sorted()
        }
        var index: [String: Int] = [:]
        for (i, k) in keep.enumerated() { index[k] = i }
        var edges: [(Int, Int)] = []
        var degree = [Int](repeating: 0, count: keep.count)
        for (i, k) in keep.enumerated() {
            for t in adj[k] ?? [] { if let j = index[t], j > i { edges.append((i, j)); degree[i] += 1; degree[j] += 1 } }
        }
        // Seed on a golden-angle spiral (deterministic, already well spread).
        var pos: [SIMD2<Float>] = []
        for i in 0..<keep.count {
            let r = 12 * sqrt(Float(i) + 0.5)
            let a = Float(i) * 2.39996
            pos.append(SIMD2(r * cos(a), r * sin(a)))
        }
        if let f = focus, let fi = index[f] { pos[fi] = .zero }
        let labels = keep.map { snap.notes[$0]?.name ?? $0 }
        return GraphData(ids: keep, labels: labels, edges: edges, degree: degree, positions: pos, isUnresolved: keep.map { _ in false })
    }

    /// Run `iterations` steps of a Fruchterman–Reingold-style simulation.
    public mutating func layout(iterations: Int = 300, pinned: Int? = nil) {
        let n = positions.count
        guard n > 1 else { return }
        let k: Float = 26            // ideal edge length
        let cell: Float = k * 3
        var temp: Float = Float(sqrt(Double(n))) * 6
        var disp = [SIMD2<Float>](repeating: .zero, count: n)
        for _ in 0..<iterations {
            for i in 0..<n { disp[i] = .zero }
            // grid
            var grid: [SIMD2<Int32>: [Int]] = [:]
            grid.reserveCapacity(n)
            for i in 0..<n { grid[SIMD2(Int32((positions[i].x / cell).rounded(.down)), Int32((positions[i].y / cell).rounded(.down))), default: []].append(i) }
            for (c, members) in grid {
                for dx in -1...1 { for dy in -1...1 {
                    guard let other = grid[SIMD2(c.x + Int32(dx), c.y + Int32(dy))] else { continue }
                    for i in members { for j in other where j != i {
                        var d = positions[i] - positions[j]
                        var dist = simd_length(d)
                        if dist < 0.01 { d = SIMD2(Float(i % 7) - 3, Float(j % 5) - 2); dist = 1 }
                        if dist < cell { disp[i] += d / dist * (k * k / dist) }
                    } }
                } }
            }
            for (a, b) in edges {
                let d = positions[a] - positions[b]
                let dist = max(simd_length(d), 0.01)
                let f = d / dist * (dist * dist / k) * 0.6
                disp[a] -= f; disp[b] += f
            }
            for i in 0..<n {
                if i == pinned { continue }
                disp[i] -= positions[i] * 0.012  // gentle gravity keeps islands on screen
                let l = simd_length(disp[i])
                if l > 0 { positions[i] += disp[i] / l * min(l, temp) }
            }
            temp = max(temp * 0.985, 0.4)
        }
    }

    public var bounds: (min: SIMD2<Float>, max: SIMD2<Float>) {
        guard var lo = positions.first else { return (.zero, .zero) }
        var hi = lo
        for p in positions { lo = simd_min(lo, p); hi = simd_max(hi, p) }
        return (lo, hi)
    }
}
