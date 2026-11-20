import XCTest
@testable import OnyxCore

final class TreeSortTests: XCTestCase {
    func snapshot() -> VaultSnapshot {
        var snap = VaultSnapshot(root: URL(fileURLWithPath: "/tmp/none"))
        let d = { (s: Double) in Date(timeIntervalSince1970: s) }
        let files: [(String, Double, Double)] = [("Note 10.md", 30, 1), ("Note 2.md", 10, 3), ("alpha.md", 20, 2), ("Zed/inner.md", 40, 0.5), ("Box/b.md", 5, 4)]
        for (p, m, c) in files { snap.notes[p] = VaultSnapshot.makeRecord(rel: p, content: "x", mtime: d(m), ctime: d(c)) }
        snap.folders = ["Zed", "Box"]
        snap.rebuildDerived()
        return snap
    }
    func names(_ ns: [FileNode]) -> [String] { ns.map { $0.isNote ? $0.displayName : $0.name + "/" } }

    func testOrders() {
        let snap = snapshot(), dates = TreeDates(snap), kids = snap.tree.children ?? []
        XCTAssertEqual(names(dates.ordered(kids, by: .standard)), ["Box/", "Zed/", "alpha", "Note 2", "Note 10"])   // natural, numeric-aware
        XCTAssertEqual(names(dates.ordered(kids, by: TreeSort(key: .name, ascending: false))), ["Zed/", "Box/", "Note 10", "Note 2", "alpha"])
        XCTAssertEqual(names(dates.ordered(kids, by: TreeSort(key: .modified))), ["Zed/", "Box/", "Note 10", "alpha", "Note 2"])   // newest first; folder = newest inside
        XCTAssertEqual(names(dates.ordered(kids, by: TreeSort(key: .created, ascending: true, foldersFirst: false))), ["Zed/", "Note 10", "alpha", "Note 2", "Box/"])
        XCTAssertEqual(names(snap.tree.children ?? []), names(dates.ordered(kids, by: .standard)))   // default needs no re-sort
    }
    func testVisibleRowsFollowDisplayedOrder() {
        let snap = snapshot(), dates = TreeDates(snap)
        let order = TreeOrder(base: TreeSort(key: .modified), overrides: [:])
        let rows = snap.tree.visiblePaths(expanded: ["Zed"]) { dates.ordered($0.children ?? [], by: order.sort(for: $0.path)) }
        XCTAssertEqual(rows, ["Zed", "Zed/inner.md", "Box", "Note 10.md", "alpha.md", "Note 2.md"])
        var sel = TreeSelection(); sel.click("Zed/inner.md"); sel.extend(to: "alpha.md", visible: rows)
        XCTAssertEqual(sel.selected, ["Zed/inner.md", "Box", "Note 10.md", "alpha.md"])
    }
    func testCodableOverrides() throws {
        let o = TreeOrder(base: TreeSort(key: .created), overrides: ["Box": TreeSort(key: .name, ascending: false, foldersFirst: false)])
        let back = try JSONDecoder().decode(TreeOrder.self, from: JSONEncoder().encode(o))
        XCTAssertEqual(back, o); XCTAssertEqual(back.sort(for: "Box").ascending, false); XCTAssertEqual(back.sort(for: "Zed"), o.base)
    }
}
