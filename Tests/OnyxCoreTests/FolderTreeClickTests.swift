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


final class TreePointerSessionTests: XCTestCase {
    func testPlainClickFiresOnceOnMouseDownNotOnMouseUp() {
        var s = TreePointerSession()
        XCTAssertEqual(s.mouseDown(command: false, canDrag: true), .clickNow)
        XCTAssertEqual(s.mouseUp(), .none)
    }

    func testPlainClickWithoutDragSupportStillFiresOnce() {
        var s = TreePointerSession()
        XCTAssertEqual(s.mouseDown(command: false, canDrag: false), .clickNow)
        XCTAssertEqual(s.mouseUp(), .none)
    }

    func testCommandClickIsDeferredUntilMouseUp() {
        var s = TreePointerSession()
        XCTAssertEqual(s.mouseDown(command: true, canDrag: true), .deferClick)
        XCTAssertEqual(s.mouseUp(), .clickNow)
    }

    func testCommandClickWithoutDragSupportFiresOnMouseDown() {
        var s = TreePointerSession()
        XCTAssertEqual(s.mouseDown(command: false, canDrag: false), .clickNow)
        // command + no drag support: treat as a normal click
        var t = TreePointerSession()
        XCTAssertEqual(t.mouseDown(command: true, canDrag: false), .clickNow)
        XCTAssertEqual(t.mouseUp(), .none)
    }

    func testPlainDragStartsAfterTheThresholdAndDoesNotClickOnMouseUp() {
        var s = TreePointerSession()
        XCTAssertEqual(s.mouseDown(command: false, canDrag: true), .clickNow)
        XCTAssertEqual(s.mouseDragged(distanceSquared: 15), .none)
        XCTAssertEqual(s.mouseDragged(distanceSquared: 16), .startDrag)
        XCTAssertEqual(s.mouseDragged(distanceSquared: 100), .none)
        XCTAssertEqual(s.mouseUp(), .none)
    }

    func testCommandDragDoesNotFireAClick() {
        var s = TreePointerSession()
        XCTAssertEqual(s.mouseDown(command: true, canDrag: true), .deferClick)
        XCTAssertEqual(s.mouseDragged(distanceSquared: 16), .startDrag)
        XCTAssertEqual(s.mouseUp(), .none)
    }

    func testASecondClickIsIndependent() {
        var s = TreePointerSession()
        XCTAssertEqual(s.mouseDown(command: false, canDrag: true), .clickNow)
        XCTAssertEqual(s.mouseUp(), .none)
        XCTAssertEqual(s.mouseDown(command: false, canDrag: true), .clickNow)
        XCTAssertEqual(s.mouseUp(), .none)
    }
}
