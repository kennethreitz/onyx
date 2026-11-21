import XCTest
@testable import OnyxCore

final class RandomNoteTests: XCTestCase {
    func testEmptyVaultHasNoCandidate() {
        XCTAssertEqual(RandomNote.candidates(in: [], excluding: nil), [])
        XCTAssertEqual(RandomNote.candidates(in: [], excluding: "Home.md"), [])
        XCTAssertNil(RandomNote.pick(from: [], excluding: nil))
    }

    func testSkipsCurrentWhenOthersExist() {
        let paths = ["A.md", "B.md", "C.md"]
        XCTAssertEqual(RandomNote.candidates(in: paths, excluding: "B.md"), ["A.md", "C.md"])
        XCTAssertEqual(RandomNote.candidates(in: paths, excluding: nil), paths)
        XCTAssertEqual(RandomNote.candidates(in: paths, excluding: "Missing.md"), paths)
    }

    func testSoleNoteStaysEvenIfCurrent() {
        XCTAssertEqual(RandomNote.candidates(in: ["Only.md"], excluding: "Only.md"), ["Only.md"])
        XCTAssertEqual(RandomNote.pick(from: ["Only.md"], excluding: "Only.md"), "Only.md")
    }

    func testPickStaysInsideCandidates() {
        let paths = ["A.md", "B.md", "Folder/C.md"]
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<40 {
            let picked = RandomNote.pick(from: paths, excluding: "A.md", using: &rng)
            XCTAssertNotNil(picked)
            XCTAssertNotEqual(picked, "A.md")
            XCTAssertTrue(paths.contains(picked!))
        }
    }
}
