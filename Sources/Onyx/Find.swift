import SwiftUI
import AppKit
import OnyxCore

/// ⌘F: find in the current note, in the editor and the reader alike. ⌥⌘F adds replace (editor).
/// While the bar is open ⌘G / ⇧⌘G step through matches (as in every Mac app); with it closed
/// ⌘G stays Focus graph. Return / ⇧Return in the field step too, and Esc closes the bar.
@Observable final class FindModel {
    var visible = false
    var query = ""
    var replacement = ""
    var showReplace = false
    var caseSensitive = false
    var count = 0
    var index = 0            // the current match, 0-based
    var focusToken = 0       // bump to focus (and select) the find field
    var fieldFocused = false
    var findFieldActive = false   // the find field (not replace) has focus: ↩ steps, in replace ↩ replaces
    @ObservationIgnored var editorRanges: [NSRange] = []
    @ObservationIgnored var painted: [NSRange] = []
    @ObservationIgnored weak var paintedIn: NSLayoutManager?
}

@MainActor
extension Workspace {
    var findInEditor: Bool { mode == .edit }

    func openFind(replace: Bool = false) {
        if replace && findInEditor { finder.showReplace = true }
        if let tv = liveEditor, findInEditor, tv.selectedRange().length > 0, tv.selectedRange().length < 200 {
            let sel = (tv.string as NSString).substring(with: tv.selectedRange())
            if !sel.contains("\n") { finder.query = sel }
        }
        finder.visible = true
        finder.focusToken += 1
        runFind(reveal: false)
    }

    func closeFind() {
        guard finder.visible else { return }
        finder.visible = false
        finder.showReplace = false
        clearEditorFind()
        liveReader?.eval("Onyx.findClear()")
        if findInEditor, let tv = liveEditor { tv.window?.makeFirstResponder(tv) }
    }

    /// Recount and repaint; `reveal` also selects/scrolls to the current match.
    func runFind(reveal: Bool, fromCaret: Bool = true) {
        guard finder.visible else { return }
        if findInEditor {
            liveReader?.eval("Onyx.findClear()")
            guard let tv = liveEditor else { finder.count = 0; return }
            let rs = FindText.ranges(of: finder.query, in: tv.string, caseSensitive: finder.caseSensitive)
            finder.editorRanges = rs
            finder.count = rs.count
            if fromCaret {   // a new query starts at the caret
                let caret = tv.selectedRange().location
                finder.index = rs.firstIndex { $0.location >= caret } ?? 0
            }
            if finder.index >= rs.count { finder.index = 0 }
            paintEditor(tv)
            if reveal, finder.index < rs.count {
                let r = rs[finder.index]
                tv.setSelectedRange(r)
                tv.scrollRangeToVisible(r)
                tv.showFindIndicator(for: r)
            }
        } else {
            clearEditorFind()
            let q = jsString(finder.query)
            liveReader?.evalResult("Onyx.find(\(q), \(finder.caseSensitive), \(finder.index), \(reveal))") { [weak self] v in
                guard let self, let d = v as? [String: Any] else { return }
                self.finder.count = (d["count"] as? Int) ?? 0
                self.finder.index = (d["index"] as? Int) ?? 0
            }
        }
    }

    func findStep(_ delta: Int) {
        guard finder.visible else { return }
        if finder.count > 0 { finder.index = ((finder.index + delta) % finder.count + finder.count) % finder.count }
        runFind(reveal: true, fromCaret: false)
    }

    func replaceCurrent() {
        guard findInEditor, let tv = liveEditor, tv.isEditable, finder.index < finder.editorRanges.count else { return }
        let r = finder.editorRanges[finder.index]
        let rep = finder.replacement
        guard tv.shouldChangeText(in: r, replacementString: rep) else { return }
        tv.replaceCharacters(in: r, with: rep)
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: r.location + (rep as NSString).length, length: 0))
        let keep = finder.index
        runFind(reveal: false, fromCaret: false)
        finder.index = finder.count == 0 ? 0 : min(keep, finder.count - 1)
        runFind(reveal: finder.count > 0, fromCaret: false)
    }

    @discardableResult
    func replaceAll() -> Int {
        guard findInEditor, let tv = liveEditor, tv.isEditable, let ts = tv.textStorage else { return 0 }
        let rs = FindText.ranges(of: finder.query, in: tv.string, caseSensitive: finder.caseSensitive)
        guard !rs.isEmpty else { return 0 }
        let reps = Array(repeating: finder.replacement, count: rs.count)
        guard tv.shouldChangeText(inRanges: rs.map { NSValue(range: $0) }, replacementStrings: reps) else { return 0 }
        ts.beginEditing()
        for r in rs.reversed() { ts.replaceCharacters(in: r, with: finder.replacement) }
        ts.endEditing()
        tv.didChangeText()   // one undo step for the lot
        finder.index = 0
        runFind(reveal: false, fromCaret: false)
        return rs.count
    }

    func paintEditor(_ tv: OnyxTextView) {
        clearEditorFind()
        guard let lm = tv.layoutManager else { return }
        let len = (tv.string as NSString).length
        for (i, r) in finder.editorRanges.enumerated() where NSMaxRange(r) <= len {
            lm.addTemporaryAttribute(.backgroundColor, value: i == finder.index ? Theme.findCurrent : Theme.findMatch, forCharacterRange: r)
        }
        finder.painted = finder.editorRanges
        finder.paintedIn = lm
    }

    func clearEditorFind() {
        guard let lm = finder.paintedIn else { finder.painted = []; return }
        let len = lm.textStorage?.length ?? 0
        for r in finder.painted where NSMaxRange(r) <= len { lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: r) }
        finder.painted = []
        finder.paintedIn = nil
    }

    func jsString(_ s: String) -> String {
        let d = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
        return String(decoding: d, as: UTF8.self).dropFirst().dropLast().description
    }
}

struct FindBar: View {
    var ws: Workspace
    @Bindable var finder: FindModel
    init(ws: Workspace) { self.ws = ws; self.finder = ws.finder }
    @FocusState private var field: Field?
    enum Field { case find, replace }

    var status: String {
        if ws.finder.query.isEmpty { return "" }
        return ws.finder.count == 0 ? "No results" : "\(ws.finder.index + 1) of \(ws.finder.count)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Color.faint)
                TextField("Find in note", text: $finder.query)
                    .textFieldStyle(.plain).font(.system(size: 12.5)).frame(width: 190)
                    .focused($field, equals: .find)
                    .onSubmit { ws.findStep(1) }
                Text(status).font(.system(size: 10.5).monospacedDigit()).foregroundStyle(ws.finder.count == 0 && !ws.finder.query.isEmpty ? Color.red.opacity(0.7) : Color.faint)
                    .frame(minWidth: 58, alignment: .trailing)
                iconButton("chevron.up", "Previous match (⇧⌘G · ⇧↩)") { ws.findStep(-1) }
                iconButton("chevron.down", "Next match (⌘G · ↩)") { ws.findStep(1) }
                Button { ws.finder.caseSensitive.toggle(); ws.runFind(reveal: false, fromCaret: false) } label: {
                    Text("Aa").font(.system(size: 11, weight: ws.finder.caseSensitive ? .bold : .regular))
                        .foregroundStyle(ws.finder.caseSensitive ? Color.ink : Color.faint).frame(width: 22, height: 18)
                }.buttonStyle(.plain).help("Match case")
                if ws.findInEditor {
                    iconButton(ws.finder.showReplace ? "arrow.left.arrow.right.circle.fill" : "arrow.left.arrow.right", "Replace (⌥⌘F)") { ws.finder.showReplace.toggle() }
                }
                iconButton("xmark", "Close (Esc)") { ws.closeFind() }
            }
            if ws.finder.showReplace && ws.findInEditor {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right").font(.system(size: 10)).foregroundStyle(Color.faint)
                    TextField("Replace with", text: $finder.replacement)
                        .textFieldStyle(.plain).font(.system(size: 12.5)).frame(width: 190)
                        .focused($field, equals: .replace)
                        .onSubmit { ws.replaceCurrent() }
                    Button("Replace") { ws.replaceCurrent() }.controlSize(.small).disabled(ws.finder.count == 0)
                    Button("All") { ws.replaceAll() }.controlSize(.small).disabled(ws.finder.count == 0)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color.paper, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.hairline, lineWidth: 0.8))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .onAppear { field = .find }
        .onChange(of: ws.finder.focusToken) { field = .find; DispatchQueue.main.async { NSApp.keyWindow?.firstResponder.flatMap { $0 as? NSTextView }?.selectAll(nil) } }
        .onChange(of: ws.finder.query) { ws.finder.index = 0; ws.runFind(reveal: true) }
        .onChange(of: field) { ws.finder.fieldFocused = field != nil; ws.finder.findFieldActive = field == .find }
        .onDisappear { ws.finder.fieldFocused = false; ws.finder.findFieldActive = false }
    }

    func iconButton(_ name: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 10.5)).foregroundStyle(Color.muted).frame(width: 20, height: 18).contentShape(Rectangle())
        }.buttonStyle(.plain).help(help)
    }
}
