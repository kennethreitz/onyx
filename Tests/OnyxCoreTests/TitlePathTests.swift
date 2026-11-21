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

    func testAncestryReplacesFolders() {
        let c = TitlePath.crumbs(folder: "Health/Meds", name: "Sertraline", ancestry: ["Health/Medication.md", "Health/SSRI.md"], otherParents: ["Antidepressants.md"])
        XCTAssertEqual(c.map(\.name), ["Medication", "SSRI", "Sertraline"])
        XCTAssertEqual(c[0].kind, .ancestor(path: "Health/Medication.md", others: []))
        XCTAssertEqual(c[1].kind, .ancestor(path: "Health/SSRI.md", others: ["Antidepressants.md"]))
        XCTAssertEqual(c[2].kind, .note)
        XCTAssertEqual(TitlePath.crumbs(folder: "A", name: "B", ancestry: []).map(\.name), ["A", "B"])
    }
}
