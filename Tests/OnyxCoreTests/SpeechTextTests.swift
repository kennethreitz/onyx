import XCTest
@testable import OnyxCore

final class SpeechTextTests: XCTestCase {
    func speak(_ s: String) -> String { SpeechText.clean(s) }

    func testPlainProseIsUnchanged() {
        XCTAssertEqual(speak("Hello, world."), "Hello, world.")
        XCTAssertEqual(speak("  Just a sentence.  \n"), "Just a sentence.")
    }

    func testFrontmatterIsStripped() {
        let src = """
        ---
        title: Secret
        tags: [a, b]
        ---
        The body of the note.
        """
        XCTAssertEqual(speak(src), "The body of the note.")
    }

    func testBodyDashesAreNotTreatedAsFrontmatter() {
        let src = "A line.\n---\nStill the body."
        XCTAssertEqual(speak(src), "A line.\n\nStill the body.")
    }

    func testCommentsAreStripped() {
        XCTAssertEqual(speak("Hello %%hidden%% world."), "Hello world.")
        let multi = "Visible\n%%a\nsecret\n%%\nAfter"
        XCTAssertEqual(speak(multi), "Visible\n\nAfter")
        XCTAssertEqual(speak("Keep <!-- not this --> this."), "Keep this.")
    }

    func testFencedCodeBlocksAreRemoved() {
        let src = """
        Before
        ```swift
        let x = 1
        print(x)
        ```
        After
        """
        XCTAssertEqual(speak(src), "Before\n\nAfter")

        let tildes = """
        Intro
        ~~~
        not spoken
        ~~~
        Outro
        """
        XCTAssertEqual(speak(tildes), "Intro\n\nOutro")
    }

    func testUnclosedFenceIsDropped() {
        XCTAssertEqual(speak("Lead\n```python\nsecret = 1\n"), "Lead")
    }

    func testInlineCodeKeepsTheWords() {
        XCTAssertEqual(speak("Use `print()` here."), "Use print() here.")
        XCTAssertEqual(speak("A ``raw ` tick`` stays."), "A raw ` tick stays.")
    }

    func testWikilinksSpeakAliasOrName() {
        XCTAssertEqual(speak("See [[Daily Notes]]."), "See Daily Notes.")
        XCTAssertEqual(speak("See [[Daily Notes|today]]."), "See today.")
        XCTAssertEqual(speak("See [[Projects/Plan]]."), "See Plan.")
        XCTAssertEqual(speak("See [[Projects/Plan#Goals]]."), "See Plan.")
        XCTAssertEqual(speak("See [[Projects/Plan#Goals|the plan]]."), "See the plan.")
        XCTAssertEqual(speak("See [[Note.md]]."), "See Note.")
    }

    func testMediaEmbedsAreSilentAndNoteEmbedsSpeakTheName() {
        XCTAssertEqual(speak("A picture ![[photo.png]] here."), "A picture here.")
        XCTAssertEqual(speak("A file ![[docs/spec.pdf]] here."), "A file here.")
        XCTAssertEqual(speak("See also ![[Related Note]]."), "See also Related Note.")
        XCTAssertEqual(speak("See also ![[Related|that]]."), "See also that.")
    }

    func testMarkdownLinksDropTheURL() {
        XCTAssertEqual(speak("Visit [Apple](https://apple.com) today."), "Visit Apple today.")
        XCTAssertEqual(speak("See [the plan](Projects/Plan.md)."), "See the plan.")
        XCTAssertEqual(speak("Look [here][ref] later.\n\n[ref]: https://example.com"), "Look here later.")
    }

    func testImagesSpeakAltText() {
        XCTAssertEqual(speak("Here ![a cat](cat.png) sat."), "Here a cat sat.")
        XCTAssertEqual(speak("Blank ![](x.png) ok."), "Blank ok.")
    }

    func testURLsAreStripped() {
        XCTAssertEqual(speak("Go to https://example.com/path now."), "Go to now.")
        XCTAssertEqual(speak("Go to https://example.com."), "Go to.")
        XCTAssertEqual(speak("See <https://example.com> please."), "See please.")
        XCTAssertEqual(speak("www.example.com is gone."), "is gone.")
    }

    func testHeadingsLoseTheirMarks() {
        XCTAssertEqual(speak("# Title\n\nBody."), "Title\n\nBody.")
        XCTAssertEqual(speak("## A heading ##\nNext."), "A heading\nNext.")
        XCTAssertEqual(speak("Setext\n======\nBody."), "Setext\n\nBody.")
    }

    func testEmphasisAndHighlightsKeepTheWords() {
        XCTAssertEqual(speak("This is **bold** and *italic*."), "This is bold and italic.")
        XCTAssertEqual(speak("This is __bold__ and _italic_ too."), "This is bold and italic too.")
        XCTAssertEqual(speak("A ~~strike~~ and ==highlight==."), "A strike and highlight.")
        XCTAssertEqual(speak("Keep file_name intact."), "Keep file_name intact.")
    }

    func testListsAndTasks() {
        let src = """
        - First
        - [ ] Open
        - [x] Done
        1. Numbered
        """
        XCTAssertEqual(speak(src), "First\nOpen\nDone\nNumbered")
    }

    func testBlockquotesAndCallouts() {
        XCTAssertEqual(speak("> A quoted line."), "A quoted line.")
        XCTAssertEqual(speak("> [!note] Title\n> The body."), "Title\nThe body.")
        XCTAssertEqual(speak("> [!warning]\n> Watch out."), "Watch out.")
    }

    func testTablesSpeakCells() {
        let src = """
        | Name | Age |
        | ---- | --- |
        | Ada  | 36  |
        """
        XCTAssertEqual(speak(src), "Name, Age\nAda, 36")
    }

    func testHorizontalRulesVanish() {
        XCTAssertEqual(speak("Above\n\n---\n\nBelow"), "Above\n\nBelow")
        XCTAssertEqual(speak("Above\n***\nBelow"), "Above\n\nBelow")
    }

    func testFootnotesAndHTMLAreCleaned() {
        XCTAssertEqual(speak("A claim[^1] here.\n\n[^1]: The source."), "A claim here.\n\nThe source.")
        XCTAssertEqual(speak("Hello <em>there</em>."), "Hello there.")
        XCTAssertEqual(speak("Line<br>break."), "Line break.")
    }

    func testMathIsDropped() {
        XCTAssertEqual(speak("Energy $E = mc^2$ matters."), "Energy matters.")
        XCTAssertEqual(speak("Shown:\n$$\\int x$$\nDone."), "Shown:\n\nDone.")
    }

    func testBlankLinesCollapseAndEdgesTrim() {
        let src = "\n\nOne.\n\n\n\nTwo.\n\n"
        XCTAssertEqual(speak(src), "One.\n\nTwo.")
    }

    func testARealisticNote() {
        let src = """
        ---
        aliases: [Demo]
        ---
        # Hello

        This is a **note** about [[Projects/Plan|the plan]] and [Apple](https://apple.com).

        %%draft%%

        ```
        skip me
        ```

        - [x] Write it
        - See https://example.com for more.

        A picture ![[shot.png]] and some `code`.
        """
        let out = speak(src)
        XCTAssertEqual(out, """
        Hello

        This is a note about the plan and Apple.

        Write it
        See for more.

        A picture and some code.
        """)
        XCTAssertFalse(out.contains("[["))
        XCTAssertFalse(out.contains("https://"))
        XCTAssertFalse(out.contains("skip me"))
        XCTAssertFalse(out.contains("aliases"))
        XCTAssertFalse(out.contains("%%"))
        XCTAssertFalse(out.contains("shot.png"))
    }
}
