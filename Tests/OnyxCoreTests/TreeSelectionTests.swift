import XCTest
@testable import OnyxCore

final class TreeSelectionTests: XCTestCase {
    let rows = ["A.md", "B", "B/b1.md", "B/b2.md", "C.md", "D.md"]

    func testClickToggleExtend() {
        var s = TreeSelection()
        s.click("A.md"); XCTAssertEqual(s.selected, ["A.md"]); XCTAssertEqual(s.anchor, "A.md")
        s.extend(to: "B/b2.md", visible: rows); XCTAssertEqual(s.selected, ["A.md", "B", "B/b1.md", "B/b2.md"])
        s.extend(to: "B", visible: rows); XCTAssertEqual(s.selected, ["A.md", "B"])        // re-spans from the same anchor
        s.toggle("D.md"); XCTAssertEqual(s.selected, ["A.md", "B", "D.md"]); XCTAssertEqual(s.anchor, "D.md")
        s.toggle("A.md"); XCTAssertEqual(s.selected, ["B", "D.md"])
        // ⌘-click moves the anchor even when it deselects (Finder), so ⇧ spans from A
        s.extend(to: "C.md", visible: rows); XCTAssertEqual(s.selected, ["A.md", "B", "B/b1.md", "B/b2.md", "C.md"])
        s.toggle("D.md"); s.extend(to: "C.md", visible: rows); XCTAssertEqual(s.selected, ["C.md", "D.md"])  // upward
        XCTAssertTrue(s.isMulti)
        s.clear(); XCTAssertEqual(s.count, 0); XCTAssertNil(s.anchor)
    }
    func testExtendWithoutAnchorIsAClick() {
        var s = TreeSelection()
        s.extend(to: "C.md", visible: rows); XCTAssertEqual(s.selected, ["C.md"]); XCTAssertEqual(s.anchor, "C.md")
        s.extend(to: "gone.md", visible: rows); XCTAssertEqual(s.selected, ["gone.md"])
    }
    func testRootsAndPrune() {
        XCTAssertEqual(TreeSelection.roots(["B/b1.md", "B", "A.md", "Bx.md"]), ["A.md", "B", "Bx.md"])
        var s = TreeSelection(); s.click("A.md"); s.toggle("C.md")
        s.prune { $0 != "C.md" }; XCTAssertEqual(s.selected, ["A.md"]); XCTAssertNil(s.anchor)
    }
    func testDescribe() {
        XCTAssertEqual(TreeSelection.describe(["N/Mercury.md"]), "Mercury")
        XCTAssertEqual(TreeSelection.describe(["Mercury.md", "Venus.md"]), "Mercury and Venus")
        XCTAssertEqual(TreeSelection.describe(["a.md", "b.md", "Folder"]), "3 items: a, b, Folder")
        XCTAssertEqual(TreeSelection.describe(["a.md", "b.md", "c.md", "d.md"]), "4 items: a, b, c, …")
    }
    func testVisiblePaths() {
        let tree = FileNode(name: "", path: "", isFolder: true, children: [
            FileNode(name: "A.md", path: "A.md", isFolder: false),
            FileNode(name: "B", path: "B", isFolder: true, children: [FileNode(name: "b1.md", path: "B/b1.md", isFolder: false)]),
            FileNode(name: "C.md", path: "C.md", isFolder: false)])
        XCTAssertEqual(tree.visiblePaths(expanded: []), ["A.md", "B", "C.md"])
        XCTAssertEqual(tree.visiblePaths(expanded: ["B"]), ["A.md", "B", "B/b1.md", "C.md"])
    }
}
