import XCTest
@testable import OnyxCore

final class OptionRevealItemTests: XCTestCase {
    func testRecognizesTitles() {
        XCTAssertTrue(OptionRevealItem.isTarget("Open in Obsidian"))
        XCTAssertFalse(OptionRevealItem.isTarget("Open in Default App"))
        XCTAssertFalse(OptionRevealItem.isTarget("Reveal in Finder"))
        XCTAssertTrue(OptionRevealItem.isSibling("Reveal in Finder"))
        XCTAssertTrue(OptionRevealItem.isSibling("Reveal 3 Items in Finder"))
        XCTAssertTrue(OptionRevealItem.isSibling("Open in Default App"))
        XCTAssertFalse(OptionRevealItem.isSibling("Reveal in Sidebar"))
        XCTAssertFalse(OptionRevealItem.isSibling("Open"))
    }

    func testAlternateOfFinderOrDefaultApp() {
        XCTAssertEqual(OptionRevealItem.treatment(previousTitle: "Reveal in Finder"), .alternate)
        XCTAssertEqual(OptionRevealItem.treatment(previousTitle: "Reveal 2 Items in Finder"), .alternate)
        XCTAssertEqual(OptionRevealItem.treatment(previousTitle: "Open in Default App"), .alternate)
        XCTAssertEqual(OptionRevealItem.treatment(previousTitle: "Copy Wikilink"), .optionOnly)
        XCTAssertEqual(OptionRevealItem.treatment(previousTitle: nil), .optionOnly)
    }
}
