import XCTest
@testable import OnyxCore

final class UnlinkedMentionsTests: XCTestCase {

    private func note(_ path: String, _ body: String, aliases: [String] = [], title: String? = nil) -> NoteRecord {
        var text = body
        if !aliases.isEmpty || title != nil {
            var fm = "---\n"
            if let title { fm += "title: \(title)\n" }
            if !aliases.isEmpty { fm += "aliases: [\(aliases.map { $0 }.joined(separator: ", "))]\n" }
            fm += "---\n"
            text = fm + body
        }
        return VaultSnapshot.makeRecord(rel: path, content: text)
    }

    private func snap(_ notes: [NoteRecord]) -> VaultSnapshot {
        var s = VaultSnapshot(root: URL(fileURLWithPath: "/tmp/onyx-unlinked"))
        for n in notes { s.notes[n.path] = n }
        s.rebuildDerived()
        return s
    }

    func testFindsCaseInsensitiveTitle() {
        let target = note("Target.md", "# Target\n")
        let other = note("Other.md", "I mentioned target in passing.\n")
        let hits = UnlinkedMentions.find(in: snap([target, other]), of: "Target.md")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].source, "Other.md")
        XCTAssertEqual(hits[0].matched, "target")
        XCTAssertEqual(hits[0].line, 0)
        XCTAssertTrue(hits[0].context.contains("target"))
    }

    func testWordBoundarySkipsNotebook() {
        let target = note("Note.md", "hello")
        let other = note("Other.md", "I opened the Notebook today.\n")
        XCTAssertTrue(UnlinkedMentions.find(in: snap([target, other]), of: "Note.md").isEmpty)
    }

    func testFindsAliasAndPrefersLongerPhrase() {
        let target = note("Daily Notes.md", "hi", aliases: ["journal"])
        let other = note("Other.md", "My journal is daily.\n")
        let hits = UnlinkedMentions.find(in: snap([target, other]), of: "Daily Notes.md")
        XCTAssertEqual(hits.map(\.matched), ["journal"])
        XCTAssertEqual(hits[0].needle.lowercased(), "journal")
    }

    func testUsesHeadingTitleWhenDifferentFromFilename() {
        let target = VaultSnapshot.makeRecord(rel: "xyz.md", content: "# Ancient History\nBody.\n")
        let other = note("Other.md", "I studied Ancient History last year.\n")
        let hits = UnlinkedMentions.find(in: snap([target, other]), of: "xyz.md")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].matched, "Ancient History")
    }

    func testSkipsFencedAndInlineCode() {
        let target = note("Target.md", "x")
        let other = note("Other.md", """
        ```
        Target
        ```
        Use `Target` in a command, then Target in prose.
        """)
        let hits = UnlinkedMentions.find(in: snap([target, other]), of: "Target.md")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].matched, "Target")
        XCTAssertTrue(hits[0].context.contains("prose"))
    }

    func testSkipsExistingWikilinksAndMarkdownLinks() {
        let target = note("Target.md", "x")
        let other = note("Other.md", "See [[Target]] and [Target](Target.md), then Target again.\n")
        let hits = UnlinkedMentions.find(in: snap([target, other]), of: "Target.md")
        XCTAssertEqual(hits.count, 1)
        XCTAssertTrue(hits[0].context.hasSuffix("again."))
    }

    func testSkipsCommentsAndFrontmatter() {
        let target = note("Target.md", "x")
        let other = VaultSnapshot.makeRecord(rel: "Other.md", content: """
        ---
        related: Target
        ---
        %% Target %%
        <!-- Target -->
        And Target in the body.
        """)
        let hits = UnlinkedMentions.find(in: snap([target, other]), of: "Target.md")
        XCTAssertEqual(hits.count, 1)
        XCTAssertTrue(hits[0].context.contains("body"))
    }

    func testStillFindsMentionsInANoteThatAlreadyLinks() {
        let target = note("Target.md", "x")
        let other = note("Other.md", "A real [[Target]] link, and later a bare Target mention.\n")
        let hits = UnlinkedMentions.find(in: snap([target, other]), of: "Target.md")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].matched, "Target")
    }

    func testMultipleMentionsInOneFileAndIgnoresSelf() {
        let target = note("Target.md", "Target talks about Target.\n")
        let other = note("Other.md", "Target once, then Target twice.\n")
        let hits = UnlinkedMentions.find(in: snap([target, other]), of: "Target.md")
        XCTAssertEqual(hits.count, 2)
        XCTAssertEqual(hits.map(\.source), ["Other.md", "Other.md"])
        XCTAssertNotEqual(hits[0].range.location, hits[1].range.location)
    }

    func testShortNamesAreIgnored() {
        let target = note("OK.md", "x")
        let other = note("Other.md", "OK sure.\n")
        XCTAssertTrue(UnlinkedMentions.find(in: snap([target, other]), of: "OK.md").isEmpty)
    }

    func testLinkWrapsTitleAndAlias() {
        let text = "I mentioned journal today."
        let r = (text as NSString).range(of: "journal")
        XCTAssertEqual(UnlinkedMentions.link(text, range: r, title: "Daily Notes"), "I mentioned [[Daily Notes|journal]] today.")
        let t2 = "See Target here."
        let r2 = (t2 as NSString).range(of: "Target")
        XCTAssertEqual(UnlinkedMentions.link(t2, range: r2, title: "Target"), "See [[Target]] here.")
    }

    func testLinkAllAppliesRightToLeft() {
        let text = "Target and Target."
        let mentions = UnlinkedMentions.find(in: text, source: "A.md", needles: ["Target"])
        XCTAssertEqual(mentions.count, 2)
        let (out, count) = UnlinkedMentions.linkAll(text, mentions: mentions, title: "Target")
        XCTAssertEqual(count, 2)
        XCTAssertEqual(out, "[[Target]] and [[Target]].")
    }

    func testVaultSnapshotDelegate() {
        let target = note("Target.md", "x")
        let other = note("Other.md", "Hello Target.\n")
        let s = snap([target, other])
        XCTAssertEqual(s.unlinkedMentions(of: "Target.md").count, 1)
    }
}
