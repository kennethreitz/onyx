import AppKit
import OnyxCore

/// Fold commands for the palette, the View ▸ Folding menu, and Settings ▸ Shortcuts. In the
/// editor they act at the caret; in the reader, on the section you're reading.
extension Workspace {
    static let foldMenu = ["fold", "unfold", "togglefold", "foldall", "unfoldall"]

    var foldStore: FoldStore? { FoldStores.store(for: root) }

    func runFold(_ id: String) {
        guard currentPath != nil, !isCanvas, !isBase else { NSSound.beep(); return }
        if mode == .edit, let tv = (MainWindow.current?.firstResponder as? OnyxTextView) ?? liveEditor {
            let f = tv.folds
            var ok = true
            switch id {
            case "fold": ok = f.foldCurrent()
            case "unfold": ok = f.unfoldCurrent()
            case "togglefold": ok = f.toggleCurrent()
            case "foldall": f.foldAll()
            case "unfoldall": f.unfoldAll()
            default: ok = false
            }
            if !ok { NSSound.beep() }
        } else if let r = liveReader {
            r.eval("Onyx.foldCommand('\(id)')")
        }
    }

    /// The editor changed a note's folds: a live reader of the same note mirrors them.
    func editorFoldsChanged(_ path: String) {
        liveReader?.pushFolds(for: path)
    }

    /// The reader folded or opened headings (source lines). List folds are kept as they were.
    func setReaderFolds(path: String, text: String, lines: [Int]) {
        guard let store = foldStore, EditorPrefs.foldKinds.contains(.heading) else { return }
        let want = Set(lines)
        let heads = MarkdownFolds.regions(in: text).filter { $0.kind == .heading }
        var a = store.anchors(for: path).filter { !$0.signature.hasPrefix("heading:") }
        a.formUnion(heads.filter { want.contains($0.line) }.map(\.anchor))
        store.set(a, for: path)
        if let tv = liveEditor, tv.folds.path == path { tv.folds.reloadFromStore() }
    }

    /// Settings ▸ Editor ▸ Folding changed: every open editor re-reads its folds.
    static func applyFoldPrefs() {
        for w in NSApp.windows {
            guard let root = w.contentView else { continue }
            var stack: [NSView] = [root]
            while let v = stack.popLast() {
                if let tv = v as? OnyxTextView { tv.folds.prefsChanged() }
                stack.append(contentsOf: v.subviews)
            }
        }
    }
}
