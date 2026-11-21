import XCTest
@testable import OnyxCore

final class FolderCreateTests: XCTestCase {
    func testFirstNameIsBare() {
        XCTAssertEqual(FolderCreate.uniqueName(existing: []), "Untitled Folder")
        XCTAssertEqual(FolderCreate.uniqueName(existing: ["Inbox"]), "Untitled Folder")
    }

    func testDedupStartsAtTwo() {
        XCTAssertEqual(FolderCreate.uniqueName(existing: ["Untitled Folder"]), "Untitled Folder 2")
        XCTAssertEqual(FolderCreate.uniqueName(existing: ["Untitled Folder", "Untitled Folder 2"]), "Untitled Folder 3")
        XCTAssertEqual(FolderCreate.uniqueName(existing: ["Untitled Folder", "Untitled Folder 3"]), "Untitled Folder 2")
    }

    func testCustomBase() {
        XCTAssertEqual(FolderCreate.uniqueName(base: "Projects", existing: ["Projects", "Projects 2"]), "Projects 3")
    }

    func testSanitize() {
        XCTAssertEqual(FolderCreate.sanitized("  A/B:C  "), "A-B-C")
        XCTAssertEqual(FolderCreate.sanitized(".."), "")
        XCTAssertEqual(FolderCreate.sanitized("."), "")
        XCTAssertEqual(FolderCreate.sanitized("   "), "")
    }

    func testEmptyBaseFallsBack() {
        XCTAssertEqual(FolderCreate.uniqueName(base: "  ", existing: []), "Untitled Folder")
        XCTAssertEqual(FolderCreate.uniqueName(base: "/", existing: ["Untitled Folder"]), "Untitled Folder 2")
    }

    func testPath() {
        XCTAssertEqual(FolderCreate.path(name: "Untitled Folder", in: ""), "Untitled Folder")
        XCTAssertEqual(FolderCreate.path(name: "Untitled Folder", in: "Writing"), "Writing/Untitled Folder")
        XCTAssertEqual(FolderCreate.path(name: "Untitled Folder 2", in: "Writing/Essays"), "Writing/Essays/Untitled Folder 2")
    }
}
