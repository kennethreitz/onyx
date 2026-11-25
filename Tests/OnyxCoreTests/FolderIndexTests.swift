import XCTest
@testable import OnyxCore

final class FolderIndexTests: XCTestCase {
    func snapshot(_ files: [String: String], folders: Set<String> = []) -> VaultSnapshot {
        var snap = VaultSnapshot(root: URL(fileURLWithPath: "/tmp/none"))
        for (p, c) in files { snap.notes[p] = VaultSnapshot.makeRecord(rel: p, content: c) }
        snap.folders = folders
        snap.rebuildDerived()
        return snap
    }

    func testNotePathIsFolderSlashFolderMd() {
        XCTAssertNil(FolderIndex.notePath(forFolder: ""))
        XCTAssertNil(FolderIndex.notePath(forFolder: "/"))
        XCTAssertEqual(FolderIndex.notePath(forFolder: "Projects"), "Projects/Projects.md")
        XCTAssertEqual(
            FolderIndex.notePath(forFolder: "Life/Family/Projects"),
            "Life/Family/Projects/Projects.md"
        )
    }

    func testHasIndexDetectsTheFolderNote() {
        let notes: Set = ["Projects/Projects.md", "Projects/Alpha.md", "Life/Life.md"]
        XCTAssertTrue(FolderIndex.hasIndex(folder: "Projects", notes: notes))
        XCTAssertTrue(FolderIndex.hasIndex(folder: "Life", notes: notes))
        XCTAssertFalse(FolderIndex.hasIndex(folder: "Projects/Alpha", notes: notes))
        XCTAssertFalse(FolderIndex.hasIndex(folder: "Inbox", notes: notes))
        XCTAssertFalse(FolderIndex.hasIndex(folder: "", notes: notes))
        // index.md is not the convention
        XCTAssertFalse(FolderIndex.hasIndex(folder: "Inbox", notes: ["Inbox/index.md"]))
    }

    func testInferredClassDefaultsToIndex() {
        XCTAssertEqual(FolderIndex.inferredClass([]), "Index")
        XCTAssertEqual(FolderIndex.inferredClass([nil, nil]), "Index")
        XCTAssertEqual(FolderIndex.inferredClass(["Index", "Index", "DailyNote"]), "Index")
        XCTAssertEqual(FolderIndex.inferredClass(["Folder"]), "Folder")
    }

    func testDraftIsAModestIndex() {
        let body = FolderIndex.draft(
            folder: "Life/Projects",
            childNotes: ["Life/Projects/Beta.md", "Life/Projects/Alpha.md", "Life/Projects/Projects.md"],
            childFolders: ["Life/Projects/Nested"],
            parentIndex: "Life/Life.md"
        )
        XCTAssertEqual(body, """
        ---
        class: Index
        ---
        # Projects

        An index of this folder.

        - [[Nested]]
        - [[Alpha]]
        - [[Beta]]

        partOf:: [[Life]]

        """)
    }

    func testDraftEmptyFolderHasNoListOrPartOf() {
        let body = FolderIndex.draft(folder: "Inbox", childNotes: [], childFolders: [])
        XCTAssertEqual(body, """
        ---
        class: Index
        ---
        # Inbox

        An index of this folder.

        """)
    }

    func testWikilinkUsesAPathWhenTheNameIsNotUnique() {
        let counts = ["Alpha": 2, "Nested": 1]
        XCTAssertEqual(FolderIndex.wikilink(path: "Life/Projects/Alpha.md", nameCounts: counts), "[[Life/Projects/Alpha]]")
        XCTAssertEqual(FolderIndex.wikilink(path: "Life/Projects/Nested", nameCounts: counts), "[[Nested]]")
    }

    func testDraftFromSnapshotUsesExistingClassAndChildren() {
        let snap = snapshot([
            "Life/Life.md": "---\nclass: Index\n---\n# Life\n",
            "Life/Projects/Alpha.md": "# Alpha\n",
            "Life/Projects/Other/Alpha.md": "# Alpha\n",
            "Life/Projects/Nested/Nested.md": "---\nclass: Index\n---\n# Nested\n",
        ], folders: ["Life", "Life/Projects", "Life/Projects/Other", "Life/Projects/Nested"])
        XCTAssertFalse(FolderIndex.hasIndex(folder: "Life/Projects", notes: Set(snap.notes.keys)))
        let body = FolderIndex.draft(forFolder: "Life/Projects", in: snap)
        XCTAssertTrue(body.hasPrefix("---\nclass: Index\n---\n# Projects\n"))
        XCTAssertTrue(body.contains("An index of this folder."))
        // Subfolders first, then notes; the colliding Alpha uses a path link.
        XCTAssertTrue(body.contains("- [[Nested]]"))
        XCTAssertTrue(body.contains("- [[Other]]"))
        XCTAssertTrue(body.contains("- [[Life/Projects/Alpha]]"))
        XCTAssertFalse(body.contains("- [[Life/Projects/Other/Alpha]]"))
        XCTAssertTrue(body.contains("partOf:: [[Life]]"))
        // The index itself is not listed as a child, even if we asked after creating it.
        XCTAssertFalse(body.contains("[[Projects]]\n"))
    }
}
