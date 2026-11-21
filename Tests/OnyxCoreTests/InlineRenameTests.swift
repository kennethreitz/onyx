import XCTest
import OnyxCore

final class InlineRenameTests: XCTestCase {
    func testFieldValueStripsMarkdownExtension() {
        XCTAssertEqual(InlineRename.fieldValue(path: "Life/Family/Projects.md"), "Projects")
        XCTAssertEqual(InlineRename.fieldValue(path: "Projects.md"), "Projects")
        XCTAssertEqual(InlineRename.fieldValue(path: "Life/Family"), "Family")
        XCTAssertEqual(InlineRename.fieldValue(path: "img/photo.png"), "photo.png")
    }

    func testSelectionSelectsStemWithoutExtension() {
        XCTAssertEqual(InlineRename.selectionLength(for: "Projects", wholeName: true), 8)
        XCTAssertEqual(InlineRename.selectionLength(for: "Untitled Folder", wholeName: true), 15)
        XCTAssertEqual(InlineRename.selectionLength(for: "photo.png", wholeName: false), 5)
        XCTAssertEqual(InlineRename.selectionLength(for: "archive.tar.gz", wholeName: false), 11)
        XCTAssertEqual(InlineRename.selectionLength(for: "Makefile", wholeName: false), 8)
        XCTAssertEqual(InlineRename.selectionLength(for: "version 1.2", wholeName: true), 11)
    }

    func testEmptyOrUnchangedCancels() {
        let taken: (String) -> Bool = { _ in false }
        XCTAssertEqual(InlineRename.evaluate(path: "Notes/A.md", typed: "", occupied: taken), .cancel)
        XCTAssertEqual(InlineRename.evaluate(path: "Notes/A.md", typed: "   ", occupied: taken), .cancel)
        XCTAssertEqual(InlineRename.evaluate(path: "Notes/A.md", typed: "A", occupied: taken), .cancel)
        XCTAssertEqual(InlineRename.evaluate(path: "Notes/A.md", typed: "  A  ", occupied: taken), .cancel)
        XCTAssertEqual(InlineRename.evaluate(path: "Inbox", typed: "Inbox", occupied: taken), .cancel)
    }

    func testCommitAppendsMarkdownAndKeepsFolder() {
        let taken: (String) -> Bool = { _ in false }
        XCTAssertEqual(
            InlineRename.evaluate(path: "Life/Note.md", typed: "Hermes", occupied: taken),
            .commit(dest: "Life/Hermes.md", fromName: "Note", toName: "Hermes")
        )
        XCTAssertEqual(
            InlineRename.evaluate(path: "Life/Note.md", typed: "Hermes.md", occupied: taken),
            .commit(dest: "Life/Hermes.md", fromName: "Note", toName: "Hermes")
        )
        XCTAssertEqual(
            InlineRename.evaluate(path: "Life/Inbox", typed: "Archive", occupied: taken),
            .commit(dest: "Life/Archive", fromName: "Inbox", toName: "Archive")
        )
        XCTAssertEqual(
            InlineRename.evaluate(path: "photo.png", typed: "cover.png", occupied: taken),
            .commit(dest: "cover.png", fromName: "photo.png", toName: "cover.png")
        )
    }

    func testInvalidCharactersKeepTheEdit() {
        let taken: (String) -> Bool = { _ in false }
        XCTAssertEqual(
            InlineRename.evaluate(path: "A.md", typed: "A/B", occupied: taken),
            .invalid("Name can’t contain “/” or “:”.")
        )
        XCTAssertEqual(
            InlineRename.evaluate(path: "A.md", typed: "A:B", occupied: taken),
            .invalid("Name can’t contain “/” or “:”.")
        )
        XCTAssertEqual(
            InlineRename.evaluate(path: "A.md", typed: ".", occupied: taken),
            .invalid("That name isn’t allowed.")
        )
        XCTAssertEqual(
            InlineRename.evaluate(path: "A.md", typed: "..", occupied: taken),
            .invalid("That name isn’t allowed.")
        )
        XCTAssertEqual(
            InlineRename.evaluate(path: "A.md", typed: ".hidden", occupied: taken),
            .invalid("Name can’t start with a period.")
        )
    }

    func testCollisionUnlessCaseOnlyRename() {
        let taken: (String) -> Bool = { $0.lowercased() == "life/venus.md" || $0.lowercased() == "life/note.md" }
        XCTAssertEqual(
            InlineRename.evaluate(path: "Life/Note.md", typed: "Venus", occupied: taken),
            .collision("“Venus” already exists there.")
        )
        // Same path, different case: not a collision (case-only rename on a case-insensitive disk).
        XCTAssertEqual(
            InlineRename.evaluate(path: "Life/Note.md", typed: "note", occupied: taken),
            .commit(dest: "Life/note.md", fromName: "Note", toName: "note")
        )
    }
}
