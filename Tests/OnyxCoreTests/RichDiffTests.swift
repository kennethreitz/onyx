import XCTest
@testable import OnyxCore

final class RichDiffTests: XCTestCase {
    typealias K = NoteDiff.BlockKind

    func kinds(_ text: String) -> [K] {
        NoteDiff.documentBlocks(text).map(\.kind)
    }

    func texts(_ text: String) -> [String] {
        NoteDiff.documentBlocks(text).map(\.text)
    }

    func testTokenizeKeepsMarkupAroundWords() {
        XCTAssertEqual(NoteDiff.tokenize("**foo**"), ["*", "*", "foo", "*", "*"])
        XCTAssertEqual(NoteDiff.tokenize("Hello world"), ["Hello", " ", "world"])
        XCTAssertEqual(NoteDiff.tokenize(""), [])
        XCTAssertEqual(NoteDiff.tokenize("a\n\nb"), ["a", "\n\n", "b"])
    }

    func testSplitParagraphsAndHeadings() {
        let t = "# Title\n\nHello world.\n\n## Section\nMore.\n"
        XCTAssertEqual(kinds(t), [.heading(1), .blank, .paragraph, .blank, .heading(2), .paragraph])
        XCTAssertEqual(texts(t).joined(), t)
    }

    func testSplitReconstructsSource() {
        let samples = [
            "",
            "just a line",
            "just a line\n",
            "# A\n\n- one\n- two\n\n```swift\nlet x = 1\n```\n",
            "---\ntags: [a]\n---\n\nBody.\n",
        ]
        for s in samples {
            XCTAssertEqual(texts(s).joined(), s, "round-trip failed for \(s.prefix(30))")
        }
    }

    func testSplitFencesMermaidTablesTasks() {
        let code = "```swift\nlet x = 1\n```\n"
        XCTAssertEqual(kinds(code), [.code("swift")])
        let mer = "```mermaid\ngraph TD\n  A-->B\n```\n"
        XCTAssertEqual(kinds(mer), [.mermaid])
        let table = "| a | b |\n| --- | --- |\n| 1 | 2 |\n"
        XCTAssertEqual(kinds(table), [.table])
        let tasks = "- [ ] write\n- [x] done\n- not a task\n"
        XCTAssertEqual(kinds(tasks), [.task, .task, .listItem])
        let fm = "---\nfoo: bar\n---\n\nHi.\n"
        XCTAssertEqual(kinds(fm), [.frontmatter, .blank, .paragraph])
        let q = "> one\n> two\n"
        XCTAssertEqual(kinds(q), [.blockquote])
    }

    func testIdenticalIsAllEqual() {
        let t = "# Hello\n\nWorld.\n"
        let blocks = NoteDiff.rich(old: t, new: t)
        XCTAssertFalse(NoteDiff.richHasChanges(blocks))
        XCTAssertEqual(blocks.map(\.op), [.equal, .equal, .equal])
    }

    func testInsertAndDeleteParagraphs() {
        let inserted = NoteDiff.rich(old: "keep\n", new: "keep\n\nnew para\n")
        XCTAssertTrue(inserted.contains { $0.op == .insert && $0.text.contains("new para") })
        let deleted = NoteDiff.rich(old: "keep\n\nold para\n", new: "keep\n")
        XCTAssertTrue(deleted.contains { $0.op == .delete && $0.text.contains("old para") })
    }

    func testWordChangeInParagraph() {
        let blocks = NoteDiff.rich(old: "The quick fox.\n", new: "The slow fox.\n")
        let chg = blocks.filter { $0.op == .change }
        XCTAssertEqual(chg.count, 1)
        let spans = chg[0].spans
        XCTAssertTrue(spans.contains { $0.op == .delete && $0.text == "quick" })
        XCTAssertTrue(spans.contains { $0.op == .insert && $0.text == "slow" })
        XCTAssertTrue(spans.contains { $0.op == .same && $0.text == "fox" })
        XCTAssertEqual(chg[0].kind, .paragraph)
    }

    func testHeadingChangeIsInline() {
        let blocks = NoteDiff.rich(old: "## Hello world\n", new: "## Hello there\n")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].op, .change)
        XCTAssertEqual(blocks[0].kind, .heading(2))
        XCTAssertTrue(blocks[0].spans.contains { $0.op == .delete && $0.text == "world" })
        XCTAssertTrue(blocks[0].spans.contains { $0.op == .insert && $0.text == "there" })
        XCTAssertFalse(blocks[0].spans.contains { $0.text.hasPrefix("#") })
    }

    func testHeadingLevelChangeStaysAChange() {
        let blocks = NoteDiff.rich(old: "## Orbit\n", new: "### Orbit\n")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].op, .change)
        XCTAssertEqual(blocks[0].kind, .heading(3))
        XCTAssertTrue(blocks[0].spans.allSatisfy { $0.op == .same })
    }

    func testCodeAndMermaidAndTableAreAtomic() {
        let oldC = "```\nold\n```\n"
        let newC = "```\nnew\n```\n"
        let code = NoteDiff.rich(old: oldC, new: newC)
        XCTAssertEqual(code.map(\.op), [.delete, .insert])
        XCTAssertEqual(code[0].kind, .code(""))
        XCTAssertEqual(code[1].kind, .code(""))

        let mer = NoteDiff.rich(
            old: "```mermaid\ngraph TD\n  A-->B\n```\n",
            new: "```mermaid\ngraph TD\n  A-->C\n```\n"
        )
        XCTAssertEqual(mer.map(\.op), [.delete, .insert])
        XCTAssertTrue(mer.allSatisfy { $0.kind == .mermaid })

        let table = NoteDiff.rich(
            old: "| a |\n| --- |\n| 1 |\n",
            new: "| a |\n| --- |\n| 2 |\n"
        )
        XCTAssertEqual(table.map(\.op), [.delete, .insert])
        XCTAssertTrue(table.allSatisfy { $0.kind == .table })
    }

    func testTaskCheckboxFlipIsInline() {
        let blocks = NoteDiff.rich(old: "- [ ] write tests\n", new: "- [x] write tests\n")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].op, .change)
        XCTAssertEqual(blocks[0].kind, .task)
        let joinedDel = blocks[0].spans.filter { $0.op == .delete }.map(\.text).joined()
        let joinedIns = blocks[0].spans.filter { $0.op == .insert }.map(\.text).joined()
        XCTAssertTrue(joinedDel.contains(" "), "unchecked box should be deleted: \(blocks[0].spans)")
        XCTAssertTrue(joinedIns.contains("x") || joinedIns.contains("X"), "checked box should be inserted: \(blocks[0].spans)")
    }

    func testPayloadShape() {
        let blocks = NoteDiff.rich(old: "The quick fox.\n", new: "The slow fox.\n")
        let payload = NoteDiff.richPayload(blocks)
        XCTAssertEqual(payload.count, 1)
        XCTAssertEqual(payload[0]["op"] as? String, "change")
        XCTAssertEqual(payload[0]["kind"] as? String, "paragraph")
        let spans = payload[0]["spans"] as? [[String: String]]
        XCTAssertNotNil(spans)
        XCTAssertTrue(spans!.contains { $0["op"] == "delete" && $0["text"] == "quick" })
        XCTAssertTrue(spans!.contains { $0["op"] == "insert" && $0["text"] == "slow" })
    }

    func testUnrelatedBlocksDoNotCoalesce() {
        let blocks = NoteDiff.rich(old: "# Alpha\n", new: "A totally different paragraph.\n")
        XCTAssertEqual(Set(blocks.map(\.op)), Set([.delete, .insert]))
    }
}
