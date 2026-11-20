import AppKit
import WebKit
import SwiftUI
import OnyxCore

/// One row in the `[[` popup.
struct LinkSuggestion: Identifiable {
    let id: Int
    var title: String
    var detail: String = ""          // folder, faint
    var titleHits: [Int] = []
    var insert: String               // what replaces the typed part on accept
    var exact = false
}

@Observable final class LinkSuggestModel {
    var items: [LinkSuggestion] = []
    var highlighted: Int?
    @ObservationIgnored var onPick: (Int) -> Void = { _ in }
}

/// A floating list that never takes focus: the text view keeps every keystroke.
final class LinkSuggestPanel: NSPanel {
    let model = LinkSuggestModel()
    static let rowHeight: CGFloat = 28, width: CGFloat = 340, maxRows = 8

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 100),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        hidesOnDeactivate = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        level = .popUpMenu
        let host = FirstMouseHostingView(rootView: LinkSuggestList(model: model))
        host.frame = NSRect(x: 0, y: 0, width: Self.width, height: 100)
        host.autoresizingMask = [.width, .height]
        contentView = host
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Place the list under (or, near the screen bottom, over) `anchor`, a screen rect.
    func show(below anchor: NSRect, parent: NSWindow) {
        let rows = min(model.items.count, Self.maxRows)
        let h = CGFloat(rows) * Self.rowHeight + 10
        let screen = parent.screen?.visibleFrame ?? .infinite
        var origin = NSPoint(x: anchor.minX - 10, y: anchor.minY - 4 - h)
        if origin.y < screen.minY { origin.y = anchor.maxY + 4 }
        origin.x = min(max(origin.x, screen.minX + 4), screen.maxX - Self.width - 4)
        setFrame(NSRect(origin: origin, size: NSSize(width: Self.width, height: h)), display: true)
        if parent.childWindows?.contains(self) != true { parent.addChildWindow(self, ordered: .above) }
        orderFront(nil)
    }
    func hide() {
        guard isVisible else { return }
        parent?.removeChildWindow(self)
        orderOut(nil)
    }
}

private final class FirstMouseHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct LinkSuggestList: View {
    @Bindable var model: LinkSuggestModel
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(model.items.enumerated()), id: \.offset) { i, s in
                        row(s, on: model.highlighted == i)
                            .id(i)
                            .contentShape(Rectangle())
                            .onTapGesture { model.onPick(i) }
                    }
                }.padding(5)
            }
            .onChange(of: model.highlighted) { if let h = model.highlighted { proxy.scrollTo(h) } }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.paper))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.hairline))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    func row(_ s: LinkSuggestion, on: Bool) -> some View {
        HStack(spacing: 8) {
            highlighted(s.title, s.titleHits).font(.system(size: 12.5)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 6)
            if !s.detail.isEmpty {
                Text(s.detail).font(.system(size: 10.5)).foregroundStyle(Color.faint).lineLimit(1).truncationMode(.head)
            }
        }
        .padding(.horizontal, 9).frame(height: LinkSuggestPanel.rowHeight)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.ink.opacity(on ? 0.075 : 0)))
    }
    func highlighted(_ t: String, _ hits: [Int]) -> Text {
        guard !hits.isEmpty else { return Text(t).foregroundColor(Color.ink) }
        let set = Set(hits)
        var out = Text("")
        for (i, ch) in t.enumerated() {
            let piece = Text(String(ch))
            out = out + (set.contains(i) ? piece.foregroundColor(Color.ink).fontWeight(.semibold) : piece.foregroundColor(Color.muted))
        }
        return out
    }
}

/// Test hook: ONYX_TYPE_TEST=<script file> types into the editor in-process (the test window
/// can't become key without stealing focus). Lines: `type <text>`, `key <code> [cmd|shift|opt]`,
/// `wait <seconds>`, `dump` (prints the note text). Never set in normal use.
enum TypeSelfTest {
    @MainActor static weak var ws: Workspace?
    @MainActor static func scheduleIfRequested() {
        guard let f = ProcessInfo.processInfo.environment["ONYX_TYPE_TEST"],
              let script = try? String(contentsOfFile: f, encoding: .utf8) else { return }
        var t = 5.0
        for raw in script.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw)
            if line.hasPrefix("#") { continue }
            if line.hasPrefix("wait ") { t += Double(line.dropFirst(5)) ?? 0.5; continue }
            let at = t
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { run(line) }
            t += line.hasPrefix("type ") ? 0.05 * Double(line.count) + 0.3 : 0.3
        }
    }
    /// `open <path>`, `split`, `back`, `trash <path>` (no confirm), `state`.
    @MainActor static func workspaceCommand(_ line: String, _ ws: Workspace) -> Bool {
        let arg = line.split(separator: " ", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
        switch line.split(separator: " ").first ?? "" {
        case "open": ws.openNote(arg)
        case "split": ws.split(.vertical)
        case "back": ws.goBack()
        case "trash": ws.trash(arg)
        case "move":     // move <path> -> <folder>
            let parts = arg.components(separatedBy: " -> "); if parts.count == 2 { ws.move(parts[0], toFolder: parts[1]) }
        case "rename":   // rename <path> -> <new path>
            let parts = arg.components(separatedBy: " -> "); if parts.count == 2 { ws.relocate(parts[0], to: parts[1], reason: "Rename \((parts[0] as NSString).lastPathComponent) → \((parts[1] as NSString).lastPathComponent)") }
        case "cat":
            if let r = ws.root, let t = try? String(contentsOf: r.appendingPathComponent(arg), encoding: .utf8) { print("[cat] \(arg): " + t.replacingOccurrences(of: "\n", with: " ⏎ ")) } else { print("[cat] \(arg): (missing)") }
        case "click", "shiftclick", "cmdclick":   // tree clicks through the same path as the view
            let m: NSEvent.ModifierFlags = line.hasPrefix("shift") ? .shift : line.hasPrefix("cmd") ? .command : []
            ws.treeClick(arg, modifiers: m) { if arg.lowercased().hasSuffix(".md") || arg.isCanvasPath { ws.openNote(arg) } }
        case "expand": ws.expanded.insert(arg)
        case "sel": print("[sel] \(TreeSelection.roots(ws.treeSelection.selected)) anchor=\(ws.treeSelection.anchor ?? "-") current=\(ws.currentPath ?? "-") targets(\(arg))=\(ws.targets(for: arg))")
        case "esc": print("[esc] cleared=\(ws.clearTreeSelection())")
        case "trashsel": ws.trash(Array(ws.treeSelection.selected))       // what ⌘⌫ does after its confirm
        case "movesel": ws.move(Array(ws.treeSelection.selected), toFolder: arg)
        case "relations":
            if let snap = ws.snapshot { print("[relations] \(arg): parents=\(snap.parents(of: arg)) parts=\(snap.parts(of: arg)) related=\(snap.related(to: arg)) backlinks=\(snap.backlinks[arg]?.count ?? 0)") }
        case "preview":   // the same card a 400 ms hover opens, anchored to the window
            if let v = MainWindow.current?.contentView { GraphPreviewController.shared.show(ws: ws, path: arg, rect: CGRect(x: v.bounds.midX - 40, y: v.bounds.maxY - 120, width: 80, height: 20), in: v); print("[preview] shown=\(GraphPreviewController.shared.shownPath ?? "-")") }
        case "hoverbtn":   // what hovering the title-bar graph button does: schedule (400 ms) for the current note
            func find(_ v: NSView) -> GraphPreviewTrigger.TriggerView? { if let t = v as? GraphPreviewTrigger.TriggerView, t.path == ws.currentPath { return t }; for s in v.subviews { if let r = find(s) { return r } }; return nil }
            if let t = MainWindow.current?.contentView.flatMap(find) {
                GraphPreviewController.shared.schedule(ws: ws, path: t.path, rect: t.bounds, in: t)
                print("[hoverbtn] scheduled \(t.path) now=\(GraphPreviewController.shared.shownPath ?? "-")")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { print("[hoverbtn] after 600ms shown=\(GraphPreviewController.shared.shownPath ?? "-")"); fflush(stdout) }
            } else { print("[hoverbtn] no trigger") }
        case "previewmode": print("[preview] shown=\(GraphPreviewController.shared.shownPath ?? "-") mode=\(GraphPreviewController.shared.shownMode.rawValue) linkMode=\(GraphPreviewController.linkMode.rawValue)")
        case "linkpreview":   // what a reader link hover does after 400 ms (remembered mode)
            if let v = MainWindow.current?.contentView { GraphPreviewController.shared.show(ws: ws, path: arg, rect: CGRect(x: v.bounds.midX - 40, y: v.bounds.maxY - 120, width: 80, height: 20), in: v, mode: nil); print("[preview] shown=\(GraphPreviewController.shared.shownPath ?? "-") mode=\(GraphPreviewController.shared.shownMode.rawValue)") }
        case "previewshot":   // previewshot <png>: only the popover's own window
            if let w = GraphPreviewController.shared.popoverWindow {
                let t = Process(); t.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); t.arguments = ["-x", "-o", "-l", String(w.windowNumber), arg]
                try? t.run(); t.waitUntilExit(); print("[previewshot] \(arg)")
            } else { print("[previewshot] no popover") }
        case "edhover":   // edhover <link text>: ⌘-hover the first [[link]] containing it in the editor
            if let tv = editor(), let lm = tv.layoutManager, let tc = tv.textContainer {
                let r = (tv.string as NSString).range(of: "[[" + arg)
                if r.location != NSNotFound {
                    tv.scrollRangeToVisible(r)
                    var b = lm.boundingRect(forGlyphRange: lm.glyphRange(forCharacterRange: NSRange(location: r.location + 3, length: 1), actualCharacterRange: nil), in: tc)
                    b.origin.x += tv.textContainerOrigin.x; b.origin.y += tv.textContainerOrigin.y
                    tv.previewHover(.command, at: NSPoint(x: b.midX, y: b.midY))
                    tv.previewHover([], at: NSPoint(x: b.midX, y: b.midY)); tv.previewHover(.command, at: NSPoint(x: b.midX, y: b.midY))   // release and press again: same link, one schedule
                    print("[edhover] \(arg) at \(Int(b.midX)),\(Int(b.midY))")
                } else { print("[edhover] not found") }
            }
        case "find": ws.openFind(); ws.finder.query = arg; DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { print("[find] \(findState(ws))"); fflush(stdout) }
        case "findstate": print("[find] \(findState(ws))")
        case "findnext": ws.findStep(1); print("[find] \(findState(ws))")
        case "findprev": ws.findStep(-1); print("[find] \(findState(ws))")
        case "findcase": ws.finder.caseSensitive.toggle(); ws.runFind(reveal: false, fromCaret: false); print("[find] \(findState(ws))")
        case "findrep": ws.finder.showReplace = true; ws.finder.replacement = arg; ws.replaceCurrent(); print("[find] \(findState(ws))")
        case "findall": ws.finder.showReplace = true; ws.finder.replacement = arg; print("[findall] replaced=\(ws.replaceAll()) \(findState(ws))")
        case "findclose": ws.closeFind(); print("[find] \(findState(ws))")
        case "undo": ws.liveEditor?.undoManager?.undo(); print("[undo] done")
        case "keyev":   // keyev cmd-g | shift-cmd-g | esc | cmd-f | opt-cmd-f | return | shift-return: through the app's key monitor
            var f: NSEvent.ModifierFlags = []
            if arg.contains("cmd") { f.insert(.command) }; if arg.contains("shift") { f.insert(.shift) }; if arg.contains("opt") { f.insert(.option) }
            let (ch, code): (String, UInt16) = arg.hasSuffix("esc") ? ("\u{1b}", 53) : arg.hasSuffix("return") ? ("\r", 36) : arg.hasSuffix("-g") ? ("g", 5) : ("f", 3)
            if let w = MainWindow.current, let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: f, timestamp: ProcessInfo.processInfo.systemUptime,
                                                                     windowNumber: w.windowNumber, context: nil, characters: ch, charactersIgnoringModifiers: ch, isARepeat: false, keyCode: code) {
                NSApp.postEvent(e, atStart: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { print("[keyev] \(arg) → \(findState(ws)) overlay=\(ws.overlay)"); fflush(stdout) }
            }
        case "previewclose": GraphPreviewController.shared.close(); print("[preview] shown=\(GraphPreviewController.shared.shownPath ?? "-")")
        case "cardshot":   // cardshot <note> -> <png>: renders only the card, never the screen
            let parts = arg.components(separatedBy: " -> ")
            if parts.count == 2, let snap = ws.snapshot {
                let r = ImageRenderer(content: GraphPreviewCard(graph: RelationGraph.build(snap, center: parts[0]), path: parts[0], open: { _ in }, hover: { _ in }))
                r.scale = 2
                if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: parts[1])); print("[cardshot] \(parts[1])")
                }
            }
        case "js":   // evaluate in the reader and print the result
            func find(_ v: NSView) -> WKWebView? { if let w = v as? WKWebView { return w }; for s in v.subviews { if let r = find(s) { return r } }; return nil }
            if let w = MainWindow.current?.contentView.flatMap(find) {
                w.evaluateJavaScript(arg) { r, e in print("[js] \(r.map { "\($0)" } ?? e.map { "error \($0)" } ?? "nil")"); fflush(stdout) }
            } else { print("[js] no reader") }
        case "sort":   // sort name|modified|created [asc|desc] [nofolders] [in <folder>]
            let w = arg.components(separatedBy: " in ")
            let words = w[0].split(separator: " ").map(String.init)
            if let k = words.first.flatMap(TreeSort.Key.init(rawValue:)) {
                var s = TreeSort(key: k, foldersFirst: !words.contains("nofolders"))
                if words.contains("asc") { s.ascending = true } else if words.contains("desc") { s.ascending = false }
                ws.setSort(s, folder: w.count > 1 ? w[1] : nil)
            }
        case "rows": print("[rows] \(ws.visibleTreePaths())")
        case "sortsaved": print("[sortsaved] \(UserDefaults.standard.data(forKey: "onyx.\(ws.root?.path ?? "").treeSort").map { String(decoding: $0, as: UTF8.self) } ?? "-")")
        case "graphpane": ws.openGraphPane(atlas: arg == "atlas")
        case "closegraph": ws.closeGraphPane()
        case "closepane": print("[closepane] \(ws.closePane())")
        case "nextpane": ws.focusNextPane()
        case "panes": print("[panes] \(ws.panes.map { $0.isGraph ? "graph" : ($0.path ?? "-") }) focused=\(ws.focusedPane) current=\(ws.currentPath ?? "-") overlay=\(ws.overlay) atlas=\(ws.graphAtlas)")
        case "webshot":   // webshot <png>: the page as the web view draws it (reader or canvas)
            func find(_ v: NSView) -> WKWebView? { if let w = v as? WKWebView { return w }; for s in v.subviews { if let r = find(s) { return r } }; return nil }
            if let w = MainWindow.current?.contentView.flatMap(find) {
                w.takeSnapshot(with: nil) { img, e in
                    if let img, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: arg)); print("[webshot] \(arg)")
                    } else { print("[webshot] failed \(e.map { "\($0)" } ?? "")") }
                    fflush(stdout)
                }
            } else { print("[webshot] no web view") }
        case "mode": ws.mode = arg == "edit" ? .edit : .read
        case "git": print("[git] \(ws.git.map { "\($0.state) · \($0.detail) · last=\($0.lastCommit ?? "-")" } ?? "no git")")
        case "state":
            let h = ws.debugHistory
            print("[state] current=\(ws.currentPath ?? "-") history=\(h) panes=\(ws.panes.map { $0.path ?? "-" }) focused=\(ws.focusedPane) recent0=\(ws.recent.first ?? "-")")
        default: return false
        }
        return true
    }
    @MainActor static func findState(_ ws: Workspace) -> String {
        let sel = ws.liveEditor.map { tv -> String in let r = tv.selectedRange(); return "sel=\(r.location)+\(r.length)" } ?? "sel=-"
        return "visible=\(ws.finder.visible) q=\(ws.finder.query) \(ws.finder.count == 0 ? "0" : "\(ws.finder.index + 1)/\(ws.finder.count)") mode=\(ws.mode) \(sel) painted=\(ws.finder.painted.count) field=\(ws.finder.fieldFocused)"
    }
    @MainActor static func editor() -> OnyxTextView? {
        func find(_ v: NSView) -> OnyxTextView? {
            if let t = v as? OnyxTextView, t.isEditable { return t }
            for s in v.subviews { if let r = find(s) { return r } }
            return nil
        }
        return MainWindow.current?.contentView.flatMap(find)
    }
    @MainActor static func send(_ tv: OnyxTextView, chars: String, code: UInt16, flags: NSEvent.ModifierFlags = []) {
        guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: tv.window?.windowNumber ?? 0, context: nil, characters: chars,
                                       charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code) else { return }
        tv.keyDown(with: e)
    }
    @MainActor static func run(_ line: String) {
        if let ws, workspaceCommand(line, ws) { fflush(stdout); return }
        guard let tv = editor() else { print("[type] no editor"); return }
        tv.directKeys = true
        if line.hasPrefix("type ") {
            for ch in line.dropFirst(5) { send(tv, chars: String(ch), code: 0) }
        } else if line.hasPrefix("key ") {
            let p = line.split(separator: " ")
            let code = UInt16(p[1]) ?? 0
            var f: NSEvent.ModifierFlags = []
            for m in p.dropFirst(2) { switch m { case "cmd": f.insert(.command); case "shift": f.insert(.shift); case "opt": f.insert(.option); default: break } }
            let chars: String = switch code {
                case 36: "\r"; case 48: "\t"; case 53: "\u{1b}"
                case 125: String(UnicodeScalar(NSDownArrowFunctionKey)!); case 126: String(UnicodeScalar(NSUpArrowFunctionKey)!)
                case 123: String(UnicodeScalar(NSLeftArrowFunctionKey)!); case 124: String(UnicodeScalar(NSRightArrowFunctionKey)!)
                default: ""
            }
            send(tv, chars: chars, code: code, flags: f)
        } else if line == "dump" {
            let sel = tv.selectedRange().location
            let s = tv.string as NSString
            let lr = s.lineRange(for: NSRange(location: min(sel, s.length), length: 0))
            let line = s.substring(with: lr).trimmingCharacters(in: .newlines) as NSString
            let marked = line.replacingCharacters(in: NSRange(location: min(sel - lr.location, line.length), length: 0), with: "¦")
            print("[type] \(marked)   popup=\(tv.suggestionsVisible)")
        }
        fflush(stdout)
    }
}
