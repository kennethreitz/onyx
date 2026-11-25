import XCTest
@testable import OnyxCore

final class TableLayoutTests: XCTestCase {

    func testCompactCells() {
        for v in ["2026-11-09", "11/9/26", "4.2", "1,234", "45%", "$12.50", "(3.1)", "−7", "OK", "v1.0"] {
            XCTAssertTrue(TableLayout.isCompact(v), v)
        }
        for v in ["2026-11-09 notes", "A long title", "Python 3 docs", "two words"] {
            XCTAssertFalse(TableLayout.isCompact(v), v)
        }
        XCTAssertTrue(TableLayout.isCompact("  "))
        XCTAssertTrue(TableLayout.isCompact(""))
    }

    func testFittingThreeColumnTable() {
        let rows = [
            ["Document", "Date", "Notes"],
            ["[[A reasonably long note title]]", "2026-11-09", "A long description that should wrap at words, not letters."],
            ["[[Another long title here]]", "2026-11-10", "More prose in the third column, still wrapping naturally."],
        ]
        let cols = TableLayout.columns(rows, available: 41)
        XCTAssertEqual(cols.count, 3)
        XCTAssertFalse(cols[0].nowrap)
        XCTAssertTrue(cols[1].nowrap)
        XCTAssertFalse(cols[2].nowrap)
        XCTAssertGreaterThanOrEqual(cols[0].width, TableLayout.minimumEm)
        XCTAssertGreaterThanOrEqual(cols[2].width, TableLayout.minimumEm)
        // A date is short: nowrap width is well under the wrapping floor.
        XCTAssertLessThan(cols[1].width, TableLayout.minimumEm)
        XCTAssertEqual(cols.map(\.width).reduce(0, +), 41, accuracy: 0.001)
        // Extra space goes to the longer wrapping columns, not the date.
        XCTAssertGreaterThan(cols[2].width, cols[1].width)
    }

    func testOverflowKeepsMinimumAndScrolls() {
        let rows = [
            ["One", "Two", "Three"],
            ["alpha beta gamma delta", "epsilon zeta eta theta", "iota kappa lambda mu"],
        ]
        let cols = TableLayout.columns(rows, available: 18)
        XCTAssertEqual(cols.count, 3)
        XCTAssertTrue(cols.allSatisfy { !$0.nowrap && $0.width >= TableLayout.minimumEm })
        XCTAssertEqual(cols.map(\.width).reduce(0, +), 24, accuracy: 0.001)
        XCTAssertGreaterThan(cols.map(\.width).reduce(0, +), 18)
    }

    func testNumericAndShortColumnsNowrap() {
        let rows = [
            ["Item", "Count", "Status"],
            ["Blue widget", "12", "OK"],
            ["Green gadget", "1,204", "YES"],
        ]
        let cols = TableLayout.columns(rows, available: 40)
        XCTAssertFalse(cols[0].nowrap)
        XCTAssertTrue(cols[1].nowrap)
        XCTAssertTrue(cols[2].nowrap)
        // Leftover measure goes to the wrapping name column; compact ones stay tight.
        XCTAssertEqual(cols[0].width + cols[1].width + cols[2].width, 40, accuracy: 0.001)
        XCTAssertGreaterThan(cols[0].width, cols[1].width)
    }

    func testTwoColumnShortLinksAndLongProseFitsAndWraps() {
        // A reader table of short wikilinks plus a description column of
        // full sentences should stay in a 41em measure and wrap the prose,
        // not bleed or scroll as if the description were one long line.
        let rows = [
            ["Note", "Description"],
            ["[[Home]]", "A long sentence about this note that should wrap within the reading measure instead of staying on one line and scrolling."],
            ["[[Daily]]", "Another full sentence of description prose that also wraps at word boundaries."],
        ]
        XCTAssertTrue(TableLayout.fits(rows, available: 41))
        XCTAssertLessThan(TableLayout.minWidth(rows), 41)
        let cols = TableLayout.columns(rows, available: 41)
        XCTAssertEqual(cols.count, 2)
        XCTAssertTrue(cols[0].nowrap)
        XCTAssertFalse(cols[1].nowrap)
        XCTAssertEqual(cols.map(\.width).reduce(0, +), 41, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(cols[1].width, TableLayout.minimumEm)
        XCTAssertGreaterThan(cols[1].width, cols[0].width)
    }

    func testEmptyInput() {
        XCTAssertEqual(TableLayout.columns([], available: 40), [])
        XCTAssertEqual(TableLayout.columns([[]], available: 40), [])
        XCTAssertTrue(TableLayout.fits([], available: 41))
        XCTAssertEqual(TableLayout.minWidth([]), 0)
    }
}
