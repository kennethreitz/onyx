import XCTest
import OnyxCore

final class FolderTreeClickTests: XCTestCase {
    func testChevronAlwaysTogglesAndDoesNotOpenTheIndex() {
        XCTAssertEqual(
            FolderTreeClick.action(.chevron, hasFolderNote: true),
            FolderTreeClick(toggleExpansion: true, openFolderNote: false)
        )
        XCTAssertEqual(
            FolderTreeClick.action(.chevron, hasFolderNote: false),
            FolderTreeClick(toggleExpansion: true, openFolderNote: false)
        )
    }

    func testRowTogglesAndOpensTheIndexWhenThereIsOne() {
        XCTAssertEqual(
            FolderTreeClick.action(.row, hasFolderNote: true),
            FolderTreeClick(toggleExpansion: true, openFolderNote: true)
        )
    }

    func testRowOnAPlainFolderJustToggles() {
        XCTAssertEqual(
            FolderTreeClick.action(.row, hasFolderNote: false),
            FolderTreeClick(toggleExpansion: true, openFolderNote: false)
        )
    }
}


final class TreeRevealTests: XCTestCase {
    func testAncestorsOfANestedNote() {
        XCTAssertEqual(
            TreeReveal.ancestors(of: "Life/Family/Projects/Projects.md"),
            ["Life/Family/Projects", "Life/Family", "Life"]
        )
    }

    func testAncestorsOfARootNoteAreEmpty() {
        XCTAssertEqual(TreeReveal.ancestors(of: "Home.md"), [])
    }

    func testOpeningTheCurrentNoteDoesNotReExpandAncestors() {
        XCTAssertFalse(TreeReveal.shouldExpandAncestors(alreadyOpen: true, reveal: true))
        XCTAssertTrue(TreeReveal.shouldExpandAncestors(alreadyOpen: false, reveal: true))
    }

    func testAFolderRowClickCanSkipRevealSoACollapseSticks() {
        XCTAssertFalse(TreeReveal.shouldExpandAncestors(alreadyOpen: false, reveal: false))
        XCTAssertFalse(TreeReveal.shouldExpandAncestors(alreadyOpen: true, reveal: false))
    }
}
