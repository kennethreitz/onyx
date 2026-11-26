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

    func testCopyOnyxURLIsAlternateOfCopyFilePath() {
        let rule = OptionAlternate.rule(for: "Copy Onyx URL")
        XCTAssertNotNil(rule)
        XCTAssertTrue(rule!.isTarget("Copy Onyx URL"))
        XCTAssertFalse(rule!.isTarget("Copy File Path"))
        XCTAssertTrue(rule!.isSibling("Copy File Path"))
        XCTAssertTrue(rule!.isSibling("Copy Wikilink"))
        XCTAssertFalse(rule!.isSibling("Copy"))
        XCTAssertEqual(rule!.treatment(previousTitle: "Copy File Path"), .alternate)
        XCTAssertEqual(rule!.treatment(previousTitle: "Copy Wikilink"), .alternate)
        XCTAssertEqual(rule!.treatment(previousTitle: "Reveal in Finder"), .optionOnly)
        XCTAssertEqual(rule!.treatment(previousTitle: nil), .optionOnly)
        // The Obsidian rule is unchanged, and does not claim this title.
        XCTAssertFalse(OptionRevealItem.isTarget("Copy Onyx URL"))
    }
}
