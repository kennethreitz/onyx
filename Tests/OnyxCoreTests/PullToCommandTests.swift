import XCTest
@testable import OnyxCore

final class PullToCommandTests: XCTestCase {
    func testOpensOnlyAfterThreshold() {
        XCTAssertFalse(PullToCommand.shouldOpen(offsetY: 0))
        XCTAssertFalse(PullToCommand.shouldOpen(offsetY: -10))
        XCTAssertFalse(PullToCommand.shouldOpen(offsetY: -PullToCommand.threshold))
        XCTAssertTrue(PullToCommand.shouldOpen(offsetY: -PullToCommand.threshold - 0.01))
        XCTAssertTrue(PullToCommand.shouldOpen(offsetY: -200))
    }

    func testHintFadesInWhilePulling() {
        XCTAssertEqual(PullToCommand.hintOpacity(offsetY: 0), 0)
        XCTAssertEqual(PullToCommand.hintOpacity(offsetY: 20), 0)
        XCTAssertEqual(PullToCommand.hintOpacity(offsetY: -PullToCommand.threshold / 2), 0.5, accuracy: 0.0001)
        XCTAssertEqual(PullToCommand.hintOpacity(offsetY: -PullToCommand.threshold), 1, accuracy: 0.0001)
        XCTAssertEqual(PullToCommand.hintOpacity(offsetY: -200), 1)
    }

    func testHintCopyIsForQuickOpen() {
        XCTAssertEqual(PullToCommand.pullingHint, "Open a note")
        XCTAssertEqual(PullToCommand.releaseHint, "Release to open a note")
    }
}
