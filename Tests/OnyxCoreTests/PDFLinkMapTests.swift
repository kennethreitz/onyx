import XCTest
@testable import OnyxCore

final class PDFLinkMapTests: XCTestCase {
    /// Letter, the default NotePrinter margins, text column 486pt.
    let geo = PDFLinkMap.Geometry(paperWidth: 612, paperHeight: 792, top: 72, bottom: 76,
                                  left: 72, right: 54)
    var pageH: CGFloat { geo.printableHeight } // 644

    func testMapRectOnTheFirstPageIsFlippedIntoPDFSpace() {
        // contentWidth == printable width → scale 1. A 20×10 box at (10, 30) from the top-left.
        let r = PDFLinkMap.mapRect(CGRect(x: 10, y: 30, width: 20, height: 10),
                                   contentWidth: 486, geometry: geo, pageCount: 3)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].page, 1)
        XCTAssertEqual(r[0].rect.origin.x, 72 + 10)
        XCTAssertEqual(r[0].rect.size, CGSize(width: 20, height: 10))
        // PDF y is measured from the bottom: paper 792, top margin 72, 30pt down, 10pt tall.
        XCTAssertEqual(r[0].rect.origin.y, 792 - 72 - 30 - 10)
    }

    func testMapRectAndPointMoveToTheNextPageAtThePrintableHeight() {
        let start = PDFLinkMap.mapPoint(x: 0, y: pageH, contentWidth: 486, geometry: geo, pageCount: 3)
        XCTAssertEqual(start?.page, 2)
        XCTAssertEqual(start?.point.y, 792 - 72)

        let r = PDFLinkMap.mapRect(CGRect(x: 0, y: pageH, width: 40, height: 12),
                                   contentWidth: 486, geometry: geo, pageCount: 3)
        XCTAssertEqual(r.map(\.page), [2])
        XCTAssertEqual(r[0].rect.origin.y, 792 - 72 - 12)
    }

    func testMapRectSplitsABoxThatCrossesAPageBreak() {
        let y = pageH - 4
        let r = PDFLinkMap.mapRect(CGRect(x: 0, y: y, width: 30, height: 10),
                                   contentWidth: 486, geometry: geo, pageCount: 3)
        XCTAssertEqual(r.map(\.page), [1, 2])
        XCTAssertEqual(r[0].rect.height, 4)
        XCTAssertEqual(r[0].rect.origin.y, 792 - 72 - (pageH - 4) - 4)
        XCTAssertEqual(r[1].rect.height, 6)
        XCTAssertEqual(r[1].rect.origin.y, 792 - 72 - 6)
    }

    func testScaleMapsContentWidthOntoTheTextColumn() {
        // Content is twice as wide as the printable area; everything halves.
        let r = PDFLinkMap.mapRect(CGRect(x: 20, y: 40, width: 80, height: 20),
                                   contentWidth: 972, geometry: geo)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].rect.origin.x, 72 + 10)
        XCTAssertEqual(r[0].rect.size, CGSize(width: 40, height: 10))
        XCTAssertEqual(r[0].rect.origin.y, 792 - 72 - 20 - 10)
    }

    func testMapDropsPagesPastTheCount() {
        let p = PDFLinkMap.mapPoint(x: 0, y: pageH * 5, contentWidth: 486, geometry: geo, pageCount: 2)
        XCTAssertNil(p)
        XCTAssertTrue(PDFLinkMap.mapRect(CGRect(x: 0, y: pageH * 5, width: 10, height: 10),
                                         contentWidth: 486, geometry: geo, pageCount: 2).isEmpty)
    }

    func testTocRowRectPadsTheBaseline() {
        let r = PDFLinkMap.tocRowRect(x: 72, y: 600, width: 400, ascent: 11, descent: 4)
        XCTAssertEqual(r, CGRect(x: 72, y: 596, width: 400, height: 15))
    }

    func testNestOutlineBuildsATreeAndAcceptsANonZeroStartDepth() {
        let flat: [(String, Int, Int, CGFloat?)] = [
            ("Projects", 2, 0, 700),
            ("Alpha", 3, 1, 700),
            ("Beta", 5, 1, 700),
            ("Notes", 8, 0, 700),
        ]
        let tree = PDFLinkMap.nestOutline(flat)
        XCTAssertEqual(tree.map(\.title), ["Projects", "Notes"])
        XCTAssertEqual(tree[0].page, 2)
        XCTAssertEqual(tree[0].children.map(\.title), ["Alpha", "Beta"])
        XCTAssertEqual(tree[0].children[1].page, 5)
        XCTAssertTrue(tree[1].children.isEmpty)

        let heads = PDFLinkMap.nestOutline([
            ("Mid", 1, 2, 10),
            ("Deep", 1, 3, 20),
            ("Also", 2, 2, 30),
        ])
        XCTAssertEqual(heads.map(\.title), ["Mid", "Also"])
        XCTAssertEqual(heads[0].children.map(\.title), ["Deep"])
    }

    func testMatchHeadingIgnoresCaseAndALeadingHash() {
        let hs = [
            PDFLinkMap.HeadingBox(text: "Table of Contents", level: 2, box: .init(x: 0, y: 0, width: 10, height: 10)),
            PDFLinkMap.HeadingBox(text: "Intro", level: 1, box: .init(x: 0, y: 20, width: 10, height: 10)),
        ]
        XCTAssertEqual(PDFLinkMap.matchHeading("table of contents", in: hs), 0)
        XCTAssertEqual(PDFLinkMap.matchHeading("#Intro", in: hs), 1)
        XCTAssertNil(PDFLinkMap.matchHeading("Missing", in: hs))
    }

    func testAnchorSetParsesPrintAnchorsJSON() {
        let json: [String: Any] = [
            "contentWidth": 486,
            "headings": [
                ["text": "Intro", "level": 1, "x": 0, "y": 12, "width": 80, "height": 16],
            ],
            "links": [
                ["heading": "Intro", "target": "", "x": 0, "y": 200, "width": 40, "height": 12],
                ["heading": "Elsewhere", "target": "Other", "x": 0, "y": 220, "width": 40, "height": 12],
            ],
        ]
        let set = PDFLinkMap.AnchorSet(json: json)
        XCTAssertEqual(set?.contentWidth, 486)
        XCTAssertEqual(set?.headings.count, 1)
        XCTAssertEqual(set?.links.count, 2)

        let dests = PDFLinkMap.destinations(in: set!, geometry: geo, pageCount: 3, pageOffset: 2)
        XCTAssertEqual(dests["intro"]?.page, 3) // page 1 of the note + offset 2

        let jumps = PDFLinkMap.jumps(in: set!, geometry: geo, pageCount: 3, pageOffset: 2) { heading, target in
            if target.isEmpty { return dests[PDFLinkMap.normalize(heading)] }
            return nil
        }
        XCTAssertEqual(jumps.count, 1)
        XCTAssertEqual(jumps[0].page, 3)
        XCTAssertEqual(jumps[0].destPage, 3)
        XCTAssertTrue(PDFLinkMap.jumps(in: set!, geometry: geo, pageCount: 3) { _, _ in nil }.isEmpty)
    }

    func testGraftAttachesHeadingChildrenUnderAMatchingPage() {
        let toc = [
            PDFLinkMap.OutlineNode(title: "Projects", page: 2, y: 700, children: [
                PDFLinkMap.OutlineNode(title: "Alpha", page: 3, y: 700),
            ]),
        ]
        let heads = [PDFLinkMap.OutlineNode(title: "Intro", page: 3, y: 600)]
        let grafted = PDFLinkMap.graft(toc, children: [3: heads])
        XCTAssertEqual(grafted[0].children[0].children.map(\.title), ["Intro"])
    }
}
