import XCTest
import OnyxCore

final class FooterCountsTests: XCTestCase {
    func n(_ i: Int) -> String { i.formatted() }

    func testTooltipIncludesWordsCharactersAndBacklinks() {
        let c = FooterCounts(words: 370, characters: 2117, backlinks: 2)
        XCTAssertEqual(c.tooltip, "\(n(370)) words · \(n(2117)) characters · \(n(2)) backlinks")
    }

    func testTooltipOmitsZeroBacklinks() {
        let c = FooterCounts(words: 1, characters: 1, backlinks: 0)
        XCTAssertEqual(c.tooltip, "1 word · 1 character")
    }

    func testAutoLabelsPriorityAndCompactionWithBacklinks() {
        let c = FooterCounts(words: 370, characters: 2117, backlinks: 2)
        XCTAssertEqual(c.labels(), [
            "\(n(370)) words · \(n(2117)) characters · 2 backlinks",
            "\(n(370)) words · \(n(2117)) chars · 2 links",
            "\(n(370)) words · 2 backlinks",
            "\(n(370)) words · 2 links",
            "\(n(370))w · 2 links",
            "\(n(370)) words",
            "\(n(370))w",
        ])
    }

    func testAutoLabelsDropCharactersFirstWhenThereAreNoBacklinks() {
        let c = FooterCounts(words: 8, characters: 40, backlinks: 0)
        XCTAssertEqual(c.labels(), [
            "8 words · 40 characters",
            "8 words · 40 chars",
            "8 words",
            "8w",
        ])
    }

    func testEachAutoLabelIsShorterThanTheOneBefore() {
        let samples = [
            FooterCounts(words: 370, characters: 2117, backlinks: 2),
            FooterCounts(words: 1, characters: 1, backlinks: 1),
            FooterCounts(words: 8, characters: 40, backlinks: 0),
            FooterCounts(words: 1_000_000, characters: 9_999_999, backlinks: 12),
        ]
        for c in samples {
            let labels = c.labels()
            XCTAssertGreaterThan(labels.count, 1, "\(c)")
            for (a, b) in zip(labels, labels.dropFirst()) {
                XCTAssertLessThan(b.count, a.count, "\(b) should be shorter than \(a)")
            }
        }
    }

    func testSingularUnits() {
        let c = FooterCounts(words: 1, characters: 1, backlinks: 1)
        XCTAssertEqual(c.tooltip, "1 word · 1 character · 1 backlink")
        XCTAssertEqual(c.labels().first, "1 word · 1 character · 1 backlink")
        XCTAssertEqual(c.labels()[1], "1 word · 1 char · 1 link")
    }

    func testCycleWalksAutoThenEachMetric() {
        let c = FooterCounts(words: 370, characters: 2117, backlinks: 2)
        XCTAssertEqual(c.next(.auto), .words)
        XCTAssertEqual(c.next(.words), .characters)
        XCTAssertEqual(c.next(.characters), .backlinks)
        XCTAssertEqual(c.next(.backlinks), .auto)
        XCTAssertEqual(c.labels(cycle: .words), ["\(n(370)) words", "\(n(370))w"])
        XCTAssertEqual(c.labels(cycle: .characters), ["\(n(2117)) characters", "\(n(2117)) chars", "\(n(2117))c"])
        XCTAssertEqual(c.labels(cycle: .backlinks), ["2 backlinks", "2 links"])
    }

    func testCycleSkipsBacklinksWhenThereAreNone() {
        let c = FooterCounts(words: 10, characters: 50, backlinks: 0)
        XCTAssertEqual(c.next(.characters), .auto)
        XCTAssertEqual(c.labels(cycle: .backlinks), c.labels())
    }

    func testAttachmentLabelsAndCycle() {
        let none = FooterCounts(words: 0, characters: 0, backlinks: 0, kind: .attachment(label: "Image"))
        XCTAssertEqual(none.tooltip, "Image")
        XCTAssertEqual(none.labels(), ["Image"])
        XCTAssertEqual(none.next(.auto), .auto)

        let linked = FooterCounts(words: 0, characters: 0, backlinks: 2, kind: .attachment(label: "PDF"))
        XCTAssertEqual(linked.tooltip, "PDF · 2 backlinks")
        XCTAssertEqual(linked.labels(), ["PDF · 2 backlinks", "PDF · 2 links", "PDF"])
        XCTAssertEqual(linked.next(.auto), .backlinks)
        XCTAssertEqual(linked.next(.backlinks), .auto)
        XCTAssertEqual(linked.labels(cycle: .backlinks), ["2 backlinks", "2 links"])
        for (a, b) in zip(linked.labels(), linked.labels().dropFirst()) {
            XCTAssertLessThan(b.count, a.count)
        }
    }
}
