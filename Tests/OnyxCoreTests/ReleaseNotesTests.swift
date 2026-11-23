import XCTest
@testable import OnyxCore

private let notesTag = "v0.1.8"
private let notesBlob = "https://github.com/kennethreitz/onyx/blob/v0.1.8"
private let notesPage = "https://github.com/kennethreitz/onyx/releases/tag/v0.1.8"

final class ReleaseNotesTests: XCTestCase {

    func testAbsolutizeRelativeAndAbsolute() {
        XCTAssertEqual(ReleaseNotes.absolutize("docs/obsidian-settings.md", tag: notesTag),
                       "\(notesBlob)/docs/obsidian-settings.md")
        XCTAssertEqual(ReleaseNotes.absolutize("docs/attachments.md#opening-attachments", tag: notesTag),
                       "\(notesBlob)/docs/attachments.md#opening-attachments")
        XCTAssertEqual(ReleaseNotes.absolutize("/docs/DEVELOP.md", tag: notesTag),
                       "\(notesBlob)/docs/DEVELOP.md")
        XCTAssertEqual(ReleaseNotes.absolutize("./docs/folding.md", tag: notesTag),
                       "\(notesBlob)/docs/folding.md")
        XCTAssertEqual(ReleaseNotes.absolutize("docs/../README.md", tag: notesTag),
                       "\(notesBlob)/README.md")
        XCTAssertEqual(ReleaseNotes.absolutize("#Updating", tag: notesTag),
                       "\(notesPage)#Updating")
        XCTAssertEqual(ReleaseNotes.absolutize("https://example.com/a", tag: notesTag),
                       "https://example.com/a")
        XCTAssertEqual(ReleaseNotes.absolutize("http://example.com/a?x=1", tag: notesTag),
                       "http://example.com/a?x=1")
        XCTAssertEqual(ReleaseNotes.absolutize("mailto:hi@example.com", tag: notesTag),
                       "mailto:hi@example.com")
        XCTAssertEqual(ReleaseNotes.absolutize("//cdn.example.com/x", tag: notesTag),
                       "https://cdn.example.com/x")
        XCTAssertEqual(ReleaseNotes.absolutize("docs/obsidian-settings.md", tag: "0.1.8"),
                       "\(notesBlob)/docs/obsidian-settings.md")
        XCTAssertEqual(ReleaseNotes.absolutize("a b.md", tag: notesTag),
                       "\(notesBlob)/a%20b.md")
        XCTAssertEqual(ReleaseNotes.absolutize("https://github.com/kennethreitz/onyx/blob/v0.1.7/docs/x.md", tag: notesTag),
                       "https://github.com/kennethreitz/onyx/blob/v0.1.7/docs/x.md")
    }

    func testRewriteInlineLinksAndTitles() {
        let src = """
        See [docs](docs/obsidian-settings.md) and [here](docs/attachments.md#opening-attachments) \
        and [abs](https://example.com/a) and [root](/docs/DEVELOP.md) and [frag](#Updating) \
        and [titled](docs/folding.md "Folding") and [angled](<docs/sync.md>).
        """
        let out = ReleaseNotes.rewriteLinks(src, tag: notesTag)
        XCTAssertTrue(out.contains("[docs](\(notesBlob)/docs/obsidian-settings.md)"))
        XCTAssertTrue(out.contains("[here](\(notesBlob)/docs/attachments.md#opening-attachments)"))
        XCTAssertTrue(out.contains("[abs](https://example.com/a)"))
        XCTAssertTrue(out.contains("[root](\(notesBlob)/docs/DEVELOP.md)"))
        XCTAssertTrue(out.contains("[frag](\(notesPage)#Updating)"))
        XCTAssertTrue(out.contains("[titled](\(notesBlob)/docs/folding.md \"Folding\")"))
        XCTAssertTrue(out.contains("[angled](<\(notesBlob)/docs/sync.md>)"))
        XCTAssertFalse(out.contains("(docs/obsidian-settings.md)"))
    }

    func testRewriteLeavesCodeAndFencesAlone() {
        let src = """
        A [ok](docs/y.md) and `[no](docs/x.md)` and more.

        ```
        [fence](docs/x.md)
        ```

        ~~~info
        [tilde](docs/x.md)
        ~~~

        Done [also](docs/z.md).
        """
        let out = ReleaseNotes.rewriteLinks(src, tag: notesTag)
        XCTAssertTrue(out.contains("[ok](\(notesBlob)/docs/y.md)"))
        XCTAssertTrue(out.contains("[also](\(notesBlob)/docs/z.md)"))
        XCTAssertTrue(out.contains("`[no](docs/x.md)`"))
        XCTAssertTrue(out.contains("[fence](docs/x.md)"))
        XCTAssertTrue(out.contains("[tilde](docs/x.md)"))
        XCTAssertFalse(out.contains("blob/v0.1.8/docs/x.md"))
    }

    func testRewriteReferenceDefinition() {
        let src = "[docs][d]\n\n[d]: docs/obsidian-settings.md\n"
        let out = ReleaseNotes.rewriteLinks(src, tag: notesTag)
        XCTAssertTrue(out.contains("[d]: \(notesBlob)/docs/obsidian-settings.md"))
    }

    func testParseHeadingsListsParagraphsAndNesting() {
        let md = """
        ### Added
        - Parent item with a link.
          - **Files & Links** (`app.json`): details.
          - Nested two.
        - Second parent.

        ### Updating

        Download the zip, unzip it, and replace `Onyx.app`.

        ---

        1. First step
        2. Second step
        """
        let blocks = ReleaseNotes.blocks(md)
        XCTAssertEqual(blocks, [
            .heading(level: 3, text: "Added"),
            .listItem(depth: 0, ordered: false, marker: "-", text: "Parent item with a link."),
            .listItem(depth: 1, ordered: false, marker: "-", text: "**Files & Links** (`app.json`): details."),
            .listItem(depth: 1, ordered: false, marker: "-", text: "Nested two."),
            .listItem(depth: 0, ordered: false, marker: "-", text: "Second parent."),
            .heading(level: 3, text: "Updating"),
            .paragraph("Download the zip, unzip it, and replace `Onyx.app`."),
            .rule,
            .listItem(depth: 0, ordered: true, marker: "1", text: "First step"),
            .listItem(depth: 0, ordered: true, marker: "2", text: "Second step"),
        ])
    }

    func testListItemContinuationAndBlankLines() {
        let md = """
        - A long item
          that continues.

        - Next item
        """
        let blocks = ReleaseNotes.blocks(md)
        XCTAssertEqual(blocks.count, 2)
        guard case .listItem(0, false, "-", let first) = blocks[0] else { return XCTFail("\(blocks[0])") }
        XCTAssertEqual(first, "A long item that continues.")
        guard case .listItem(0, false, "-", let second) = blocks[1] else { return XCTFail("\(blocks[1])") }
        XCTAssertEqual(second, "Next item")
    }

    func testBlocksFromRewritesLinks() {
        let md = """
        ### Added
        - See [docs](docs/obsidian-settings.md).
          - **Files & Links** (`app.json`): details.
        """
        let blocks = ReleaseNotes.blocks(from: md, tag: "0.1.8")
        XCTAssertEqual(blocks.count, 3)
        guard case .heading(3, "Added") = blocks[0] else { return XCTFail("\(blocks[0])") }
        guard case .listItem(0, false, "-", let parent) = blocks[1] else { return XCTFail("\(blocks[1])") }
        XCTAssertEqual(parent, "See [docs](\(notesBlob)/docs/obsidian-settings.md).")
        guard case .listItem(1, false, "-", let nested) = blocks[2] else { return XCTFail("\(blocks[2])") }
        XCTAssertEqual(nested, "**Files & Links** (`app.json`): details.")
    }

    func testAttributedInlineBoldCodeAndLink() {
        let text = "See **Files & Links** (`app.json`) and [docs](\(notesBlob)/docs/obsidian-settings.md)."
        let a = ReleaseNotes.attributed(text)
        var sawStrong = false, sawCode = false, sawLink = false
        for run in a.runs {
            if run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true { sawStrong = true }
            if run.inlinePresentationIntent?.contains(.code) == true { sawCode = true }
            if run.link?.absoluteString == "\(notesBlob)/docs/obsidian-settings.md" { sawLink = true }
        }
        XCTAssertTrue(sawStrong, "expected bold")
        XCTAssertTrue(sawCode, "expected inline code")
        XCTAssertTrue(sawLink, "expected rewritten link")
    }

    func testAttributedDoesNotLinkCodeSpans() {
        let a = ReleaseNotes.attributed("keep `[x](docs/x.md)` as code")
        XCTAssertTrue(a.runs.allSatisfy { $0.link == nil })
        XCTAssertTrue(a.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true })
    }

    func testExcerptFrom018ReleaseNotes() {
        let md = """
        ### Added
        - Obsidian's core settings stay in sync ([docs](docs/obsidian-settings.md)).
          - **Files & Links** (`app.json`): default location for new notes.
          - **Daily Notes** (`daily-notes.json`, `templates.json`): date format.
        - Attachments open in the pane ([docs](docs/attachments.md#opening-attachments)).

        ### Fixed
        - Markdown image embeds (`![](…)`) in the reader resolve as Obsidian resolves them.

        ### Updating

        Download the zip, unzip it, and replace `Onyx.app`. From v0.1.1 on, the app can also update itself.
        """
        let blocks = ReleaseNotes.blocks(from: md, tag: notesTag)
        XCTAssertEqual(blocks.first, .heading(level: 3, text: "Added"))
        XCTAssertEqual(blocks.filter {
            if case .heading = $0 { return true }; return false
        }.count, 3)
        let items = blocks.compactMap { b -> (Int, String)? in
            if case .listItem(let d, _, _, let t) = b { return (d, t) }
            return nil
        }
        XCTAssertEqual(items.count, 5)
        XCTAssertEqual(items[0].0, 0)
        XCTAssertTrue(items[0].1.contains("\(notesBlob)/docs/obsidian-settings.md"))
        XCTAssertEqual(items[1].0, 1)
        XCTAssertTrue(items[1].1.hasPrefix("**Files & Links** (`app.json`)"))
        XCTAssertTrue(items[3].1.contains("\(notesBlob)/docs/attachments.md#opening-attachments"))
        XCTAssertTrue(items[4].1.contains("`![](…)`"))
        XCTAssertFalse(items[4].1.contains("blob/v0.1.8"))
        guard case .paragraph(let p) = blocks.last else { return XCTFail("\(String(describing: blocks.last))") }
        XCTAssertTrue(p.contains("`Onyx.app`"))
    }
}
