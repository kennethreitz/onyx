import XCTest
@testable import OnyxCore

final class NoteNamingTests: XCTestCase {
    func testIsUntitled() {
        XCTAssertTrue(NoteNaming.isUntitled("Untitled.md"))
        XCTAssertTrue(NoteNaming.isUntitled("Untitled 2.md"))
        XCTAssertTrue(NoteNaming.isUntitled("Projects/Untitled 12.md"))
        XCTAssertTrue(NoteNaming.isUntitled("untitled.md"))
        XCTAssertFalse(NoteNaming.isUntitled("Untitled Thoughts.md"))
        XCTAssertFalse(NoteNaming.isUntitled("Daily/2026-11-21.md"))
        XCTAssertFalse(NoteNaming.isUntitled("Home.md"))
    }

    func testFolderForNewNote() {
        let folders: Set<String> = ["Projects", "Daily", "Writing"]
        XCTAssertEqual(NoteNaming.folderForNewNote(selected: ["Projects"], folders: folders, selectedFolder: nil, currentPath: "Home.md"), "Projects")
        XCTAssertEqual(NoteNaming.folderForNewNote(selected: ["Home.md"], folders: folders, selectedFolder: nil, currentPath: "Home.md"), "")
        XCTAssertEqual(NoteNaming.folderForNewNote(selected: ["Projects/Foo.md"], folders: folders, selectedFolder: nil, currentPath: "Projects/Foo.md"), "Projects")
        XCTAssertEqual(NoteNaming.folderForNewNote(selected: [], folders: folders, selectedFolder: "Writing", currentPath: "Home.md"), "Writing")
        XCTAssertEqual(NoteNaming.folderForNewNote(selected: ["Projects", "Daily"], folders: folders, selectedFolder: nil, currentPath: "Home.md"), "")
        XCTAssertEqual(NoteNaming.folderForNewNote(selected: [], folders: folders, selectedFolder: nil, currentPath: nil), "")
        XCTAssertEqual(NoteNaming.folderForNewNote(selected: [], folders: folders, selectedFolder: nil, currentPath: "Writing/Essay.md"), "Writing")
    }

    func testTitleFromContent() {
        XCTAssertEqual(NoteNaming.title(fromContent: "# Saved Note Title\n\nBody.\n"), "Saved Note Title")
        XCTAssertEqual(NoteNaming.title(fromContent: "---\ntags: a\n---\n# From Frontmatter\n\nHi\n"), "From Frontmatter")
        XCTAssertEqual(NoteNaming.title(fromContent: "# Untitled\n\nJust a body.\n"), nil)
        XCTAssertEqual(NoteNaming.title(fromContent: "\n\nPlain first line\n\nMore\n"), "Plain first line")
        XCTAssertEqual(NoteNaming.title(fromContent: "## Only H2\n\nBody\n"), "Only H2")
        XCTAssertEqual(NoteNaming.title(fromContent: "# Path/Like: Title\n\n"), "Path-Like- Title")
        XCTAssertNil(NoteNaming.title(fromContent: "\n\n"))
        XCTAssertNil(NoteNaming.title(fromContent: "# Untitled 2\n"))
    }

    func testDestSkipsOccupiedAndAllowsSource() {
        let taken: Set<String> = ["Projects/Saved.md", "Projects/Saved 2.md"]
        XCTAssertEqual(NoteNaming.dest(folder: "Projects", title: "Saved", occupied: { taken.contains($0) }), "Projects/Saved 3.md")
        XCTAssertEqual(NoteNaming.dest(folder: "", title: "Home", occupied: { $0 == "Home.md" }), "Home 2.md")
        XCTAssertEqual(NoteNaming.dest(folder: "Projects", title: "New One", occupied: { $0 == "Untitled.md" }), "Projects/New One.md")
    }

    func testFileNameSanitizes() {
        XCTAssertEqual(NoteNaming.fileName(fromTitle: "  A / B: C  "), "A - B- C")
        XCTAssertEqual(NoteNaming.fileName(fromTitle: ".hidden"), "hidden")
    }

    func testNoteRecordTitleIsFirstH1() {
        let r = VaultSnapshot.makeRecord(rel: "Untitled.md", content: "# Real Title\n\nBody\n")
        XCTAssertEqual(r.title, "Real Title")
        XCTAssertEqual(r.name, "Untitled")
        let noH1 = VaultSnapshot.makeRecord(rel: "Plain.md", content: "Just words\n")
        XCTAssertEqual(noH1.title, "Plain")
    }
}
