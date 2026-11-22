import AppKit
import OnyxCore

extension EditorPrefs {
    static let foldHeadings = "onyx.fold.headings"   // Settings ▸ Editor ▸ Fold headings; default on
    static let foldLists = "onyx.fold.lists"         // Settings ▸ Editor ▸ Fold indent; default on
    static var foldKinds: Set<FoldRegion.Kind> {
        var k: Set<FoldRegion.Kind> = []
        if UserDefaults.standard.object(forKey: foldHeadings) as? Bool ?? true { k.insert(.heading) }
        if UserDefaults.standard.object(forKey: foldLists) as? Bool ?? true { k.insert(.list) }
        return k
    }
}

/// One FoldStore per vault (folds are local view state, like Obsidian's; never in the note).
enum FoldStores {
    @MainActor private static var cache: [String: FoldStore] = [:]
    @MainActor static func store(for root: URL?) -> FoldStore? {
        guard let root else { return nil }
        if let s = cache[root.path] { return s }
        let s = FoldStore(vault: root.path); cache[root.path] = s; return s
    }
}

/// Folding for one editor. The text storage is never touched: FoldLayoutManager turns the
/// folded characters into null glyphs, so save, sync, undo, find, copy, and completion all
/// see the full note. This object decides *which* regions are folded and keeps carets out.
@MainActor
final class EditorFolds {
    weak var tv: OnyxTextView?
    private(set) var path: String?
    private var store: FoldStore?
    /// The note's fold state changed (the reader of the same note mirrors it).
    var onChange: ((String) -> Void)?
    private(set) var folded = Set<FoldAnchor>()
    private var preserved = Set<FoldAnchor>()   // stored folds of a kind that's switched off
    private var cached: [FoldRegion]?
    private var kinds = EditorPrefs.foldKinds
    var loading = false
    var hover: Int?            // header location of the region under the mouse
    var hoverPart: Part?
    enum Part { case chevron, ellipsis }

    var lm: FoldLayoutManager? { tv?.layoutManager as? FoldLayoutManager }
    var isActive: Bool { !(lm?.hiddenRanges.isEmpty ?? true) }

    func attach(_ tv: OnyxTextView) {
        self.tv = tv
        lm?.onEdit = { [weak self] edit, delta in
            MainActor.assumeIsolated { self?.storageEdited(edit, delta) }
        }
    }

    var regions: [FoldRegion] {
        if let c = cached { return c }
        guard let tv, !kinds.isEmpty else { cached = []; return [] }
        let r = MarkdownFolds.regions(in: tv.string).filter { kinds.contains($0.kind) }
        cached = r
        return r
    }

    private var foldedRegions: [FoldRegion] { folded.isEmpty ? [] : regions.filter { folded.contains($0.anchor) } }

    private func storageEdited(_ edit: NSRange, _ delta: Int) -> [NSRange]? {
        let old = cached
        cached = nil
        hover = nil
        if loading || folded.isEmpty { folded = loading ? [] : folded; return lm?.hiddenRanges.isEmpty == false ? [] : nil }
        guard let old else { folded = []; persist(); return [] }
        let next = FoldEdits.remap(old.filter { folded.contains($0.anchor) }, edit: edit, delta: delta, into: regions)
        if next != folded { folded = next; persist() }
        return foldedRegions.map(\.hidden)
    }

    // MARK: Load / restore

    /// Bind to a note and show its saved folds. Folds whose heading or list item is gone are dropped.
    func restore(path: String?, store: FoldStore?) {
        self.path = path; self.store = store
        kinds = EditorPrefs.foldKinds
        cached = nil
        guard let path, let store else { folded = []; preserved = []; apply(); return }
        let saved = store.anchors(for: path)
        preserved = saved.filter { a in !kinds.contains(where: { a.signature.hasPrefix($0.rawValue + ":") }) }
        let present = Set(regions.map(\.anchor))
        folded = saved.intersection(present)
        if folded.union(preserved) != saved { persist() }
        apply(keepCaretVisible: true)
    }

    func reloadFromStore() { restore(path: path, store: store) }

    func prefsChanged() { reloadFromStore(); tv?.needsDisplay = true }

    private func persist() {
        guard let path, let store, !loading else { return }
        store.set(folded.union(preserved), for: path)
    }

    /// Push the folded set to the layout. First move any caret out of what's about to hide,
    /// so the selection guard never sees it inside a fold (and doesn't reopen it).
    private func apply(keepCaretVisible: Bool = true) {
        guard let tv, let lm else { return }
        let hidden = foldedRegions.map(\.hidden)
        if keepCaretVisible {
            let merged = FoldSelection.merge(hidden)
            let sel = tv.selectedRange()
            if let h = FoldSelection.container(of: sel.location, in: merged) ?? (sel.length > 0 ? FoldSelection.container(of: NSMaxRange(sel), in: merged).flatMap { NSMaxRange(sel) < NSMaxRange($0) ? $0 : nil } : nil) {
                tv.applyingFolds = true
                tv.setSelectedRange(NSRange(location: h.location, length: 0))
                tv.applyingFolds = false
            }
        }
        lm.setHiddenRanges(hidden)
        tv.needsDisplay = true
        tv.sizeToFitContent()
        if let path { onChange?(path) }
    }

    // MARK: Fold operations

    func isFolded(_ r: FoldRegion) -> Bool { folded.contains(r.anchor) }

    func setFolded(_ r: FoldRegion, _ on: Bool) {
        guard on != folded.contains(r.anchor) else { return }
        if on { folded.insert(r.anchor) } else { folded.remove(r.anchor) }
        persist(); apply()
    }

    func toggle(_ r: FoldRegion) { setFolded(r, !isFolded(r)) }

    /// The region whose header line holds the caret, else the innermost one around it.
    func regionAtCaret(foldedOnly: Bool = false, enclosing: Bool = true) -> FoldRegion? {
        guard let tv else { return nil }
        let c = tv.selectedRange().location
        let rs = regions
        if let h = rs.last(where: { c >= $0.header.location && c <= NSMaxRange($0.header) && (!foldedOnly || isFolded($0)) }) { return h }
        guard enclosing else { return nil }
        return rs.filter { c > $0.header.location && c <= NSMaxRange($0.hidden) && (!foldedOnly || isFolded($0)) }
            .min { $0.hidden.length < $1.hidden.length }
    }

    @discardableResult func foldCurrent() -> Bool {
        guard let r = regionAtCaret() else { return false }
        if isFolded(r) {   // already folded at the header: fold its parent, like “fold more”
            guard let p = regions.filter({ $0.header.location < r.header.location && NSMaxRange($0.hidden) >= NSMaxRange(r.hidden) && !isFolded($0) })
                .min(by: { $0.hidden.length < $1.hidden.length }) else { return false }
            setFolded(p, true); return true
        }
        setFolded(r, true); return true
    }

    @discardableResult func unfoldCurrent() -> Bool {
        guard let r = regionAtCaret(foldedOnly: true, enclosing: false) else { return false }
        setFolded(r, false); return true
    }

    @discardableResult func toggleCurrent() -> Bool {
        if let r = regionAtCaret(enclosing: false) { toggle(r); return true }
        return foldCurrent()
    }

    func foldAll() { folded = Set(regions.map(\.anchor)); persist(); apply() }
    func unfoldAll() { guard !folded.isEmpty else { return }; folded = []; persist(); apply() }

    /// Open every fold that would hide one of these caret positions (Find, outline, links, undo).
    func reveal(_ positions: [Int]) {
        var changed = false
        for r in foldedRegions where positions.contains(where: { $0 > r.hidden.location && $0 <= NSMaxRange(r.hidden) }) {
            folded.remove(r.anchor); changed = true
        }
        if changed { persist(); apply(keepCaretVisible: false) }
    }

    /// An edit that would change hidden text, or merge the line after a fold into it, opens
    /// that fold first, so nothing changes out of sight. Deleting a whole folded section
    /// (header included) is allowed as is.
    func revealForEdit(_ ranges: [NSRange]) {
        guard !folded.isEmpty else { return }
        var changed = false
        for f in foldedRegions {
            let h = f.hidden, guardEnd = NSMaxRange(h) + 1
            for r in ranges {
                let hit: Bool
                if r.length == 0 { hit = r.location > h.location && r.location <= NSMaxRange(h) }
                else {
                    let whole = r.location <= f.header.location && NSMaxRange(r) >= NSMaxRange(h)
                    hit = !whole && r.location < guardEnd && NSMaxRange(r) > h.location
                }
                if hit { folded.remove(f.anchor); changed = true; break }
            }
        }
        if changed { persist(); apply(keepCaretVisible: false) }
    }

    // MARK: Selection guard

    func adjust(_ ranges: [NSValue], stillSelecting: Bool) -> [NSValue] {
        guard let tv, let lm, !lm.hiddenRanges.isEmpty, !tv.applyingFolds else { return ranges }
        let intent = Self.intent(for: tv)
        let previous = tv.selectedRanges.first?.rangeValue
        let ns = tv.string as NSString
        var out: [NSValue] = [], reveals: [Int] = []
        for v in ranges {
            let r = FoldSelection.adjust(v.rangeValue, previous: previous, hidden: lm.hiddenRanges, intent: stillSelecting ? .mouse : intent) { e in
                e >= ns.length ? ns.length : NSMaxRange(ns.lineRange(for: NSRange(location: e, length: 0)))
            }
            out.append(NSValue(range: r.range)); reveals += r.reveal
        }
        if !reveals.isEmpty { reveal(reveals) }
        return out
    }

    private static func intent(for tv: NSTextView) -> FoldSelection.Intent {
        if let u = tv.undoManager, u.isUndoing || u.isRedoing { return .programmatic }
        guard let e = NSApp.currentEvent, e.window === tv.window, e.window != nil else { return .programmatic }
        switch e.type {
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown:
            return tv.visibleRect.contains(tv.convert(e.locationInWindow, from: nil)) ? .mouse : .programmatic
        case .keyDown:
            return tv.window?.firstResponder === tv ? .keyboard : .programmatic
        default: return .programmatic
        }
    }

    // MARK: Geometry and drawing

    /// Header regions sorted by location; binary search by character index on the header line.
    func region(atHeaderChar c: Int) -> FoldRegion? {
        let rs = regions
        var lo = 0, hi = rs.count - 1, best: FoldRegion?
        while lo <= hi {
            let m = (lo + hi) / 2
            if rs[m].header.location <= c { best = rs[m]; lo = m + 1 } else { hi = m - 1 }
        }
        guard let b = best, c <= NSMaxRange(b.header) else { return nil }
        return b
    }

    /// The region whose header line is under a point (anywhere across the row, margin included).
    func region(atY y: CGFloat) -> FoldRegion? {
        guard let tv, let lm, let tc = tv.textContainer, !regions.isEmpty else { return nil }
        let p = NSPoint(x: 1, y: y - tv.textContainerOrigin.y)
        guard lm.numberOfGlyphs > 0 else { return nil }
        let g = lm.glyphIndex(for: p, in: tc)
        let frag = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
        guard p.y >= frag.minY - 1, p.y <= frag.maxY + 1 else { return nil }
        return region(atHeaderChar: lm.characterIndexForGlyph(at: g))
    }

    private func firstGlyphRect(_ r: FoldRegion) -> NSRect? {
        guard let tv, let lm, let tc = tv.textContainer else { return nil }
        let ns = tv.string as NSString
        var c = r.header.location
        while c < NSMaxRange(r.header), [0x20, 0x09].contains(ns.character(at: c)) { c += 1 }
        let g = lm.glyphIndexForCharacter(at: min(c, max(0, ns.length - 1)))
        guard g < lm.numberOfGlyphs else { return nil }
        var rect = lm.boundingRect(forGlyphRange: NSRange(location: g, length: 1), in: tc)
        rect.origin.x += tv.textContainerOrigin.x; rect.origin.y += tv.textContainerOrigin.y
        return rect
    }

    func chevronRect(_ r: FoldRegion) -> NSRect? {
        guard let g = firstGlyphRect(r) else { return nil }
        let size: CGFloat = 18
        return NSRect(x: g.minX - size - 4, y: g.midY - size / 2, width: size, height: size)
    }

    func ellipsisRect(_ r: FoldRegion) -> NSRect? {
        guard let tv, let lm, let tc = tv.textContainer, r.header.length > 0 else { return nil }
        let gr = lm.glyphRange(forCharacterRange: NSRange(location: NSMaxRange(r.header) - 1, length: 1), actualCharacterRange: nil)
        guard gr.length > 0 else { return nil }
        var g = lm.boundingRect(forGlyphRange: gr, in: tc)
        g.origin.x += tv.textContainerOrigin.x; g.origin.y += tv.textContainerOrigin.y
        let h: CGFloat = max(12, min(16, Theme.editorSize * 0.95))
        return NSRect(x: g.maxX + 8, y: g.midY - h / 2, width: h * 1.9, height: h)
    }

    func hit(_ point: NSPoint) -> (FoldRegion, Part)? {
        guard !kinds.isEmpty, let r = region(atY: point.y) else { return nil }
        if let c = chevronRect(r), c.insetBy(dx: -3, dy: -3).contains(point) { return (r, .chevron) }
        if isFolded(r), let e = ellipsisRect(r), e.insetBy(dx: -3, dy: -3).contains(point) { return (r, .ellipsis) }
        return nil
    }

    func draw(_ dirty: NSRect) {
        guard !kinds.isEmpty, let tv, let lm, let tc = tv.textContainer, !folded.isEmpty || hover != nil else { return }
        // Only headers on the dirtied rows, and never one tucked inside a folded parent.
        var rect = dirty.insetBy(dx: 0, dy: -40); rect.origin.x = 0; rect.size.width = tv.bounds.width
        rect.origin.y -= tv.textContainerOrigin.y
        let chars = lm.characterRange(forGlyphRange: lm.glyphRange(forBoundingRect: rect, in: tc), actualGlyphRange: nil)
        let hidden = lm.hiddenRanges
        var show = foldedRegions.filter { NSLocationInRange($0.header.location, chars) || $0.header.location == NSMaxRange(chars) }
        if let h = hover, let r = regions.first(where: { $0.header.location == h }), !isFolded(r) { show.append(r) }
        for r in show where FoldSelection.container(of: r.header.location, in: hidden) == nil && !hidden.contains(where: { NSLocationInRange(r.header.location, $0) }) {
            guard let c = chevronRect(r), c.intersects(dirty) || (ellipsisRect(r)?.intersects(dirty) ?? false) else { continue }
            let hot = hover == r.header.location && hoverPart == .chevron
            drawChevron(in: c, open: !isFolded(r), color: hot ? Theme.muted : Theme.faint.withAlphaComponent(isFolded(r) || hover == r.header.location ? 0.9 : 0.6))
            if isFolded(r), let e = ellipsisRect(r) {
                let hotE = hover == r.header.location && hoverPart == .ellipsis
                let pill = NSBezierPath(roundedRect: e, xRadius: e.height / 2, yRadius: e.height / 2)
                (hotE ? Theme.border : Theme.paperAlt).setFill(); pill.fill()
                Theme.border.withAlphaComponent(0.8).setStroke(); pill.lineWidth = 0.5; pill.stroke()
                (hotE ? Theme.ink : Theme.muted).setFill()
                let d: CGFloat = 2.2, gap: CGFloat = 3.4
                for i in -1...1 {
                    NSBezierPath(ovalIn: NSRect(x: e.midX + CGFloat(i) * (d + gap) - d / 2, y: e.midY - d / 2, width: d, height: d)).fill()
                }
            }
        }
    }

    private func drawChevron(in r: NSRect, open: Bool, color: NSColor) {
        let s: CGFloat = 3.6, c = NSPoint(x: r.midX, y: r.midY)
        let p = NSBezierPath()
        if open {   // ⌄ (flipped view: +y is down)
            p.move(to: NSPoint(x: c.x - s, y: c.y - s / 2)); p.line(to: NSPoint(x: c.x, y: c.y + s / 2)); p.line(to: NSPoint(x: c.x + s, y: c.y - s / 2))
        } else {    // ›
            p.move(to: NSPoint(x: c.x - s / 2, y: c.y - s)); p.line(to: NSPoint(x: c.x + s / 2, y: c.y)); p.line(to: NSPoint(x: c.x - s / 2, y: c.y + s))
        }
        p.lineWidth = 1.3; p.lineCapStyle = .round; p.lineJoinStyle = .round
        color.setStroke(); p.stroke()
    }

    /// Mouse moved: track the row under the pointer; redraw only the rows that changed.
    func mouseMoved(to point: NSPoint) {
        guard let tv, !kinds.isEmpty else { return }
        let r = region(atY: point.y)
        var part: Part?
        if let r {
            if let c = chevronRect(r), c.insetBy(dx: -3, dy: -3).contains(point) { part = .chevron }
            else if isFolded(r), let e = ellipsisRect(r), e.insetBy(dx: -3, dy: -3).contains(point) { part = .ellipsis }
        }
        let new = r?.header.location
        guard new != hover || part != hoverPart else { return }
        let old = hover.flatMap { h in regions.first { $0.header.location == h } }
        hover = new; hoverPart = part
        for x in [old, r].compactMap({ $0 }) { invalidate(x) }
        _ = tv
    }

    func mouseExited() {
        guard let h = hover else { return }
        let old = regions.first { $0.header.location == h }
        hover = nil; hoverPart = nil
        if let old { invalidate(old) }
    }

    private func invalidate(_ r: FoldRegion) {
        guard let tv else { return }
        if let c = chevronRect(r) { tv.setNeedsDisplay(c.insetBy(dx: -4, dy: -4)) }
        if let e = ellipsisRect(r) { tv.setNeedsDisplay(e.insetBy(dx: -4, dy: -4)) }
    }
}

extension OnyxTextView {
    /// Grow/shrink the document view after a fold (TextKit 1 resizes lazily otherwise).
    func sizeToFitContent() {
        guard let lm = layoutManager, let tc = textContainer else { return }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc)
        let h = max(used.maxY + textContainerInset.height * 2, enclosingScrollView?.contentSize.height ?? 0)
        if abs(frame.height - h) > 0.5 { setFrameSize(NSSize(width: frame.width, height: h)) }
    }
}
