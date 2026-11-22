#if canImport(AppKit)
import AppKit

/// TextKit 1 display-only folding. No attributes, attachments, or source replacements.
/// Null glyphs include internal newlines, leaving the final newline of each run alive;
/// the hidden paragraphs consequently occupy no line fragments of their own.
public final class FoldLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    public private(set) var hiddenRanges: [NSRange] = []

    public override init() { super.init(); delegate = self }
    public required init?(coder: NSCoder) { super.init(coder: coder); delegate = self }

    public func setHiddenRanges(_ ranges: [NSRange]) {
        let n = textStorage?.length ?? 0
        let valid = FoldSelection.merge(ranges.compactMap {
            let start = max(0, $0.location), end = min(n, NSMaxRange($0))
            return end > start ? NSRange(location: start, length: end - start) : nil
        })
        guard valid != hiddenRanges else { return }
        let old = hiddenRanges; hiddenRanges = valid
        // Invalidating only the affected spans matters in long notes. The glyph delegate
        // gets called lazily as TextKit lays out the visible portion of the page.
        for r in FoldSelection.merge(old + valid) {
            let end = min(n, NSMaxRange(r))
            if end > r.location {
                invalidateGlyphs(forCharacterRange: NSRange(location: r.location, length: end - r.location), changeInLength: 0, actualCharacterRange: nil)
            }
        }
    }

    /// Called while the storage processes a character edit (the string is already new):
    /// return the hidden ranges for the new text, or nil when nothing is folded.
    public var onEdit: ((_ edited: NSRange, _ delta: Int) -> [NSRange]?)?

    public override func processEditing(for textStorage: NSTextStorage, edited mask: NSTextStorageEditActions, range newCharRange: NSRange, changeInLength delta: Int, invalidatedRange invalidatedCharRange: NSRange) {
        var stale: [NSRange] = []
        if mask.contains(.editedCharacters), let next = onEdit?(newCharRange, delta) {
            // Shift the old runs into new coordinates; whatever changed state must be re-glyphed.
            let oldEnd = newCharRange.location + max(0, newCharRange.length - delta)
            let shifted = hiddenRanges.map { r -> NSRange in
                if NSMaxRange(r) <= newCharRange.location { return r }
                if r.location >= oldEnd { return NSRange(location: r.location + delta, length: r.length) }
                let s = min(r.location, newCharRange.location), e = max(NSMaxRange(r) + delta, NSMaxRange(newCharRange))
                return NSRange(location: s, length: max(0, e - s))
            }
            let n = textStorage.length
            hiddenRanges = FoldSelection.merge(next.compactMap {
                let start = max(0, $0.location), end = min(n, NSMaxRange($0))
                return end > start ? NSRange(location: start, length: end - start) : nil
            })
            if shifted != hiddenRanges { stale = FoldSelection.merge(shifted + hiddenRanges) }
        }
        super.processEditing(for: textStorage, edited: mask, range: newCharRange, changeInLength: delta, invalidatedRange: invalidatedCharRange)
        let n = textStorage.length
        for r in stale {
            let end = min(n, NSMaxRange(r))
            if end > r.location { invalidateGlyphs(forCharacterRange: NSRange(location: r.location, length: end - r.location), changeInLength: 0, actualCharacterRange: nil) }
        }
    }

    private func hidden(_ i: Int) -> Bool {
        var lo = 0, hi = hiddenRanges.count - 1
        while lo <= hi {
            let m = (lo + hi) / 2, r = hiddenRanges[m]
            if i < r.location { hi = m - 1 } else if i >= NSMaxRange(r) { lo = m + 1 } else { return true }
        }
        return false
    }

    public func layoutManager(_ lm: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>, properties: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes: UnsafePointer<Int>, font: NSFont, forGlyphRange range: NSRange) -> Int {
        guard !hiddenRanges.isEmpty else { return 0 }
        var props: [NSLayoutManager.GlyphProperty]?
        for i in 0..<range.length where hidden(characterIndexes[i]) {
            if props == nil { props = Array(UnsafeBufferPointer(start: properties, count: range.length)) }
            props![i].insert(.null)
        }
        guard let p = props else { return 0 }
        p.withUnsafeBufferPointer { lm.setGlyphs(glyphs, properties: $0.baseAddress!, characterIndexes: characterIndexes, font: font, forGlyphRange: range) }
        return range.length
    }

    public func layoutManager(_ lm: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction, forControlCharacterAt index: Int) -> NSLayoutManager.ControlCharacterAction {
        hidden(index) ? .zeroAdvancement : action
    }
}
#endif
