import XCTest
import OnyxCore

final class SectionExportTests: XCTestCase {
    private func node(_ name: String, path: String, folder: Bool, children: [FileNode] = [], folderNote: String? = nil) -> FileNode {
        FileNode(name: name, path: path, isFolder: folder, children: folder ? children : nil, folderNote: folderNote)
    }

    private var tree: FileNode {
        // Alpha.md, Beta.md, Projects/ (folder note + Apollo, Nested/Inside)
        let nested = node("Nested", path: "Projects/Nested", folder: true, children: [
            node("Inside.md", path: "Projects/Nested/Inside.md", folder: false)
        ], folderNote: "Projects/Nested/Nested.md")
        let projects = node("Projects", path: "Projects", folder: true, children: [
            nested,
            node("Apollo.md", path: "Projects/Apollo.md", folder: false),
            node("sketch.png", path: "Projects/sketch.png", folder: false),
        ], folderNote: "Projects/Projects.md")
        return node("", path: "", folder: true, children: [
            projects,
            node("Alpha.md", path: "Alpha.md", folder: false),
            node("Beta.md", path: "Beta.md", folder: false),
            node("Gamma.md", path: "Gamma.md", folder: false),
        ])
    }
    private func kids(_ n: FileNode) -> [FileNode] { n.children ?? [] }

    func testFolderExpandsInOrderWithFolderNoteFirst() {
        let items = SectionExport.outline(selected: ["Projects"], root: tree, children: kids)
        XCTAssertEqual(items.map { "\($0.kind == .part ? "P" : "N"):\($0.path):\($0.depth)" }, [
            "P:Projects:0",
            "N:Projects/Projects.md:1",
            "P:Projects/Nested:1",
            "N:Projects/Nested/Nested.md:2",
            "N:Projects/Nested/Inside.md:2",
            "N:Projects/Apollo.md:1",
        ])
        XCTAssertEqual(SectionExport.defaultFilename(items), "Projects.pdf")
    }

    func testMixedSelectionFollowsSidebarOrderAndDropsChildrenOfSelectedFolders() {
        let items = SectionExport.outline(selected: ["Gamma.md", "Projects/Apollo.md", "Projects", "Alpha.md"], root: tree, children: kids)
        // Projects is a root, so Apollo (inside it) is dropped; Alpha then Gamma stay, in tree order.
        XCTAssertEqual(items.filter { $0.depth == 0 }.map(\.path), ["Projects", "Alpha.md", "Gamma.md"])
        XCTAssertEqual(SectionExport.defaultFilename(items), "Selection.pdf")
    }

    func testNotesOnly() {
        let items = SectionExport.outline(selected: ["Beta.md", "Alpha.md"], root: tree, children: kids)
        XCTAssertEqual(items.map(\.path), ["Alpha.md", "Beta.md"])
        XCTAssertTrue(items.allSatisfy { $0.kind == .note && $0.depth == 0 })
    }

    func testSkipsNonNotes() {
        let items = SectionExport.outline(selected: ["Projects/sketch.png", "Alpha.md"], root: tree, children: kids)
        XCTAssertEqual(items.map(\.path), ["Alpha.md"])
    }

    func testNoteTitle() {
        XCTAssertEqual(SectionExport.noteTitle("Projects/Apollo.md"), "Apollo")
        XCTAssertEqual(SectionExport.noteTitle("Projects"), "Projects")
    }
}
