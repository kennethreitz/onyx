import AppKit
import SwiftUI
import OnyxCore

/// The writing room: NSTextView on TextKit 1, a centered 760px measure,
/// a warm active-line glow and a colored cursor, as in Reitz Mono.
final class OnyxTextView: NSTextView {
    // AppKit recenters the insertion point on every width change. A pane resize/split is
    // not a caret navigation; keep the viewport under the source-anchor coordinator instead.
    private var sizing = 0   // depth: AppKit nests setFrameSize calls
    override func setFrameSize(_ newSize: NSSize) {
        sizing += 1
        super.setFrameSize(newSize)
        sizing -= 1
    }
    override func scrollToVisible(_ rect: NSRect) -> Bool {
        if sizing > 0 { return false }
        return super.scrollToVisible(rect)
    }

    var noteNames: () -> [String] = { [] }
    var onFollowLink: (String) -> Void = { _ in }
    var measure: CGFloat = Theme.editorMeasure

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let lm = layoutManager, let tc = textContainer, window?.firstResponder === self else { return }
        let sel = selectedRange()
        guard sel.length == 0 else { return }
        let ns = string as NSString
        let lineRange = ns.lineRange(for: NSRange(location: min(sel.location, ns.length), length: 0))
        var glyphs = lm.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
        var r: NSRect
        if glyphs.length == 0 {
            r = lm.extraLineFragmentRect
            if r.isEmpty, sel.location > 0 { glyphs = lm.glyphRange(forCharacterRange: NSRange(location: sel.location - 1, length: 1), actualCharacterRange: nil); r = lm.boundingRect(forGlyphRange: glyphs, in: tc) }
        } else {
            r = lm.boundingRect(forGlyphRange: glyphs, in: tc)
        }
        r.origin.x = 0; r.size.width = bounds.width
        r.origin.y += textContainerOrigin.y
        Theme.activeLine.setFill()
        r.fill()
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let inset = max(36, (bounds.width - measure) / 2)
        if abs(textContainerInset.width - inset) > 0.5 {
            textContainerInset = NSSize(width: inset, height: 96)
        }
    }

    // ⌘-click follows [[links]]; plain click edits.
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let target = wikilink(at: convert(event.locationInWindow, from: nil)) {
            onFollowLink(target); return
        }
        super.mouseDown(with: event)
    }

    func wikilink(at point: NSPoint) -> String? {
        let idx = characterIndexForInsertion(at: point)
        let ns = string as NSString
        guard idx <= ns.length else { return nil }
        let lr = ns.lineRange(for: NSRange(location: min(idx, max(0, ns.length - 1)), length: 0))
        for l in NoteParser.parseWikiLinks(string, in: lr) where NSLocationInRange(idx, l.range) || NSMaxRange(l.range) == idx {
            return l.target + (l.heading.map { "#" + $0 } ?? "")
        }
        if let m = MarkdownHighlighter.url.matches(in: string, range: lr).first(where: { NSLocationInRange(idx, $0.range) }), let u = URL(string: ns.substring(with: m.range)) {
            NSWorkspace.shared.open(u); return nil
        }
        return nil
    }

    // MARK: Wikilink completion via the native completion popup

    var openLinkStart: Int? {
        let sel = selectedRange()
        guard sel.length == 0 else { return nil }
        let ns = string as NSString
        let lr = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        let before = ns.substring(with: NSRange(location: lr.location, length: sel.location - lr.location))
        guard let open = before.range(of: "[[", options: .backwards) else { return nil }
        let after = before[open.upperBound...]
        if after.contains("]") || after.contains("|") { return nil }
        return lr.location + before.utf16.distance(from: before.utf16.startIndex, to: open.upperBound.samePosition(in: before.utf16)!)
    }

    override var rangeForUserCompletion: NSRange {
        if let start = openLinkStart { return NSRange(location: start, length: selectedRange().location - start) }
        return super.rangeForUserCompletion
    }

    override func completions(forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String]? {
        guard openLinkStart != nil else { return super.completions(forPartialWordRange: charRange, indexOfSelectedItem: index) }
        let q = (string as NSString).substring(with: charRange)
        index.pointee = 0
        let names = noteNames()
        if q.isEmpty { return Array(names.prefix(40)) }
        return names.compactMap { n in Fuzzy.score(q, n).map { (n, $0) } }.sorted { $0.1 > $1.1 }.prefix(40).map(\.0)
    }

    override func insertCompletion(_ word: String, forPartialWordRange charRange: NSRange, movement: Int, isFinal flag: Bool) {
        super.insertCompletion(word, forPartialWordRange: charRange, movement: movement, isFinal: flag)
        guard flag, movement != NSCancelTextMovement, openLinkStart != nil || (string as NSString).substring(to: max(0, charRange.location)).hasSuffix("[[") else { return }
        let ns = string as NSString
        let end = selectedRange().location
        if !(end + 2 <= ns.length && ns.substring(with: NSRange(location: end, length: 2)) == "]]") {
            insertText("]]", replacementRange: selectedRange())
        } else {
            setSelectedRange(NSRange(location: end + 2, length: 0))
        }
    }

    override func didChangeText() {
        super.didChangeText()
        let sel = selectedRange()
        if sel.location >= 2, (string as NSString).substring(with: NSRange(location: sel.location - 2, length: 2)) == "[[" {
            // auto-pair and open the completion list
            insertText("]]", replacementRange: sel)
            setSelectedRange(sel)
            DispatchQueue.main.async { self.complete(nil) }
        }
    }

    override func keyDown(with event: NSEvent) {
        super.keyDown(with: event)
        if openLinkStart != nil, let c = event.characters, c.count == 1, c.rangeOfCharacter(from: .alphanumerics.union(.whitespaces)) != nil {
            complete(nil)
        }
    }
}

struct EditorView: NSViewRepresentable {
    @Bindable var ws: Workspace
    var fontSize: Double = 14
    var measure: Double = 41
    /// Set for an unfocused split pane: show this note, read-only until the pane is focused.
    var source: (path: String?, text: String)? = nil
    /// The split pane this view belongs to when unfocused (nil = the focused pane).
    var paneID: UUID? = nil
    @Environment(\.colorScheme) var scheme

    var path: String? { source == nil ? ws.currentPath : source!.path }
    var text: String { source?.text ?? ws.text }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let lm = NSLayoutManager()
        storage.addLayoutManager(lm)
        let tc = NSTextContainer(size: NSSize(width: Theme.editorMeasure, height: .greatestFiniteMagnitude))
        tc.widthTracksTextView = true
        lm.addTextContainer(tc)
        let tv = OnyxTextView(frame: .zero, textContainer: tc)
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.drawsBackground = true
        tv.backgroundColor = Theme.paper
        tv.insertionPointColor = Theme.cursor
        tv.selectedTextAttributes = [.backgroundColor: Theme.selection]
        tv.typingAttributes = MarkdownHighlighter().baseAttributes
        tv.autoresizingMask = [.width]
        tv.isVerticallyResizable = true
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        tv.textContainerInset = NSSize(width: 80, height: 96)
        tv.delegate = context.coordinator
        tv.noteNames = { [weak ws] in ws?.snapshot?.notes.values.map(\.name).sorted() ?? [] }
        tv.onFollowLink = { [weak ws] t in ws?.openLink(t) }

        let scroll = ThinScrollView()
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        ThinScroller.install(on: scroll)
        scroll.drawsBackground = true
        scroll.backgroundColor = Theme.paper
        scroll.automaticallyAdjustsContentInsets = false
        context.coordinator.textView = tv
        context.coordinator.load(text)
        context.coordinator.loadedPath = path
        tv.isEditable = source == nil
        context.coordinator.wasLive = source == nil
        if source == nil { DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) } }
        // Open where this pane was (⌘↩ from the reader, or a fresh split), then report as it scrolls.
        let c = context.coordinator
        let start = ws.initialTop(paneID)
        scroll.contentView.postsBoundsChangedNotifications = true
        scroll.onResize = { [weak c] in c?.holdAnchor() }
        c.anchor = start
        NotificationCenter.default.addObserver(c, selector: #selector(Coordinator.scrolled), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        if start > 0 {
            c.restoring = true
            c.restore(start, caret: source == nil, tries: 30)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.parent = self
        guard let tv = c.textView else { return }
        let live = source == nil
        if tv.isEditable != live { tv.isEditable = live }
        if live && !c.wasLive { DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) } }
        c.wasLive = live
        if c.loadedToken != ws.renderToken || (tv.string != text && !c.isEditing) {
            c.loadedToken = ws.renderToken
            if tv.string != text { c.load(text, keepSelection: c.loadedPath == path) }
            c.loadedPath = path
        }
        if live, let line = ws.editorJump {
            DispatchQueue.main.async { c.reveal(line: line); ws.editorJump = nil }
        }
        if c.scheme != scheme { c.scheme = scheme; c.rehighlight() }
        let tk = "\(fontSize)/\(measure)"
        if c.typeKey != tk {
            if !c.typeKey.isEmpty { c.rehighlight() }
            c.typeKey = tk
            tv.measure = Theme.editorMeasure
            tv.typingAttributes = MarkdownHighlighter().baseAttributes
            tv.needsLayout = true
        }
        if c.rhymesOn != ws.rhymesOn { c.rhymesOn = ws.rhymesOn; c.updateRhymes(force: true) }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorView
        weak var textView: OnyxTextView?
        var loadedToken = -1
        var loadedPath: String?
        var isEditing = false
        var wasLive = true
        var scheme: ColorScheme?
        var rhymesOn = false
        var typeKey = ""
        var restoring = false
        var anchor: Double = 0   // last position the writer chose (scroll or restore)
        private var reportQueued = false
        private var rhymeTask: Task<Void, Never>?
        private var highlighter: MarkdownHighlighter { MarkdownHighlighter() }

        init(_ p: EditorView) { parent = p }

        func load(_ text: String, keepSelection: Bool = false) {
            guard let tv = textView, let ts = tv.textStorage else { return }
            let sel = tv.selectedRange()
            let visible = tv.enclosingScrollView?.contentView.bounds.origin
            ts.setAttributedString(NSAttributedString(string: text, attributes: highlighter.baseAttributes))
            highlighter.apply(to: ts)
            if keepSelection {
                tv.setSelectedRange(NSRange(location: min(sel.location, (text as NSString).length), length: 0))
                if let v = visible { tv.enclosingScrollView?.contentView.scroll(to: v) }
            } else {
                tv.setSelectedRange(NSRange(location: initialCursor(text), length: 0))
                tv.scroll(.zero)
            }
            tv.undoManager?.removeAllActions()
            updateRhymes(force: true)
        }

        /// Start writing below the frontmatter and title, like opening a notebook to the page.
        func initialCursor(_ text: String) -> Int {
            (text as NSString).length
        }

        func rehighlight() {
            guard let ts = textView?.textStorage else { return }
            highlighter.apply(to: ts)
            textView?.needsDisplay = true
            updateRhymes(force: true)
        }

        /// Distance below the visible top that counts as "where you are": just under the title line.
        static let anchorY: CGFloat = 48

        private func lineStart(_ line: Int, in ns: NSString) -> Int {
            var loc = 0
            for _ in 0..<max(0, line) {
                let r = ns.lineRange(for: NSRange(location: loc, length: 0))
                if NSMaxRange(r) >= ns.length { return ns.length }
                loc = NSMaxRange(r)
            }
            return loc
        }

        /// Fractional source line at the anchor: the line index plus how far down its
        /// (possibly soft-wrapped) paragraph the anchor sits.
        func topLine() -> Double? {
            guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer,
                  let clip = tv.enclosingScrollView?.contentView else { return nil }
            let ns = tv.string as NSString
            guard ns.length > 0 else { return 0 }
            let y = clip.bounds.minY + Self.anchorY - tv.textContainerOrigin.y
            if y <= 0 { return 0 }
            let g = lm.glyphIndex(for: NSPoint(x: 0, y: y), in: tc)
            let ch = min(lm.characterIndexForGlyph(at: g), ns.length - 1)
            let lr = ns.lineRange(for: NSRange(location: ch, length: 0))
            var line = 0
            ns.enumerateSubstrings(in: NSRange(location: 0, length: lr.location), options: [.byLines, .substringNotRequired]) { _, _, _, _ in line += 1 }
            let rect = lm.boundingRect(forGlyphRange: lm.glyphRange(forCharacterRange: lr, actualCharacterRange: nil), in: tc)
            let frac = rect.height > 0 ? min(max((y - rect.minY) / rect.height, 0), 0.999) : 0
            return Double(line) + Double(frac)
        }

        func scrollTo(line: Double, caret: Bool) {
            guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer,
                  let scroll = tv.enclosingScrollView else { return }
            let ns = tv.string as NSString
            let loc = lineStart(Int(line), in: ns)
            let lr = ns.lineRange(for: NSRange(location: loc, length: 0))
            lm.ensureLayout(forCharacterRange: NSRange(location: 0, length: NSMaxRange(lr)))
            let rect = lm.boundingRect(forGlyphRange: lm.glyphRange(forCharacterRange: lr, actualCharacterRange: nil), in: tc)
            let frac = CGFloat(line - line.rounded(.down))
            let maxY = max(0, tv.frame.height - scroll.contentView.bounds.height)
            let y = min(max(0, rect.minY + frac * rect.height + tv.textContainerOrigin.y - Self.anchorY), maxY)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
            if caret { tv.setSelectedRange(NSRange(location: loc, length: 0)) }
        }

        /// Wait for the scroll view to get a real size (SwiftUI lays it out after creation).
        func restore(_ line: Double, caret: Bool, tries: Int) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { [weak self] in
                guard let self, let tv = self.textView, let clip = tv.enclosingScrollView?.contentView else { return }
                if clip.bounds.height < 1 || tv.frame.width < 1, tries > 0 { return self.restore(line, caret: caret, tries: tries - 1) }
                tv.layoutManager?.ensureLayout(for: tv.textContainer!)
                self.scrollTo(line: line, caret: caret)
                if tries > 0 { return self.restore(line, caret: false, tries: tries - 1) }
                self.restoring = false
                if let t = self.topLine() { self.parent.ws.reportTop(self.parent.paneID, t) }
            }
        }

        func holdAnchor() {
            guard anchor > 0, textView != nil else { return }
            let was = restoring
            restoring = true
            scrollTo(line: anchor, caret: false)
            restoring = was
        }

        @objc func scrolled(_ n: Notification) {
            if (textView?.enclosingScrollView as? ThinScrollView)?.resizing ?? 0 > 0 { return }
            guard !restoring, !reportQueued else { return }
            reportQueued = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.reportQueued = false
                if !self.restoring, let t = self.topLine() { self.anchor = t; self.parent.ws.reportTop(self.parent.paneID, t) }
            }
        }

        func reveal(line: Int) {
            guard let tv = textView else { return }
            let ns = tv.string as NSString
            var loc = 0
            for _ in 0..<line { let r = ns.lineRange(for: NSRange(location: loc, length: 0)); loc = NSMaxRange(r); if loc >= ns.length { break } }
            tv.setSelectedRange(NSRange(location: min(loc, ns.length), length: 0))
            tv.scrollRangeToVisible(NSRange(location: min(loc, ns.length), length: 0))
            tv.showFindIndicator(for: ns.lineRange(for: NSRange(location: min(loc, ns.length), length: 0)))
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView, let ts = tv.textStorage else { return }
            isEditing = true
            highlighter.apply(to: ts)
            if parent.source == nil { parent.ws.text = tv.string }
            isEditing = false
            updateRhymes(force: false)
        }

        // MARK: RhymePad paint (temporary attributes, never touches the text)
        func updateRhymes(force: Bool) {
            guard let tv = textView, let lm = tv.layoutManager else { return }
            rhymeTask?.cancel()
            let full = NSRange(location: 0, length: (tv.string as NSString).length)
            if !rhymesOn {
                lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
                lm.removeTemporaryAttribute(.underlineStyle, forCharacterRange: full)
                return
            }
            let text = tv.string
            let dark = tv.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            rhymeTask = Task { [weak self] in
                if !force { try? await Task.sleep(nanoseconds: 600_000_000) }
                guard !Task.isCancelled else { return }
                guard let a = await RhymeClient.analyze(text) else { self?.parent.ws.toast = "RhymePad: couldn’t reach the rhyme engine"; return }
                guard !Task.isCancelled, let self, let tv = self.textView, tv.string == text, let lm = tv.layoutManager else { return }
                let lines = RhymePad.mask(text).components(separatedBy: "\n")
                var starts: [Int] = []; var acc = 0
                for l in lines { starts.append(acc); acc += (l as NSString).length + 1 }
                lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
                lm.removeTemporaryAttribute(.underlineStyle, forCharacterRange: full)
                let palette = dark ? RhymePad.darkPalette : RhymePad.lightPalette
                for seg in RhymePad.segments(a, docLines: lines) {
                    let r = NSRange(location: starts[seg.line] + seg.start, length: seg.end - seg.start)
                    if let c = seg.color {
                        lm.addTemporaryAttribute(.backgroundColor, value: NSColor(hex: palette[c], alpha: seg.alpha * 1.4), forCharacterRange: r)
                        if seg.tail { lm.addTemporaryAttributes([.underlineStyle: NSUnderlineStyle.thick.rawValue, .underlineColor: NSColor(hex: palette[c], alpha: 0.4 + seg.tailAlpha)], forCharacterRange: r) }
                    } else if seg.near {
                        lm.addTemporaryAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue, .underlineColor: NSColor(hex: 0xc79a10)], forCharacterRange: r)
                    } else if seg.open {
                        lm.addTemporaryAttribute(.backgroundColor, value: NSColor.gray.withAlphaComponent(0.18), forCharacterRange: r)
                    }
                }
            }
        }
    }
}

enum RhymeClient {
    /// Same endpoint and settings as the obsidian-rhymepad plugin (apiBase in its data.json).
    static var apiBase: String = "https://rhymepad.org"

    static func analyze(_ text: String) async -> RhymePad.Analysis? {
        guard let url = URL(string: apiBase + "/api/analyze") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["text": RhymePad.mask(text)])
        req.timeoutInterval = 15
        guard let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(RhymePad.Analysis.self, from: data)
    }
}
