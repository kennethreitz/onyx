import XCTest
import OnyxCore

final class TreeMoveTests: XCTestCase {
    func testDestinationUsesFolderOrParentOfFile() {
        XCTAssertEqual(TreeMove.destination(droppingOn: "Life/Family", targetIsFolder: true), "Life/Family")
        XCTAssertEqual(TreeMove.destination(droppingOn: "Life/Family/Note.md", targetIsFolder: false), "Life/Family")
        XCTAssertEqual(TreeMove.destination(droppingOn: "Note.md", targetIsFolder: false), "")
        XCTAssertEqual(TreeMove.destination(droppingOn: "", targetIsFolder: true), "")
    }

    func testAlreadyInFolderIsANoOp() {
        XCTAssertEqual(
            TreeMove.verdict(sources: ["Life/Note.md"], toFolder: "Life", occupied: { _ in false }),
            .none
        )
        XCTAssertEqual(
            TreeMove.verdict(sources: ["Note.md"], toFolder: "", occupied: { _ in false }),
            .none
        )
    }

    func testMoveIntoAnotherFolder() {
        XCTAssertEqual(
            TreeMove.verdict(sources: ["Life/Note.md"], toFolder: "Archive", occupied: { _ in false }),
            .move(["Life/Note.md"])
        )
        XCTAssertEqual(
            TreeMove.verdict(sources: ["Note.md"], toFolder: "Life", occupied: { _ in false }),
            .move(["Note.md"])
        )
        XCTAssertEqual(TreeMove.destPath(source: "Life/Note.md", toFolder: "Archive"), "Archive/Note.md")
        XCTAssertEqual(TreeMove.destPath(source: "Note.md", toFolder: ""), "Note.md")
    }

    func testRefusesFolderIntoSelfOrDescendant() {
        let refuse = TreeMove.Verdict.refuse("You can’t move a folder into itself.")
        XCTAssertEqual(TreeMove.verdict(sources: ["Life"], toFolder: "Life", occupied: { _ in false }), refuse)
        XCTAssertEqual(TreeMove.verdict(sources: ["Life"], toFolder: "Life/Family", occupied: { _ in false }), refuse)
        XCTAssertEqual(TreeMove.verdict(sources: ["Life/Family"], toFolder: "Life/Family/Kids", occupied: { _ in false }), refuse)
        // A note with a similar prefix is not the folder itself.
        XCTAssertEqual(
            TreeMove.verdict(sources: ["Life.md"], toFolder: "Life", occupied: { _ in false }),
            .move(["Life.md"])
        )
    }

    func testCollision() {
        XCTAssertEqual(
            TreeMove.verdict(sources: ["A/Note.md"], toFolder: "B", occupied: { $0 == "B/Note.md" }),
            .collision("“Note” already exists there.")
        )
        XCTAssertEqual(
            TreeMove.verdict(sources: ["Life/Inbox"], toFolder: "", occupied: { $0 == "Inbox" }),
            .collision("“Inbox” already exists there.")
        )
    }

    func testMultiSelectUsesRootsAndSkipsItemsAlreadyThere() {
        let sources = ["Life/A.md", "Life/Family", "Life/Family/B.md", "Inbox/C.md"]
        XCTAssertEqual(
            TreeMove.verdict(sources: sources, toFolder: "Archive", occupied: { _ in false }),
            .move(["Inbox/C.md", "Life/A.md", "Life/Family"])
        )
        XCTAssertEqual(
            TreeMove.verdict(sources: ["Life/A.md", "Archive/D.md"], toFolder: "Archive", occupied: { _ in false }),
            .move(["Life/A.md"])
        )
    }
}
