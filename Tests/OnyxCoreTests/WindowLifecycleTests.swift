import XCTest
@testable import OnyxCore

final class WindowLifecycleTests: XCTestCase {
    func testClosingTheLastWindowDoesNotQuit() {
        XCTAssertFalse(WindowLifecycle.terminateAfterLastWindowClosed)
    }

    func testClassifiesWindows() {
        XCTAssertEqual(WindowLifecycle.kind(isPanel: true, identifier: "main", title: "Onyx"), .panel)
        XCTAssertEqual(WindowLifecycle.kind(isPanel: false, identifier: "main", title: "Onyx"), .vault)
        XCTAssertEqual(WindowLifecycle.kind(isPanel: false, identifier: "onyx-settings", title: ""), .settings)
        XCTAssertEqual(WindowLifecycle.kind(isPanel: false, identifier: nil, title: "Settings"), .settings)
        XCTAssertEqual(WindowLifecycle.kind(isPanel: false, identifier: nil, title: "Editor Settings"), .settings)
        XCTAssertEqual(WindowLifecycle.kind(isPanel: false, identifier: nil, title: "Onyx Update"), .update)
        XCTAssertEqual(WindowLifecycle.kind(isPanel: false, identifier: nil, title: "Untitled"), .other)
    }

    func testClosingTheVaultWindowSavesAndStopsPlaybackButKeepsSync() {
        let plan = WindowLifecycle.closePlan(kind: .vault, isQuit: false)
        XCTAssertEqual(plan, .window)
        XCTAssertTrue(plan.flushUnsavedNotes)
        XCTAssertTrue(plan.persistSplitLayout)
        XCTAssertTrue(plan.stopSpeech)
        XCTAssertTrue(plan.stopAudioPlayback)
        XCTAssertTrue(plan.finishRecording)
        XCTAssertFalse(plan.stopObsidianSync)
        XCTAssertFalse(plan.finishGitForQuit)
    }

    func testClosingSettingsOrUpdateDoesNotFlushSession() {
        XCTAssertEqual(WindowLifecycle.closePlan(kind: .settings, isQuit: false), .none)
        XCTAssertEqual(WindowLifecycle.closePlan(kind: .update, isQuit: false), .none)
        XCTAssertEqual(WindowLifecycle.closePlan(kind: .panel, isQuit: false), .none)
    }

    func testQuitStillFlushesAndStopsSync() {
        let plan = WindowLifecycle.closePlan(kind: .vault, isQuit: true)
        XCTAssertEqual(plan, .quit)
        XCTAssertTrue(plan.stopObsidianSync)
        XCTAssertTrue(plan.finishGitForQuit)
        // Quit with no vault window still does the terminate work.
        XCTAssertEqual(WindowLifecycle.closePlan(kind: .other, isQuit: true), .quit)
    }

    func testReopenFocusesAnExistingWindowOtherwiseOpensOne() {
        XCTAssertEqual(WindowLifecycle.reopenPlan(hasVaultWindow: true), .focusExisting)
        XCTAssertEqual(WindowLifecycle.reopenPlan(hasVaultWindow: false), .openNew)
    }
}
