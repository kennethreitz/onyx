import XCTest
import simd
@testable import OnyxCore

final class AtlasLayoutTests: XCTestCase {

    /// Linked notes in uneven top-level folders, plus a couple of nested ones,
    /// roughly like a real vault where a few giants sit next to small neighbors.
    func unevenVault() -> VaultSnapshot {
        var snap = VaultSnapshot(root: URL(fileURLWithPath: "/tmp/atlas-layout-test"))
        func add(folder: String, count: Int, hub: String, alsoLink: [String] = []) {
            for i in 0..<count {
                let name = i == 0 ? hub : "\(hub)-\(i)"
                let path = "\(folder)/\(name).md"
                var body = "# \(name)\n[[\(hub)]]\n"
                if i > 0 { body += "[[\(hub)-\(max(1, i - 1))]]\n" }
                for l in alsoLink { body += "[[\(l)]]\n" }
                snap.notes[path] = VaultSnapshot.makeRecord(rel: path, content: body)
            }
        }
        // Cross-links between the small neighbors so attraction has something to pull on.
        add(folder: "Knowledge", count: 220, hub: "KnowledgeHub")
        add(folder: "Writing", count: 140, hub: "WritingHub", alsoLink: ["LifeHub"])
        add(folder: "System 777", count: 80, hub: "SystemHub")
        add(folder: "Life", count: 30, hub: "LifeHub", alsoLink: ["ProjectsHub", "HomeHub"])
        add(folder: "Clippings", count: 18, hub: "ClippingsHub")
        add(folder: "Projects", count: 10, hub: "ProjectsHub", alsoLink: ["LifeHub"])
        add(folder: "Home", count: 4, hub: "HomeHub", alsoLink: ["LifeHub"])
        // A nested project, so Projects has a sub-circle.
        snap.notes["Projects/App/Spec.md"] = VaultSnapshot.makeRecord(
            rel: "Projects/App/Spec.md",
            content: "# Spec\n[[ProjectsHub]]\n"
        )
        snap.rebuildDerived()
        return snap
    }

    func atlas(_ snap: VaultSnapshot) -> Atlas {
        Atlas.build(GraphIndex.build(snap), grouping: .folders, include: { _ in true }, includeOrphans: false)
    }

    func assertSeparated(_ clusters: [AtlasCluster], gap: Double, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(clusters.isEmpty, "expected clusters", file: file, line: line)
        for i in clusters.indices {
            for j in clusters.indices where i < j {
                let dist = simd_length(clusters[i].center - clusters[j].center)
                let minD = clusters[i].radius + clusters[j].radius + gap
                XCTAssertGreaterThanOrEqual(
                    dist + 0.01, minD,
                    "\(clusters[i].label) (r=\(clusters[i].radius)) overlaps \(clusters[j].label) (r=\(clusters[j].radius)): dist=\(dist) min=\(minD)",
                    file: file, line: line
                )
            }
        }
    }

    func testTopClustersKeepMinimumGap() {
        let a = atlas(unevenVault())
        let tops = a.clusters.filter { $0.level == 0 }
        XCTAssertEqual(Set(tops.map(\.key)), ["Knowledge", "Writing", "System 777", "Life", "Clippings", "Projects", "Home"])
        assertSeparated(tops, gap: Atlas.clusterGap)
        // The smallest folders stay visible and off the giants.
        let home = tops.first { $0.key == "Home" }!
        let knowledge = tops.first { $0.key == "Knowledge" }!
        XCTAssertGreaterThanOrEqual(home.radius, Atlas.minClusterRadius)
        XCTAssertLessThanOrEqual(knowledge.radius, Atlas.maxClusterRadius)
        let clearance = simd_length(home.center - knowledge.center) - home.radius - knowledge.radius
        XCTAssertGreaterThanOrEqual(clearance + 0.01, Atlas.clusterGap)
    }

    func testSubClustersKeepMinimumGap() {
        let a = atlas(unevenVault())
        for (idx, top) in a.clusters.enumerated() where top.level == 0 {
            let subs = a.clusters.filter { $0.level == 1 && $0.parent == idx }
            assertSeparated(subs, gap: Atlas.subClusterGap)
            // Every sub stays inside its parent, with a little padding.
            for s in subs {
                let reach = simd_length(s.center - top.center) + s.radius
                XCTAssertLessThanOrEqual(reach, top.radius + 0.01)
            }
        }
    }

    func testLayoutIsDeterministic() {
        let snap = unevenVault()
        let a = atlas(snap)
        let b = atlas(snap)
        XCTAssertEqual(a.clusters.map(\.key), b.clusters.map(\.key))
        for (x, y) in zip(a.clusters, b.clusters) {
            XCTAssertEqual(x.center.x, y.center.x, accuracy: 1e-9)
            XCTAssertEqual(x.center.y, y.center.y, accuracy: 1e-9)
            XCTAssertEqual(x.radius, y.radius, accuracy: 1e-9)
        }
    }

    func testRadiusScaleCompressesGiants() {
        XCTAssertGreaterThanOrEqual(Atlas.radius(forCount: 1), Atlas.minClusterRadius)
        XCTAssertGreaterThanOrEqual(Atlas.radius(forCount: 4), Atlas.minClusterRadius)
        let huge = Atlas.radius(forCount: 1074)
        let small = Atlas.radius(forCount: 14)
        XCTAssertLessThanOrEqual(huge, Atlas.maxClusterRadius)
        XCTAssertGreaterThan(huge, small)
        // Uncompressed sunflower radius would be about 13√n + 42 ≈ 468 vs 91 (ratio ~5).
        XCTAssertLessThan(huge / small, 4.0)
    }

    func testSeparateResolvesOverlapsAndHonorsGap() {
        var centers = [
            SIMD2<Double>(0, 0),
            SIMD2<Double>(5, 0),
            SIMD2<Double>(0, 0)
        ]
        let radii = [40.0, 20.0, 12.0]
        let gap = 24.0
        Atlas.separate(&centers, radii: radii, gap: gap)
        for i in centers.indices {
            for j in centers.indices where i < j {
                let dist = simd_length(centers[i] - centers[j])
                XCTAssertGreaterThanOrEqual(dist + 0.01, radii[i] + radii[j] + gap)
            }
        }
    }

    func testPackLeavesRequestedGap() {
        let items: [(String, Double)] = [
            ("Knowledge", 260), ("Writing", 210), ("System 777", 160),
            ("Life", 80), ("Clippings", 70), ("Projects", 60), ("Home", 52)
        ]
        let packed = Atlas.pack(items, gap: Atlas.clusterGap)
        XCTAssertEqual(packed.map(\.0).sorted(), items.map(\.0).sorted())
        for i in packed.indices {
            for j in packed.indices where i < j {
                let dist = simd_length(packed[i].1 - packed[j].1)
                XCTAssertGreaterThanOrEqual(dist + 0.01, packed[i].2 + packed[j].2 + Atlas.clusterGap)
            }
        }
        // Same input, same output.
        let again = Atlas.pack(items, gap: Atlas.clusterGap)
        for (x, y) in zip(packed, again) {
            XCTAssertEqual(x.0, y.0)
            XCTAssertEqual(x.1.x, y.1.x, accuracy: 1e-9)
            XCTAssertEqual(x.1.y, y.1.y, accuracy: 1e-9)
        }
    }
}
