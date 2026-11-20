import XCTest
@testable import OnyxCore

final class FindTextTests: XCTestCase {
    func testLiteralCaseInsensitiveNonOverlapping() {
        let s = "Stone stone STONE aaaa (x)"
        XCTAssertEqual(FindText.ranges(of: "stone", in: s, caseSensitive: false).count, 3)
        XCTAssertEqual(FindText.ranges(of: "stone", in: s, caseSensitive: true).map(\.location), [6])
        XCTAssertEqual(FindText.ranges(of: "aa", in: s, caseSensitive: false).count, 2)   // non-overlapping
        XCTAssertEqual(FindText.ranges(of: "(x)", in: s, caseSensitive: false).count, 1)  // literal, not regex
        XCTAssertEqual(FindText.ranges(of: "", in: s, caseSensitive: false).count, 0)
    }
    func testUTF16Ranges() {
        let s = "🜍 Mercury 🜍 mercury"
        let rs = FindText.ranges(of: "mercury", in: s, caseSensitive: false)
        XCTAssertEqual(rs.count, 2)
        XCTAssertEqual((s as NSString).substring(with: rs[1]), "mercury")
    }
}
