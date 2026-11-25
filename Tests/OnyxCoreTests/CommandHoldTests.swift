import XCTest
@testable import OnyxCore

final class CommandHoldTests: XCTestCase {
    func testFlagsCommandAlone() {
        XCTAssertEqual(CommandHold.flagsEvent(command: true, shift: false, option: false, control: false), .commandAlone)
    }

    func testFlagsCommandReleased() {
        XCTAssertEqual(CommandHold.flagsEvent(command: false, shift: false, option: false, control: false), .commandReleased)
        XCTAssertEqual(CommandHold.flagsEvent(command: false, shift: true, option: false, control: false), .commandReleased)
    }

    func testFlagsOtherModifierCancels() {
        XCTAssertEqual(CommandHold.flagsEvent(command: true, shift: true, option: false, control: false), .cancel)
        XCTAssertEqual(CommandHold.flagsEvent(command: true, shift: false, option: true, control: false), .cancel)
        XCTAssertEqual(CommandHold.flagsEvent(command: true, shift: false, option: false, control: true), .cancel)
    }

    func testHoldThenReleaseBeforeTimer() {
        var m = CommandHold()
        XCTAssertEqual(m.handle(.commandAlone), .startTimer)
        XCTAssertEqual(m.phase, .pending)
        XCTAssertEqual(m.handle(.commandAlone), .none)
        XCTAssertEqual(m.handle(.commandReleased), .stopTimer)
        XCTAssertEqual(m.phase, .idle)
    }

    func testTimerShowsThenReleaseHides() {
        var m = CommandHold()
        XCTAssertEqual(m.handle(.commandAlone), .startTimer)
        XCTAssertEqual(m.handle(.timerFired), .show)
        XCTAssertEqual(m.phase, .showing)
        XCTAssertEqual(m.handle(.timerFired), .none)
        XCTAssertEqual(m.handle(.commandReleased), .hide)
        XCTAssertEqual(m.phase, .idle)
    }

    func testKeyOrClickCancelsPendingTimer() {
        var m = CommandHold()
        XCTAssertEqual(m.handle(.commandAlone), .startTimer)
        XCTAssertEqual(m.handle(.cancel), .stopTimer)
        XCTAssertEqual(m.phase, .idle)
    }

    func testKeyOrClickHidesVisibleSheet() {
        var m = CommandHold()
        _ = m.handle(.commandAlone)
        _ = m.handle(.timerFired)
        XCTAssertEqual(m.handle(.cancel), .hide)
        XCTAssertEqual(m.phase, .idle)
    }

    func testEscapeHidesVisibleSheet() {
        var m = CommandHold()
        _ = m.handle(.commandAlone)
        _ = m.handle(.timerFired)
        XCTAssertEqual(m.handle(.escape), .hide)
        XCTAssertEqual(m.phase, .idle)
    }

    func testEscapeCancelsPendingTimer() {
        var m = CommandHold()
        _ = m.handle(.commandAlone)
        XCTAssertEqual(m.handle(.escape), .stopTimer)
        XCTAssertEqual(m.phase, .idle)
    }

    func testIdleIgnoresReleaseAndTimer() {
        var m = CommandHold()
        XCTAssertEqual(m.handle(.commandReleased), .none)
        XCTAssertEqual(m.handle(.timerFired), .none)
        XCTAssertEqual(m.handle(.cancel), .none)
        XCTAssertEqual(m.handle(.escape), .none)
    }

    func testCanHoldAgainAfterHide() {
        var m = CommandHold()
        _ = m.handle(.commandAlone)
        _ = m.handle(.timerFired)
        _ = m.handle(.commandReleased)
        XCTAssertEqual(m.handle(.commandAlone), .startTimer)
        XCTAssertEqual(m.phase, .pending)
    }

    func testDurationIsTwoSeconds() {
        XCTAssertEqual(CommandHold.duration, 2.0)
    }
}

final class ShortcutHintsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var store: ShortcutStore!

    override func setUp() {
        super.setUp()
        suite = "onyx.hints.tests.\(UUID().uuidString)"
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

    func testDefaultRowsUseShippingShortcuts() {
        let rows = ShortcutHints.all(store: store)
        let keys = rows.map(\.0)
        XCTAssertTrue(keys.contains("⌘O"))
        XCTAssertTrue(keys.contains("⌘P"))
        XCTAssertTrue(keys.contains("⌘K"))
        XCTAssertTrue(keys.contains("⇧⌘F"))
        XCTAssertTrue(keys.contains("⌘↩"))
        XCTAssertTrue(keys.contains("⌘T"))
        XCTAssertTrue(keys.contains("⌥⌘I"))
        XCTAssertTrue(keys.contains("⌘B  ⌘I"))
        XCTAssertTrue(keys.contains("⌘G"))
        XCTAssertTrue(keys.contains("⌘[  ⌘]"))
        XCTAssertTrue(keys.contains("⌘⌫"))
        XCTAssertTrue(keys.contains("⇧⌘M"))
        XCTAssertTrue(keys.contains("⌘D"))
        XCTAssertTrue(keys.contains("⌘F"))
        XCTAssertTrue(keys.contains("⌃⌘F"))
        XCTAssertTrue(keys.contains("Esc"))
        if let palette = rows.first(where: { $0.0 == "⌘P" }) {
            XCTAssertTrue(palette.1.contains("⇧⌘P"), palette.1)
        } else {
            XCTFail("missing palette row")
        }
        if let inspector = rows.first(where: { $0.0 == "⌥⌘I" }) {
            XCTAssertTrue(inspector.1.lowercased().contains("inspector"), inspector.1)
        } else {
            XCTFail("missing inspector row")
        }
        if let style = rows.first(where: { $0.0 == "⌘B  ⌘I" }) {
            XCTAssertTrue(style.1.lowercased().contains("italic"), style.1)
        } else {
            XCTFail("missing bold/italic row")
        }
    }

    func testRowsFollowShortcutOverrides() {
        store.assign("inspector", .command("j", option: true))
        store.assign("italic", .command("i", shift: true))
        let rows = ShortcutHints.all(store: store)
        XCTAssertTrue(rows.contains(where: { $0.0 == "⌥⌘J" }))
        XCTAssertFalse(rows.contains(where: { $0.0 == "⌥⌘I" }))
        XCTAssertTrue(rows.contains(where: { $0.0 == "⌘B  ⇧⌘I" }))
    }

    func testUnboundCommandIsOmitted() {
        store.clear("switcher")
        let rows = ShortcutHints.all(store: store)
        XCTAssertFalse(rows.contains(where: { $0.0 == "⌘O" }))
        XCTAssertTrue(rows.contains(where: { $0.0 == "Esc" }))
    }
}
