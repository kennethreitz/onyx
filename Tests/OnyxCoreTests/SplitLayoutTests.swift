import XCTest
@testable import OnyxCore

final class SplitLayoutTests: XCTestCase {
    func testEncodeDecodeRoundTrip() {
        let layout = SplitLayout(
            axis: .horizontal,
            ratios: [0.35, 0.65],
            panes: [SplitLayout.Pane(path: "Home.md"), SplitLayout.Pane(path: "Daily/2026-11-20.md")],
            focused: 1
        )
        let data = layout.encoded()
        XCTAssertNotNil(data)
        let back = SplitLayout.decode(data!)
        XCTAssertEqual(back, layout)

        // Stable keys, so an older build can still read this.
        let json = try! JSONSerialization.jsonObject(with: data!) as! [String: Any]
        XCTAssertEqual(json["axis"] as? String, "horizontal")
        XCTAssertEqual(json["focused"] as? Int, 1)
        XCTAssertEqual((json["ratios"] as? [Double])?.count, 2)
        XCTAssertEqual((json["panes"] as? [[String: Any]])?.count, 2)
    }

    func testDecodeRejectsGarbage() {
        XCTAssertNil(SplitLayout.decode(Data()))
        XCTAssertNil(SplitLayout.decode(Data("not json".utf8)))
        XCTAssertNil(SplitLayout.decode(Data("{\"axis\":1}".utf8)))
    }

    func testDecodeGraphPane() {
        let src = SplitLayout(
            axis: .vertical,
            ratios: [0.5, 0.5],
            panes: [SplitLayout.Pane(path: "Home.md"), SplitLayout.Pane(path: nil, isGraph: true)],
            focused: 0
        )
        XCTAssertEqual(SplitLayout.decode(src.encoded()!), src)
    }

    func testClampLiftsATooSmallPane() {
        // 0.1 of 1000.8 available would be 100pt; floor is 240.
        let r = PaneRatios.clamped([0.1, 0.9], total: 1000.8)
        let sizes = PaneRatios.sizes(r, total: 1000.8)
        XCTAssertEqual(sizes[0], 240, accuracy: 0.01)
        XCTAssertEqual(sizes[1], 760, accuracy: 0.01)
        XCTAssertEqual(r[0] + r[1], 1, accuracy: 0.0001)
        XCTAssertEqual(r[0], 240 / 1000, accuracy: 0.0001)
    }

    func testClampShrinksFloorWhenWindowIsTight() {
        let r = PaneRatios.clamped([0.2, 0.8], total: 400.8)
        let sizes = PaneRatios.sizes(r, total: 400.8)
        XCTAssertEqual(sizes[0], 200, accuracy: 0.01)
        XCTAssertEqual(sizes[1], 200, accuracy: 0.01)
        XCTAssertEqual(r[0], 0.5, accuracy: 0.0001)
    }

    func testClampSingleAndEmpty() {
        XCTAssertEqual(PaneRatios.clamped([], count: 0, total: 1000), [])
        XCTAssertEqual(PaneRatios.clamped([0.3, 0.7], count: 1, total: 1000), [1])
    }

    func testSanitizeDropsMissingNotesAndClamps() {
        let raw = SplitLayout(
            axis: .vertical,
            ratios: [0.1, 0.2, 0.7],
            panes: [
                SplitLayout.Pane(path: "Gone.md"),
                SplitLayout.Pane(path: "Home.md"),
                SplitLayout.Pane(path: "Kept.md"),
            ],
            focused: 0  // the missing note; should land on Home
        )
        let out = raw.sanitized(existing: { $0 != "Gone.md" }, total: 1000.8)
        XCTAssertEqual(out?.axis, .vertical)
        XCTAssertEqual(out?.panes.map(\.path), ["Home.md", "Kept.md"])
        XCTAssertEqual(out?.focused, 0)
        let sizes = PaneRatios.sizes(out!.ratios, total: 1000.8)
        XCTAssertEqual(sizes[0], 240, accuracy: 0.5)  // 0.2 of leftover would be under the floor
        XCTAssertEqual(sizes[1], 760, accuracy: 0.5)
    }

    func testSanitizeOneSurvivorDropsTheSplit() {
        let raw = SplitLayout(
            axis: .horizontal,
            ratios: [0.5, 0.5],
            panes: [SplitLayout.Pane(path: "Home.md"), SplitLayout.Pane(path: "Gone.md")],
            focused: 1
        )
        let out = raw.sanitized(existing: { $0 == "Home.md" }, total: 800)
        XCTAssertEqual(out?.panes.map(\.path), ["Home.md"])
        XCTAssertEqual(out?.ratios, [1])
        XCTAssertEqual(out?.focused, 0)
        XCTAssertEqual(out?.axis, .horizontal)
    }

    func testSanitizeNilWhenNothingRemains() {
        let raw = SplitLayout(
            axis: .vertical,
            ratios: [0.5, 0.5],
            panes: [SplitLayout.Pane(path: "A.md"), SplitLayout.Pane(path: nil, isGraph: true)],
            focused: 0
        )
        XCTAssertNil(raw.sanitized(existing: { _ in false }, total: 1000))
    }

    func testSanitizeSkipsAFocusedGraph() {
        let raw = SplitLayout(
            axis: .vertical,
            ratios: [0.5, 0.5],
            panes: [SplitLayout.Pane(path: "Home.md"), SplitLayout.Pane(path: nil, isGraph: true)],
            focused: 1
        )
        let out = raw.sanitized(existing: { $0 == "Home.md" }, total: 1000)
        XCTAssertEqual(out?.focused, 0)
        XCTAssertEqual(out?.panes.count, 2)
        XCTAssertEqual(out?.panes[1].isGraph, true)
    }

    func testSessionPersistenceSkipsTestAndShotHooks() {
        let notes = "/Users/kennethreitz/Notes"
        XCTAssertTrue(SessionPersistence.isEnabled(environment: [:], arguments: ["Onyx"], vaultPath: notes))
        XCTAssertFalse(SessionPersistence.isEnabled(environment: ["ONYX_SHOT_QUIET": "1"], arguments: ["Onyx"], vaultPath: notes))
        XCTAssertFalse(SessionPersistence.isEnabled(environment: ["ONYX_NO_DEFAULT_VAULT": "1"], arguments: ["Onyx"], vaultPath: notes))
        XCTAssertFalse(SessionPersistence.isEnabled(environment: ["ONYX_TYPE_TEST": "/tmp/script"], arguments: ["Onyx"], vaultPath: notes))
        XCTAssertFalse(SessionPersistence.isEnabled(environment: ["ONYX_KEY_SELFTEST": "1"], arguments: ["Onyx"], vaultPath: notes))
        XCTAssertFalse(SessionPersistence.isEnabled(environment: ["ONYX_SCROLL_TEST": "4"], arguments: ["Onyx"], vaultPath: notes))
        XCTAssertFalse(SessionPersistence.isEnabled(environment: ["ONYX_OPEN_SETTINGS": "1"], arguments: ["Onyx"], vaultPath: notes))
        XCTAssertFalse(SessionPersistence.isEnabled(environment: [:], arguments: ["Onyx", "--split", "vertical"], vaultPath: notes))
        XCTAssertFalse(SessionPersistence.isEnabled(environment: [:], arguments: ["Onyx", "--pane-ratios", "0.3,0.7"], vaultPath: notes))
        XCTAssertFalse(SessionPersistence.isEnabled(environment: [:], arguments: ["Onyx"], vaultPath: "/tmp/onyx-vault"))
        XCTAssertFalse(SessionPersistence.isEnabled(environment: [:], arguments: ["Onyx"], vaultPath: "/private/tmp/demo"))
        // --vault on a real path is fine; only /tmp vaults and hooks are skipped.
        XCTAssertTrue(SessionPersistence.isEnabled(environment: [:], arguments: ["Onyx", "--vault", notes], vaultPath: notes))
    }
}
