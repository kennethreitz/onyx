import XCTest
@testable import OnyxCore

final class EscPrecedenceTests: XCTestCase {
    func testQuietReadingDoesNothing() {
        XCTAssertEqual(EscPrecedence.action(EscSituation()), .none)
        XCTAssertEqual(EscPrecedence.action(EscSituation(editorFocused: true, modeIsEdit: false)), .none)
    }

    func testEditorReturnsToReadingWhenClear() {
        let s = EscSituation(editorFocused: true, modeIsEdit: true, escReturnsToReading: true)
        XCTAssertEqual(EscPrecedence.action(s), .returnToReading)
    }

    func testSettingOffDoesNotReturnToReading() {
        let s = EscSituation(editorFocused: true, modeIsEdit: true, escReturnsToReading: false)
        XCTAssertEqual(EscPrecedence.action(s), .none)
    }

    func testReadingViewNeverSwitchesToEditing() {
        let s = EscSituation(editorFocused: true, modeIsEdit: false, escReturnsToReading: true)
        XCTAssertEqual(EscPrecedence.action(s), .none)
        // Even if a selection flag were set without the editor, still not a mode flip.
        let reading = EscSituation(hasSelectionOrMultiCursor: true, modeIsEdit: false)
        XCTAssertEqual(EscPrecedence.action(reading), .none)
    }

    func testIgnoresEditorActionsWhenEditorIsNotFocused() {
        let s = EscSituation(hasSelectionOrMultiCursor: true, modeIsEdit: true, escReturnsToReading: true)
        XCTAssertEqual(EscPrecedence.action(s), .none)
    }

    func testSelectionCollapsesBeforeReturningToReading() {
        let s = EscSituation(editorFocused: true, hasSelectionOrMultiCursor: true, modeIsEdit: true)
        XCTAssertEqual(EscPrecedence.action(s), .collapseSelection)
    }

    /// Every layer above “return to reading” wins, in this exact order.
    func testPrecedenceLadder() {
        var s = EscSituation(
            sheetOrAlert: true,
            hasMarkedText: true,
            suggestionsVisible: true,
            findVisible: true,
            overlayOpen: true,
            treeSelectionConsumes: true,
            unpinnedInspector: true,
            unpinnedSidebar: true,
            inspectorVisible: true,
            focusMode: true,
            editorFocused: true,
            hasSelectionOrMultiCursor: true,
            modeIsEdit: true,
            escReturnsToReading: true
        )
        let steps: [(EscAction, (inout EscSituation) -> Void)] = [
            (.passToSheet, { $0.sheetOrAlert = false }),
            (.passToIME, { $0.hasMarkedText = false }),
            (.dismissSuggestions, { $0.suggestionsVisible = false }),
            (.closeFind, { $0.findVisible = false }),
            (.dismissOverlay, { $0.overlayOpen = false }),
            (.clearTreeSelection, { $0.treeSelectionConsumes = false }),
            (.dismissUnpinnedInspector, { $0.unpinnedInspector = false }),
            (.dismissUnpinnedSidebar, { $0.unpinnedSidebar = false }),
            (.dismissInspector, { $0.inspectorVisible = false }),
            (.leaveFocusMode, { $0.focusMode = false }),
            (.collapseSelection, { $0.hasSelectionOrMultiCursor = false }),
            (.returnToReading, { $0.modeIsEdit = false }),
            (.none, { _ in }),
        ]
        for (i, step) in steps.enumerated() {
            XCTAssertEqual(EscPrecedence.action(s), step.0, "step \(i) expected \(step.0)")
            step.1(&s)
        }
    }

    func testEachConsumerBeatsReturnToReading() {
        let base = EscSituation(editorFocused: true, modeIsEdit: true, escReturnsToReading: true)
        XCTAssertEqual(EscPrecedence.action(base), .returnToReading)

        var sheet = base; sheet.sheetOrAlert = true
        XCTAssertEqual(EscPrecedence.action(sheet), .passToSheet)

        var ime = base; ime.hasMarkedText = true
        XCTAssertEqual(EscPrecedence.action(ime), .passToIME)

        var suggest = base; suggest.suggestionsVisible = true
        XCTAssertEqual(EscPrecedence.action(suggest), .dismissSuggestions)

        var find = base; find.findVisible = true
        XCTAssertEqual(EscPrecedence.action(find), .closeFind)

        var overlay = base; overlay.overlayOpen = true
        XCTAssertEqual(EscPrecedence.action(overlay), .dismissOverlay)

        var tree = base; tree.treeSelectionConsumes = true
        XCTAssertEqual(EscPrecedence.action(tree), .clearTreeSelection)

        var insp = base; insp.inspectorVisible = true
        XCTAssertEqual(EscPrecedence.action(insp), .dismissInspector)

        var focus = base; focus.focusMode = true
        XCTAssertEqual(EscPrecedence.action(focus), .leaveFocusMode)
    }

    func testSheetBeatsFindSoAlertsKeepEsc() {
        let s = EscSituation(sheetOrAlert: true, findVisible: true, editorFocused: true, modeIsEdit: true)
        XCTAssertEqual(EscPrecedence.action(s), .passToSheet)
    }

    func testSuggestionsBeatFind() {
        let s = EscSituation(suggestionsVisible: true, findVisible: true, editorFocused: true, modeIsEdit: true)
        XCTAssertEqual(EscPrecedence.action(s), .dismissSuggestions)
    }

    func testOverlayBeatsTreeSelection() {
        let s = EscSituation(overlayOpen: true, treeSelectionConsumes: true)
        XCTAssertEqual(EscPrecedence.action(s), .dismissOverlay)
    }
}
