import XCTest
@testable import OnyxCore

final class PaneRatiosTests: XCTestCase {
    func testEqualAndNormalized() {
        XCTAssertEqual(PaneRatios.equal(0), [])
        XCTAssertEqual(PaneRatios.equal(1), [1])
        XCTAssertEqual(PaneRatios.equal(2), [0.5, 0.5])
        XCTAssertEqual(PaneRatios.normalized([], count: 0), [])
        XCTAssertEqual(PaneRatios.normalized([], count: 2), [0.5, 0.5])
        XCTAssertEqual(PaneRatios.normalized([1], count: 2), [0.5, 0.5])
        XCTAssertEqual(PaneRatios.normalized([0, 1], count: 2), [0.5, 0.5])
        XCTAssertEqual(PaneRatios.normalized([2, 6], count: 2), [0.25, 0.75])
        XCTAssertEqual(PaneRatios.normalized([0.3, 0.7], count: 1), [1])
    }

    func testSplittingTakesHalfOfTheSourcePane() {
        XCTAssertEqual(PaneRatios.splitting([], at: 0), [0.5, 0.5])
        XCTAssertEqual(PaneRatios.splitting([1], at: 0), [0.5, 0.5])
        assertClose(PaneRatios.splitting([0.7, 0.3], at: 0), [0.35, 0.35, 0.3])
        assertClose(PaneRatios.splitting([0.7, 0.3], at: 1), [0.7, 0.15, 0.15])
    }

    func testRemovingGivesShareToNeighbor() {
        assertClose(PaneRatios.removing([0.35, 0.35, 0.3], at: 1), [0.7, 0.3])
        assertClose(PaneRatios.removing([0.35, 0.35, 0.3], at: 0), [0.7, 0.3])
        XCTAssertEqual(PaneRatios.removing([0.5, 0.5], at: 0), [1])
        XCTAssertEqual(PaneRatios.removing([1], at: 0), [])
    }

    func testSizesHonorMinAndRemainder() {
        let even = PaneRatios.sizes([0.5, 0.5], total: 1000.8)
        XCTAssertEqual(even[0] + even[1] + PaneRatios.thickness, 1000.8, accuracy: 0.01)
        XCTAssertEqual(even[0], 500, accuracy: 0.01)

        let tight = PaneRatios.sizes([0.2, 0.8], total: 1000.8)
        XCTAssertEqual(tight[0], 240, accuracy: 0.01)
        XCTAssertEqual(tight[1], 760, accuracy: 0.01)

        let narrow = PaneRatios.sizes([0.2, 0.8], total: 400.8)
        XCTAssertEqual(narrow[0], 200, accuracy: 0.01)
        XCTAssertEqual(narrow[1], 200, accuracy: 0.01)
    }

    func testDraggingMovesThePairAndClamps() {
        let moved = PaneRatios.dragging([0.5, 0.5], divider: 0, delta: -100, total: 1000.8)
        let sizes = PaneRatios.sizes(moved, total: 1000.8)
        XCTAssertEqual(sizes[0], 400, accuracy: 0.5)
        XCTAssertEqual(sizes[1], 600, accuracy: 0.5)

        let clamped = PaneRatios.dragging([0.5, 0.5], divider: 0, delta: -1000, total: 1000.8)
        XCTAssertEqual(PaneRatios.sizes(clamped, total: 1000.8)[0], 240, accuracy: 0.5)

        let three = PaneRatios.dragging([0.4, 0.3, 0.3], divider: 1, delta: 50, total: 1000)
        let s = PaneRatios.sizes(three, total: 1000)
        XCTAssertEqual(s[0], PaneRatios.sizes([0.4, 0.3, 0.3], total: 1000)[0], accuracy: 0.5)
        XCTAssertEqual(s[1] + s[2], PaneRatios.sizes([0.4, 0.3, 0.3], total: 1000)[1] + PaneRatios.sizes([0.4, 0.3, 0.3], total: 1000)[2], accuracy: 0.5)
        XCTAssertGreaterThan(s[1], PaneRatios.sizes([0.4, 0.3, 0.3], total: 1000)[1])
    }

    private func assertClose(_ a: [Double], _ b: [Double], file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(a.count, b.count, file: file, line: line)
        for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: 0.0001, file: file, line: line) }
    }
}
