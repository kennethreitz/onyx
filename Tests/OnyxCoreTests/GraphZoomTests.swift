import XCTest
import OnyxCore

final class GraphZoomTests: XCTestCase {
    func testClampKeepsValuesInsideTheFitBasedFloorAndExistingMax() {
        XCTAssertEqual(GraphZoom.max, 12)
        XCTAssertEqual(GraphZoom.minimum(fit: 2), 1)
        XCTAssertEqual(GraphZoom.clamp(1.5, fit: 2), 1.5)
        XCTAssertEqual(GraphZoom.clamp(0.01, fit: 2), 1)          // floor is half of fit
        XCTAssertEqual(GraphZoom.clamp(40, fit: 2), 12)           // existing max
        XCTAssertEqual(GraphZoom.clamp(0.02, fit: 0.2), 0.1)
    }

    func testClampUsesASafeFallbackWhenFitIsUnknown() {
        XCTAssertEqual(GraphZoom.minimum(fit: 0), 0.5)
        XCTAssertEqual(GraphZoom.clamp(0.01, fit: 0), 0.5)
        XCTAssertEqual(GraphZoom.clamp(0.01, fit: .nan), 0.5)
        XCTAssertEqual(GraphZoom.clamp(.infinity, fit: 1), 12)
        XCTAssertEqual(GraphZoom.clamp(-4, fit: 1), 0.5)
    }
}
