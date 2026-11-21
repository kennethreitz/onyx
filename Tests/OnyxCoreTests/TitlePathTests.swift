import XCTest
import OnyxCore

final class TitlePathTests: XCTestCase {
    func testFolderNoteMergesTheLastFolderAndTheNote() {
        let c = TitlePath.crumbs(folder: "Life/Family/Projects", name: "Projects")
        XCTAssertEqual(c.map(\.name), ["Life", "Family", "Projects"])
        XCTAssertEqual(c[0], TitleCrumb(name: "Life", kind: .folder(path: "Life")))
        XCTAssertEqual(c[1], TitleCrumb(name: "Family", kind: .folder(path: "Life/Family")))
        XCTAssertEqual(c[2], TitleCrumb(name: "Projects", kind: .note))
    }

    func testRootLevelFolderNoteIsASingleCrumb() {
        let c = TitlePath.crumbs(folder: "Projects", name: "Projects")
        XCTAssertEqual(c, [TitleCrumb(name: "Projects", kind: .note)])
    }

    func testOrdinaryNoteKeepsTheFolderAndTheName() {
        let c = TitlePath.crumbs(folder: "Life/Family/Projects", name: "Apollo")
        XCTAssertEqual(c.map(\.name), ["Life", "Family", "Projects", "Apollo"])
        XCTAssertEqual(c[2], TitleCrumb(name: "Projects", kind: .folder(path: "Life/Family/Projects")))
        XCTAssertEqual(c[3], TitleCrumb(name: "Apollo", kind: .note))
    }

    func testRootNoteIsJustTheName() {
        let c = TitlePath.crumbs(folder: "", name: "Home")
        XCTAssertEqual(c, [TitleCrumb(name: "Home", kind: .note)])
    }
}
