import XCTest
@testable import OnyxCore

final class ShortcutStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var store: ShortcutStore!

    override func setUp() {
        super.setUp()
        suite = "onyx.shortcuts.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        store = ShortcutStore(defaults: defaults, catalog: CommandCatalog.all)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        store = nil
        super.tearDown()
    }

    func testDefaultsMatchShippingShortcuts() {
        XCTAssertEqual(store.display(for: "switcher"), "⌘O")
        XCTAssertEqual(store.display(for: "palette"), "⌘P  ⇧⌘P")
        XCTAssertEqual(store.display(for: "new"), "⌘N")
        XCTAssertEqual(store.display(for: "newfolder"), "⇧⌘N")
        XCTAssertEqual(store.display(for: "openvault"), "⇧⌘O")
        XCTAssertEqual(store.display(for: "save"), "⌘S")
        XCTAssertEqual(store.display(for: "move"), "⇧⌘M")
        XCTAssertEqual(store.display(for: "delete"), "⌘⌫")
        XCTAssertEqual(store.display(for: "exportpdf"), "⇧⌘E")
        XCTAssertEqual(store.display(for: "print"), "⌥⌘P")
        XCTAssertEqual(store.display(for: "daily"), "⌘T  ⌘\\")
        XCTAssertEqual(store.display(for: "daily-prev"), "⌥⌘[")
        XCTAssertEqual(store.display(for: "daily-next"), "⌥⌘]")
        XCTAssertEqual(store.display(for: "back"), "⌘[")
        XCTAssertEqual(store.display(for: "forward"), "⌘]")
        XCTAssertEqual(store.display(for: "home"), "⇧⌘H")
        XCTAssertEqual(store.display(for: "graph"), "⌘G")
        XCTAssertEqual(store.display(for: "atlas"), "⇧⌘G")
        XCTAssertEqual(store.display(for: "graphpane"), "⌥⌘G")
        XCTAssertEqual(store.display(for: "split"), "⌘D")
        XCTAssertEqual(store.display(for: "splitdown"), "⇧⌘D")
        XCTAssertEqual(store.display(for: "closepane"), "⌘W")
        XCTAssertEqual(store.display(for: "nextpane"), "⌃⇥")
        XCTAssertEqual(store.display(for: "prevpane"), "⌃⇧⇥")
        XCTAssertEqual(store.display(for: "mode"), "⌘↩")
        XCTAssertEqual(store.display(for: "modetoggle"), "⌘E")
        XCTAssertEqual(store.display(for: "focus"), "⌃⌘F")
        XCTAssertEqual(store.display(for: "files"), "⌘K")
        XCTAssertEqual(store.display(for: "search"), "⇧⌘F")
        XCTAssertEqual(store.display(for: "recent"), "⇧⌘R")
        XCTAssertEqual(store.display(for: "bookmarks"), "⇧⌘B")
        XCTAssertEqual(store.display(for: "tags"), "⇧⌘T")
        XCTAssertEqual(store.display(for: "git"), "⇧⌘Y")
        XCTAssertEqual(store.display(for: "inspector"), "⌘I")
        XCTAssertEqual(store.display(for: "outline"), "⌥⌘1")
        XCTAssertEqual(store.display(for: "backlinks"), "⌥⌘2")
        XCTAssertEqual(store.display(for: "props"), "⌥⌘3")
        XCTAssertEqual(store.display(for: "layout"), "⌥⌘0")
        XCTAssertEqual(store.display(for: "find"), "⌘F")
        XCTAssertEqual(store.display(for: "findreplace"), "⌥⌘F")
        XCTAssertEqual(store.display(for: "bookmark"), "⌥⌘D")
        XCTAssertEqual(store.display(for: "copy"), "⇧⌘L")
        XCTAssertEqual(store.display(for: "finder"), "⌥⇧⌘R")
        XCTAssertEqual(store.chords(for: "rename"), [])
        XCTAssertEqual(store.chords(for: "synclog"), [])
    }

    func testDefaultChordsAreUnique() {
        var seen: [KeyChord: String] = [:]
        for spec in CommandCatalog.all {
            for chord in spec.defaultChords {
                if let other = seen[chord] {
                    XCTFail("\(chord.display) is bound to both \(other) and \(spec.id)")
                }
                seen[chord] = spec.id
            }
        }
        var ids = Set<String>()
        for spec in CommandCatalog.all {
            XCTAssertFalse(spec.id.isEmpty)
            XCTAssertTrue(ids.insert(spec.id).inserted, "duplicate command id \(spec.id)")
        }
    }

    func testOverrideAndReset() {
        let chord = KeyChord.command("j")
        XCTAssertTrue(store.evaluate(chord, for: "switcher").isClear)
        store.assign("switcher", chord)
        XCTAssertEqual(store.chords(for: "switcher"), [chord])
        XCTAssertTrue(store.isOverridden("switcher"))
        XCTAssertEqual(store.display(for: "switcher"), "⌘J")
        store.reset("switcher")
        XCTAssertEqual(store.display(for: "switcher"), "⌘O")
        XCTAssertFalse(store.isOverridden("switcher"))
    }

    func testClearUnbinds() {
        store.clear("graph")
        XCTAssertEqual(store.chords(for: "graph"), [])
        XCTAssertTrue(store.isOverridden("graph"))
        XCTAssertNil(store.commandId(for: .command("g")))
        store.reset("graph")
        XCTAssertEqual(store.display(for: "graph"), "⌘G")
    }

    func testConflictAndReassign() {
        let chord = KeyChord.command("g")
        let proposal = store.evaluate(chord, for: "switcher")
        XCTAssertEqual(proposal.conflictId, "graph")
        XCTAssertEqual(proposal.conflictTitle, "Focus Graph")
        XCTAssertFalse(proposal.isClear)
        store.assign("switcher", chord, replacing: "graph")
        XCTAssertEqual(store.chords(for: "switcher"), [chord])
        XCTAssertEqual(store.chords(for: "graph"), [])
        XCTAssertEqual(store.commandId(for: chord), "switcher")
    }

    func testStealOneChordFromMultiDefault() {
        store.assign("save", .command("p"), replacing: "palette")
        XCTAssertEqual(store.display(for: "save"), "⌘P")
        XCTAssertEqual(store.chords(for: "palette"), [.command("p", shift: true)])
        XCTAssertEqual(store.display(for: "palette"), "⇧⌘P")
    }

    func testReservedShortcuts() {
        XCTAssertEqual(store.evaluate(.command("q"), for: "graph").reservedReason, "Quit")
        XCTAssertEqual(store.evaluate(.command("c"), for: "graph").reservedReason, "Copy")
        XCTAssertEqual(store.evaluate(.command(","), for: "graph").reservedReason, "Settings")
        XCTAssertNil(store.evaluate(.command("g"), for: "graph").reservedReason)
        XCTAssertTrue(KeyChord.command("q").isReserved)
        XCTAssertFalse(KeyChord.command("w").isReserved)
    }

    func testResetAllAndPersistenceRoundTrip() {
        store.assign("switcher", .command("j"))
        store.clear("graph")
        store.assign("search", .command("f", shift: true, option: true))
        XCTAssertTrue(store.isOverridden("switcher"))

        let again = ShortcutStore(defaults: defaults, catalog: CommandCatalog.all)
        XCTAssertEqual(again.display(for: "switcher"), "⌘J")
        XCTAssertEqual(again.chords(for: "graph"), [])
        XCTAssertEqual(again.display(for: "search"), "⌥⇧⌘F")
        XCTAssertEqual(again.display(for: "atlas"), "⇧⌘G")

        again.resetAll()
        XCTAssertEqual(again.display(for: "switcher"), "⌘O")
        XCTAssertEqual(again.display(for: "graph"), "⌘G")
        XCTAssertFalse(again.isOverridden("search"))

        store.reload()
        XCTAssertEqual(store.display(for: "switcher"), "⌘O")
        XCTAssertEqual(store.display(for: "graph"), "⌘G")
        XCTAssertEqual(store.display(for: "search"), "⇧⌘F")
    }

    func testConflictsOnReset() {
        store.assign("switcher", .command("g"), replacing: "graph")
        let conflicts = store.conflictsOnReset("graph")
        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(conflicts.first?.commandId, "switcher")
        store.reset("graph", replacing: ["switcher"])
        XCTAssertEqual(store.display(for: "graph"), "⌘G")
        XCTAssertEqual(store.chords(for: "switcher"), [])
    }

    func testEventParsing() {
        let o = KeyChord(charactersIgnoringModifiers: "o", keyCode: 31, modifiers: .command)
        XCTAssertEqual(o, .command("o"))
        let del = KeyChord(charactersIgnoringModifiers: "\u{7F}", keyCode: 51, modifiers: .command)
        XCTAssertEqual(del, .command("\u{7F}"))
        let tab = KeyChord(charactersIgnoringModifiers: "\t", keyCode: 48, modifiers: .control)
        XCTAssertEqual(tab?.display, "⌃⇥")
        let pal = KeyChord(charactersIgnoringModifiers: "p", keyCode: 35, modifiers: [.command, .shift])
        XCTAssertEqual(pal?.display, "⇧⌘P")
        XCTAssertNil(KeyChord(charactersIgnoringModifiers: "", keyCode: 55, modifiers: .command))
        XCTAssertTrue(KeyChord.command("g").matches(charactersIgnoringModifiers: "g", keyCode: 5, modifiers: .command))
        XCTAssertFalse(KeyChord.command("g").matches(charactersIgnoringModifiers: "g", keyCode: 5, modifiers: [.command, .shift]))
    }
}
