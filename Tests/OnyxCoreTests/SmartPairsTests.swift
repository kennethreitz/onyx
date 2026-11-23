import XCTest
@testable import OnyxCore

final class SmartPairsTests: XCTestCase {
    private let on = SmartPairs.Settings()
    private let off = SmartPairs.Settings(autoPairBrackets: false, autoPairMarkdown: false)
    private func r(_ l: Int, _ n: Int = 0) -> NSRange { NSRange(location: l, length: n) }
    private func end(_ s: String) -> NSRange { r((s as NSString).length) }

    private func applyInsert(_ t: String, _ sel: NSRange, _ typed: String, settings: SmartPairs.Settings = SmartPairs.Settings()) -> String? {
        switch SmartPairs.insert(t, sel, typed: typed, settings: settings) {
        case .replace(let e): return e.applied(to: t)
        case .move: return t
        case nil: return nil
        }
    }
    private func caret(_ t: String, _ sel: NSRange, _ typed: String, settings: SmartPairs.Settings = SmartPairs.Settings()) -> NSRange? {
        switch SmartPairs.insert(t, sel, typed: typed, settings: settings) {
        case .replace(let e): return e.selection
        case .move(let s): return s
        case nil: return nil
        }
    }

    func testInsertsBracketPairs() {
        for (o, c) in [("(", ")"), ("[", "]"), ("{", "}")] {
            let e = SmartPairs.insert("", r(0), typed: o, settings: on)
            if case .replace(let edit) = e {
                XCTAssertEqual(edit.applied(to: ""), o + c)
                XCTAssertEqual(edit.selection, r(1))
            } else { XCTFail("expected pair for \(o)") }
        }
    }

    func testInsertsQuotesWhenNotMidWord() {
        XCTAssertEqual(applyInsert("", r(0), "\""), "\"\"")
        XCTAssertEqual(applyInsert("", r(0), "'"), "''")
        XCTAssertEqual(applyInsert("", r(0), "`"), "``")
        XCTAssertEqual(applyInsert("say ", end("say "), "'"), "say ''")
        XCTAssertEqual(caret("say ", end("say "), "'"), r(("say '" as NSString).length))
    }

    func testQuotesDoNotPairMidWord() {
        XCTAssertNil(SmartPairs.insert("don", end("don"), typed: "'", settings: on))
        XCTAssertNil(SmartPairs.insert("O", end("O"), typed: "\"", settings: on))
        XCTAssertNil(SmartPairs.insert("id_1", end("id_1"), typed: "`", settings: on))
        // after punctuation, pairing is fine
        XCTAssertEqual(applyInsert("()", r(1), "'"), "('')")
    }

    func testWikilinkDoubleBracket() {
        // first [ → [|]
        XCTAssertEqual(applyInsert("", r(0), "["), "[]")
        XCTAssertEqual(caret("", r(0), "["), r(1))
        // second [ inside [|] → [[|]]
        let once = "[]"
        XCTAssertEqual(applyInsert(once, r(1), "["), "[[]]")
        XCTAssertEqual(caret(once, r(1), "["), r(2))
        // typing ] steps over each closer
        let full = "[[]]"
        if case .move(let s) = SmartPairs.insert(full, r(2), typed: "]", settings: on) {
            XCTAssertEqual(s, r(3))
        } else { XCTFail("step over first ]") }
        if case .move(let s) = SmartPairs.insert(full, r(3), typed: "]", settings: on) {
            XCTAssertEqual(s, r(4))
        } else { XCTFail("step over second ]") }
        // a two-character insert from wikilink accept/leave is not intercepted
        XCTAssertNil(SmartPairs.insert("[[Name", end("[[Name"), typed: "]]", settings: on))
    }

    func testWrapsSelection() {
        let t = "bold"
        let all = r(0, 4)
        let e = SmartPairs.insert(t, all, typed: "*", settings: on)
        if case .replace(let edit) = e {
            XCTAssertEqual(edit.applied(to: t), "*bold*")
            XCTAssertEqual(edit.selection, r(1, 4))
        } else { XCTFail("wrap *") }
        let inner = r(1, 4)
        let twice = SmartPairs.insert("*bold*", inner, typed: "*", settings: on)
        if case .replace(let edit) = twice {
            XCTAssertEqual(edit.applied(to: "*bold*"), "**bold**")
            XCTAssertEqual(edit.selection, r(2, 4))
        } else { XCTFail("wrap **") }
        XCTAssertEqual(applyInsert("hi", r(0, 2), "="), "=hi=")
        XCTAssertEqual(applyInsert("hi", r(0, 2), "~"), "~hi~")
        XCTAssertEqual(applyInsert("hi", r(0, 2), "_"), "_hi_")
        XCTAssertEqual(applyInsert("hi", r(0, 2), "("), "(hi)")
        XCTAssertEqual(applyInsert("hi", r(0, 2), "\""), "\"hi\"")
        XCTAssertEqual(caret("hi", r(0, 2), "["), r(1, 2))
    }

    func testMarkdownDoesNotPairWithoutSelection() {
        XCTAssertNil(SmartPairs.insert("", r(0), typed: "*", settings: on))
        XCTAssertNil(SmartPairs.insert("a", end("a"), typed: "_", settings: on))
        XCTAssertNil(SmartPairs.insert("", r(0), typed: "~", settings: on))
        XCTAssertNil(SmartPairs.insert("", r(0), typed: "=", settings: on))
    }

    func testStepsOverCloser() {
        if case .move(let s) = SmartPairs.insert("()", r(1), typed: ")", settings: on) {
            XCTAssertEqual(s, r(2))
        } else { XCTFail("step )") }
        if case .move(let s) = SmartPairs.insert("\"\"", r(1), typed: "\"", settings: on) {
            XCTAssertEqual(s, r(2))
        } else { XCTFail("step quote") }
        if case .move(let s) = SmartPairs.insert("*x*", r(2), typed: "*", settings: on) {
            XCTAssertEqual(s, r(3))
        } else { XCTFail("step *") }
    }

    func testDeleteEmptyPair() {
        let t = "()"
        let e = SmartPairs.deleteBackward(t, r(1), settings: on)!
        XCTAssertEqual(e.applied(to: t), "")
        XCTAssertEqual(e.selection, r(0))
        XCTAssertEqual(SmartPairs.deleteBackward("[[]]", r(2), settings: on)!.applied(to: "[[]]"), "[]")
        XCTAssertEqual(SmartPairs.deleteBackward("[[]]", r(2), settings: on)!.selection, r(1))
        XCTAssertEqual(SmartPairs.deleteBackward("**", r(1), settings: on)!.applied(to: "**"), "")
        // not empty, or not a pair
        XCTAssertNil(SmartPairs.deleteBackward("(x)", r(2), settings: on))
        XCTAssertNil(SmartPairs.deleteBackward("()", r(2), settings: on))
        XCTAssertNil(SmartPairs.deleteBackward("x", r(1), settings: on))
    }

    func testSettingsOff() {
        XCTAssertNil(SmartPairs.insert("", r(0), typed: "(", settings: off))
        XCTAssertNil(SmartPairs.insert("hi", r(0, 2), typed: "*", settings: off))
        XCTAssertNil(SmartPairs.insert("()", r(1), typed: ")", settings: off))
        XCTAssertNil(SmartPairs.deleteBackward("()", r(1), settings: off))
        let bracketsOnly = SmartPairs.Settings(autoPairBrackets: true, autoPairMarkdown: false)
        XCTAssertEqual(applyInsert("", r(0), "(", settings: bracketsOnly), "()")
        XCTAssertNil(SmartPairs.insert("hi", r(0, 2), typed: "*", settings: bracketsOnly))
        let mdOnly = SmartPairs.Settings(autoPairBrackets: false, autoPairMarkdown: true)
        XCTAssertNil(SmartPairs.insert("", r(0), typed: "(", settings: mdOnly))
        XCTAssertEqual(applyInsert("hi", r(0, 2), "*", settings: mdOnly), "*hi*")
    }

    func testSkipsMarkdownInsideFences() {
        let t = "```\ncode\n```"
        let inside = ("```\nco" as NSString).length
        XCTAssertNil(SmartPairs.insert(t, r(inside, 2), typed: "*", settings: on))
        XCTAssertNil(SmartPairs.insert(t, r(inside), typed: "*", settings: on))
        // brackets still pair inside a fence
        XCTAssertEqual(applyInsert(t, r(inside), "("), "```\nco()de\n```")
        // after the fence, markdown wrap works
        let after = t + "\nword"
        XCTAssertEqual(applyInsert(after, r((t + "\n" as NSString).length, 4), "*"), "```\ncode\n```\n*word*")
        XCTAssertNil(SmartPairs.insert("```\n", end("```\n"), typed: "*", settings: on))
    }

    func testIgnoresMultiCharacterInserts() {
        XCTAssertNil(SmartPairs.insert("", r(0), typed: "((", settings: on))
        XCTAssertNil(SmartPairs.insert("", r(0), typed: "", settings: on))
        XCTAssertNil(SmartPairs.insert("ab", r(0, 2), typed: "x", settings: on))
    }

    func testDefaultSettingsFromAppJSON() {
        XCTAssertEqual(SmartPairs.Settings.from(appJSON: nil).autoPairBrackets, true)
        XCTAssertEqual(SmartPairs.Settings.from(appJSON: [:]).autoPairMarkdown, true)
        let offJSON: [String: Any] = ["autoPairBrackets": false, "autoPairMarkdown": false]
        let s = SmartPairs.Settings.from(appJSON: offJSON)
        XCTAssertFalse(s.autoPairBrackets)
        XCTAssertFalse(s.autoPairMarkdown)
    }
}
