#if canImport(AppKit)
import AppKit
import XCTest
@testable import OnyxCore

final class FoldLayoutTests: XCTestCase {
    private func setup(_ text: String) -> (NSTextStorage, FoldLayoutManager, NSTextContainer) {
        let p = NSMutableParagraphStyle(); p.minimumLineHeight = 22; p.maximumLineHeight = 22
        let ts = NSTextStorage(string: text, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), .paragraphStyle: p])
        let lm = FoldLayoutManager(); ts.addLayoutManager(lm)
        let tc = NSTextContainer(size: NSSize(width: 300, height: 1e7)); lm.addTextContainer(tc)
        return (ts, lm, tc)
    }
    private func fragments(_ lm: NSLayoutManager, _ tc: NSTextContainer) -> [NSRect] {
        lm.ensureLayout(for: tc)
        var out: [NSRect] = [], g = 0
        while g < lm.numberOfGlyphs {
            var range = NSRange()
            out.append(lm.lineFragmentRect(forGlyphAt: g, effectiveRange: &range))
            g = NSMaxRange(range)
        }
        return out
    }
    func testHiddenParagraphsUseNoExtraLineFragmentsAndSourceIsUnchanged() {
        let text = "# Heading\n" + String(repeating: "body word ", count: 200) + "\n## Child\nchild body\n# Next\nx\n"
        let (ts, lm, tc) = setup(text)
        let all = MarkdownFolds.regions(in: text)
        let before = fragments(lm, tc).count
        let attrs = NSAttributedString(attributedString: ts)
        lm.setHiddenRanges([all[0].hidden])
        let after = fragments(lm, tc)
        XCTAssertEqual(after.count, 3)   // Heading, Next, x
        XCTAssertGreaterThan(before, 50)
        XCTAssertEqual(after[0].height, 22)
        XCTAssertEqual(after[1].minY, 22)
        XCTAssertEqual(ts.string, text)
        XCTAssertEqual(NSAttributedString(attributedString: ts), attrs) // even styling is untouched
        lm.setHiddenRanges([])
        XCTAssertEqual(fragments(lm, tc).count, before)
    }
    func testNestedFoldSurvivesOpeningItsParent() {
        let text = "# A\na\n## B\nb\n# C\nc"
        let (ts, lm, tc) = setup(text), r = MarkdownFolds.regions(in: text)
        lm.setHiddenRanges([r[0].hidden, r[1].hidden])
        XCTAssertEqual(fragments(lm, tc).count, 3)
        lm.setHiddenRanges([r[1].hidden])
        XCTAssertEqual(fragments(lm, tc).count, 5)
        XCTAssertEqual(ts.string, text)
    }
    func testEOFNoPhantomLines() {
        let text = "# A\nbody"
        let (ts, lm, tc) = setup(text); defer { _ = ts }
        lm.setHiddenRanges(MarkdownFolds.regions(in: text).map(\.hidden))
        XCTAssertEqual(fragments(lm, tc).count, 1)
    }
    func testCRLFFolds() {
        let text = "# A\r\nbody\r\n# B\r\nx"
        let (ts, lm, tc) = setup(text); defer { _ = ts }
        lm.setHiddenRanges([MarkdownFolds.regions(in: text)[0].hidden])
        XCTAssertEqual(fragments(lm, tc).count, 3)
    }
    func testStorageEditAndAttributeRestylingDontLoseHiddenGlyphs() {
        let text = "# A\nbody\n# B\nx"
        let (ts, lm, tc) = setup(text)
        lm.setHiddenRanges([MarkdownFolds.regions(in: text)[0].hidden])
        XCTAssertEqual(fragments(lm, tc).count, 3)
        ts.addAttribute(.foregroundColor, value: NSColor.red, range: NSRange(location: 0, length: ts.length))
        XCTAssertEqual(fragments(lm, tc).count, 3)
        ts.replaceCharacters(in: NSRange(location: 2, length: 1), with: "Changed")
        lm.setHiddenRanges([MarkdownFolds.regions(in: ts.string)[0].hidden])
        XCTAssertEqual(fragments(lm, tc).count, 3)
        XCTAssertEqual(ts.string, "# Changed\nbody\n# B\nx")
    }
}
#endif

final class FoldLayoutEditTests: XCTestCase {
    func testOnEditKeepsFoldThroughTypingAboveAndDeletingTheBoundary() {
        let text = "intro\n# A\nbody\n# B\nb\n"
        let ts = NSTextStorage(string: text, attributes: [.font: NSFont.systemFont(ofSize: 14)])
        let lm = FoldLayoutManager(); ts.addLayoutManager(lm)
        let tc = NSTextContainer(size: NSSize(width: 300, height: 1e7)); lm.addTextContainer(tc)
        var folded = MarkdownFolds.regions(in: text).filter { $0.line == 1 }
        lm.onEdit = { edit, delta in
            let new = MarkdownFolds.regions(in: ts.string)
            let a = FoldEdits.remap(folded, edit: edit, delta: delta, into: new)
            folded = new.filter { a.contains($0.anchor) }
            return folded.map(\.hidden)
        }
        lm.setHiddenRanges(folded.map(\.hidden))
        func lines() -> Int { lm.ensureLayout(for: tc); var n = 0, g = 0; while g < lm.numberOfGlyphs { var r = NSRange(); _ = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: &r); g = NSMaxRange(r); n += 1 }; return n }
        XCTAssertEqual(lines(), 4)
        ts.replaceCharacters(in: NSRange(location: 0, length: 0), with: "more\n")
        XCTAssertEqual(lines(), 5)
        XCTAssertEqual((ts.string as NSString).substring(with: lm.hiddenRanges[0]), "\nbody")
        let b = (ts.string as NSString).range(of: "# B")
        ts.replaceCharacters(in: NSRange(location: b.location, length: 2), with: "")
        XCTAssertEqual((ts.string as NSString).substring(with: lm.hiddenRanges[0]), "\nbody\nB\nb")
        XCTAssertEqual(lines(), 3)
    }
}
