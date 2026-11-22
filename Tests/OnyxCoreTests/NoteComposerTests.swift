import XCTest
import OnyxCore

final class NoteComposerTests: XCTestCase {

    // MARK: Merge bodies

    func testMergeAppendJoinsBodiesWithABlankLine() {
        let out = NoteComposer.merge(source: "Source body\n", target: "Target body\n", placement: .append)
        XCTAssertEqual(out, "Target body\n\nSource body\n")
    }

    func testMergePrependPutsSourceFirst() {
        let out = NoteComposer.merge(source: "Source", target: "Target", placement: .prepend)
        XCTAssertEqual(out, "Source\n\nTarget\n")
    }

    func testMergeEmptySourceLeavesTarget() {
        XCTAssertEqual(NoteComposer.merge(source: "", target: "Keep\n"), "Keep\n")
    }

    func testMergeEmptyTargetLeavesSource() {
        XCTAssertEqual(NoteComposer.merge(source: "Only\n", target: ""), "Only\n")
    }

    func testMergeStripsSourceAndTargetFrontmatterFromBodies() {
        let source = """
        ---
        tags: [a]
        ---

        From source
        """
        let target = """
        ---
        tags: [b]
        ---

        From target
        """
        let out = NoteComposer.merge(source: source, target: target)
        XCTAssertFalse(out.contains("From source\n---"), "bodies should not include the YAML fences")
        XCTAssertTrue(out.contains("From target"))
        XCTAssertTrue(out.hasSuffix("From source\n") || out.hasSuffix("From source"))
        let body = NoteComposer.body(of: out)
        XCTAssertEqual(body, "From target\n\nFrom source")
    }

    // MARK: Frontmatter

    func testMergeKeepsTargetScalarsAndAddsNewSourceKeys() {
        let source = """
        ---
        title: Source
        status: draft
        ---

        S
        """
        let target = """
        ---
        title: Target
        ---

        T
        """
        let out = NoteComposer.merge(source: source, target: target)
        let fm = Frontmatter.parse(out)
        XCTAssertEqual(fm["title"], .string("Target"))
        XCTAssertEqual(fm["status"], .string("draft"))
        XCTAssertEqual(NoteComposer.body(of: out, fm: fm), "T\n\nS")
    }

    func testMergeUnionsListPropertiesTargetFirst() {
        let source = """
        ---
        tags: [b, c]
        ---
        """
        let target = """
        ---
        tags:
          - a
          - b
        ---
        """
        let out = NoteComposer.merge(source: source, target: target)
        XCTAssertEqual(Frontmatter.parse(out)["tags"], .list(["a", "b", "c"]))
    }

    func testMergeUnionsScalarAndList() {
        let source = """
        ---
        aliases:
          - Other
        ---
        """
        let target = """
        ---
        aliases: Main
        ---
        """
        let out = NoteComposer.merge(source: source, target: target)
        XCTAssertEqual(Frontmatter.parse(out)["aliases"], .list(["Main", "Other"]))
    }

    func testMergeWithoutFrontmatterWritesNoYAML() {
        let out = NoteComposer.merge(source: "A", target: "B")
        XCTAssertFalse(out.hasPrefix("---"))
        XCTAssertEqual(out, "B\n\nA\n")
    }

    func testRenderQuotesYAMLThatNeedsIt() {
        let text = NoteComposer.render(
            properties: [
                Property(key: "title", value: .string("Hello: world")),
                Property(key: "ok", value: .bool(true)),
                Property(key: "count", value: .number(3)),
                Property(key: "tags", value: .list(["a", "yes"])),
            ],
            body: "Hi"
        )
        let fm = Frontmatter.parse(text)
        XCTAssertEqual(fm["title"], .string("Hello: world"))
        XCTAssertEqual(fm["ok"], .bool(true))
        XCTAssertEqual(fm["count"], .number(3))
        XCTAssertEqual(fm["tags"], .list(["a", "yes"]))
        XCTAssertEqual(NoteComposer.body(of: text, fm: fm), "Hi")
    }

    // MARK: Default extract name

    func testDefaultNameFromLeadingHeading() {
        XCTAssertEqual(NoteComposer.defaultName(forSelection: "# My Idea\n\nDetails"), "My Idea")
    }

    func testDefaultNameSkipsBlankLinesBeforeHeading() {
        XCTAssertEqual(NoteComposer.defaultName(forSelection: "\n\n## Nested Title\nbody"), "Nested Title")
    }

    func testDefaultNameStripsInlineMarkup() {
        XCTAssertEqual(NoteComposer.defaultName(forSelection: "# A **bold** [[Link|Alias]]"), "A bold Link")
    }

    func testDefaultNameNilWhenSelectionIsNotAHeading() {
        XCTAssertNil(NoteComposer.defaultName(forSelection: "Just a paragraph\n\n# Later"))
        XCTAssertNil(NoteComposer.defaultName(forSelection: ""))
        XCTAssertNil(NoteComposer.defaultName(forSelection: "#NotAHeading"))
    }

    // MARK: Heading section

    func testHeadingSectionRunsUntilNextSameOrHigherHeading() {
        let text = """
        Intro

        ## Keep

        inside

        ### Deeper

        still in

        ## Next

        after
        """
        let keep = text.range(of: "## Keep")!
        let offset = NSRange(keep, in: text).location
        let section = NoteComposer.headingSection(in: text, at: offset)
        XCTAssertEqual(section?.name, "Keep")
        let slice = (text as NSString).substring(with: section!.range)
        XCTAssertTrue(slice.hasPrefix("## Keep"))
        XCTAssertTrue(slice.contains("### Deeper"))
        XCTAssertTrue(slice.contains("still in"))
        XCTAssertFalse(slice.contains("## Next"))
        XCTAssertFalse(slice.contains("after"))
    }

    func testHeadingSectionFromCursorInTheBody() {
        let text = "# Top\n\nparagraph here\n\n# Other\n"
        let offset = (text as NSString).range(of: "paragraph").location
        let section = NoteComposer.headingSection(in: text, at: offset)
        XCTAssertEqual(section?.name, "Top")
        let slice = (text as NSString).substring(with: section!.range)
        XCTAssertTrue(slice.contains("paragraph here"))
        XCTAssertFalse(slice.contains("# Other"))
    }

    func testHeadingSectionNilBeforeTheFirstHeading() {
        let text = "Preamble\n\n# First\n"
        XCTAssertNil(NoteComposer.headingSection(in: text, at: 0))
    }

    func testHeadingSectionNilInFrontmatter() {
        let text = "---\ntitle: X\n---\n\n# Head\nbody\n"
        XCTAssertNil(NoteComposer.headingSection(in: text, at: 4))
    }

    func testHeadingSectionGoesToEndOfFile() {
        let text = "# Only\n\nthe rest"
        let section = NoteComposer.headingSection(in: text, at: 0)
        XCTAssertEqual(section?.name, "Only")
        XCTAssertEqual(section?.range, NSRange(location: 0, length: (text as NSString).length))
    }

    func testNestedHeadingDoesNotEndAHigherSection() {
        let text = "# Parent\n\n## Child\n\nchild body\n\n# Sibling\n"
        let section = NoteComposer.headingSection(in: text, at: 0)
        let slice = (text as NSString).substring(with: section!.range)
        XCTAssertTrue(slice.contains("## Child"))
        XCTAssertFalse(slice.contains("# Sibling"))
    }

    // MARK: Replacement and paths

    func testReplacementStyles() {
        XCTAssertEqual(NoteComposer.replacement(title: "Idea", style: .link), "[[Idea]]")
        XCTAssertEqual(NoteComposer.replacement(title: "Idea", style: .embed), "![[Idea]]")
        XCTAssertEqual(NoteComposer.replacement(title: "Idea", style: .none), "")
    }

    func testDisplayTitleUsesPathWhenTheNameClashes() {
        XCTAssertEqual(NoteComposer.displayTitle(path: "Folder/Note.md", clash: false), "Note")
        XCTAssertEqual(NoteComposer.displayTitle(path: "Folder/Note.md", clash: true), "Folder/Note")
    }

    func testFolderForNewNote() {
        XCTAssertEqual(NoteComposer.folder(forCurrent: "Projects/Alpha.md", location: .sameFolder), "Projects")
        XCTAssertEqual(NoteComposer.folder(forCurrent: "Alpha.md", location: .sameFolder), "")
        XCTAssertEqual(NoteComposer.folder(forCurrent: "Projects/Alpha.md", location: .vaultRoot), "")
        XCTAssertEqual(NoteComposer.folder(forCurrent: nil, location: .sameFolder), "")
    }

    func testPathNamedAddsExtensionAndFolder() {
        XCTAssertEqual(NoteComposer.path(named: "Idea", folder: "Projects"), "Projects/Idea.md")
        XCTAssertEqual(NoteComposer.path(named: "Idea.md", folder: "Projects"), "Projects/Idea.md")
        XCTAssertEqual(NoteComposer.path(named: "Other/Idea", folder: "Projects"), "Other/Idea.md")
        XCTAssertEqual(NoteComposer.path(named: "  ", folder: ""), "Untitled.md")
    }

    func testUniquePathAddsANumber() {
        let taken: Set<String> = ["Projects/Idea.md", "Projects/Idea 2.md"]
        XCTAssertEqual(NoteComposer.uniquePath("Projects/Idea.md", occupied: { taken.contains($0) }), "Projects/Idea 3.md")
        XCTAssertEqual(NoteComposer.uniquePath("Projects/New.md", occupied: { taken.contains($0) }), "Projects/New.md")
    }

    // MARK: Link remap (same rules as relocate)

    func testRemapRewritesNameWikilinksAndKeepsHeadingAndAlias() {
        let text = "See [[Source#Head|Alias]] and ![[Source]]."
        let links = NoteParser.parseWikiLinks(text)
        let out = WikiLinkRemap.rewrite(text, links: links, map: ["Source.md": "Target.md"], resolve: { t in
            t == "Source" ? "Source.md" : nil
        }, nameClash: { _ in false })
        XCTAssertEqual(out, "See [[Target#Head|Alias]] and ![[Target]].")
    }

    func testRemapRewritesPathWikilinks() {
        let text = "[[Folder/Source]]"
        let links = NoteParser.parseWikiLinks(text)
        let out = WikiLinkRemap.rewrite(text, links: links, map: ["Folder/Source.md": "Inbox/Target.md"], resolve: { t in
            t == "Folder/Source" ? "Folder/Source.md" : nil
        }, nameClash: { _ in false })
        XCTAssertEqual(out, "[[Inbox/Target]]")
    }

    func testRemapUsesPathWhenTheNewNameWouldClash() {
        let text = "[[Source]]"
        let links = NoteParser.parseWikiLinks(text)
        let out = WikiLinkRemap.rewrite(text, links: links, map: ["Source.md": "Folder/Target.md"], resolve: { t in
            t == "Source" ? "Source.md" : nil
        }, nameClash: { $0 == "Target" })
        XCTAssertEqual(out, "[[Folder/Target]]")
    }

    func testRemapLeavesUnrelatedLinksAlone() {
        let text = "[[Other]] and [[Source]]"
        let links = NoteParser.parseWikiLinks(text)
        let out = WikiLinkRemap.rewrite(text, links: links, map: ["Source.md": "Target.md"], resolve: { t in
            t == "Source" ? "Source.md" : (t == "Other" ? "Other.md" : nil)
        }, nameClash: { _ in false })
        XCTAssertEqual(out, "[[Other]] and [[Target]]")
    }

    func testRemapNilWhenNothingChanges() {
        let text = "[[Other]]"
        let links = NoteParser.parseWikiLinks(text)
        XCTAssertNil(WikiLinkRemap.rewrite(text, links: links, map: ["Source.md": "Target.md"], resolve: { t in
            t == "Other" ? "Other.md" : nil
        }, nameClash: { _ in false }))
    }

    func testRemapBareFieldLink() {
        var link = NoteParser.makeLink(inner: "Source", embed: false, range: NSRange(location: 10, length: 6))
        link.isBare = true
        link.fieldKey = "partOf"
        let text = "partOf:: Source\n"
        // The bare target starts at "Source"
        link.range = (text as NSString).range(of: "Source")
        let out = WikiLinkRemap.rewrite(text, links: [link], map: ["Source.md": "Target.md"], resolve: { t in
            t == "Source" ? "Source.md" : nil
        }, nameClash: { _ in false })
        XCTAssertEqual(out, "partOf:: Target\n")
    }
}
