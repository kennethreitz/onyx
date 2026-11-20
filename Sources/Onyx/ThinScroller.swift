import AppKit
import SwiftUI

/// Onyx's scrollbar (overlay-feeling, drawn by us): a few points wide, a low-contrast rounded thumb, no track.
/// It fades in while scrolling or when the pointer is over it, and fades out when idle.
final class ThinScroller: NSScroller {
    private var hovering = false
    private var fadeWork: DispatchWorkItem?
    private var tracking: NSTrackingArea?

    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat { 9 }

    override init(frame: NSRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }
    private func setup() { scrollerStyle = .legacy; knobStyle = .default; alphaValue = 0; wantsLayer = true }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}   // no track
    override func draw(_ dirtyRect: NSRect) { drawKnob() }

    override func drawKnob() {
        var r = rect(for: .knob)
        guard r.height > 0, r.width > 0 else { return }
        let w: CGFloat = hovering ? 5 : 3
        let vertical = bounds.height >= bounds.width
        if vertical { r = NSRect(x: bounds.maxX - w - 2, y: r.minY + 2, width: w, height: max(0, r.height - 4)) }
        else { r = NSRect(x: r.minX + 2, y: bounds.maxY - w - 2, width: max(0, r.width - 4), height: w) }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let ink = dark ? NSColor.white : NSColor.black
        ink.withAlphaComponent(hovering ? (dark ? 0.38 : 0.32) : (dark ? 0.26 : 0.2)).setFill()
        NSBezierPath(roundedRect: r, xRadius: w / 2, yRadius: w / 2).fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(t); tracking = t
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true; show(hold: true) }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true; show() }
    override func mouseDown(with event: NSEvent) { show(hold: true); super.mouseDown(with: event); show() }

    /// Fade in, then out after a beat of stillness (unless the pointer is resting on it).
    func show(hold: Bool = false) {
        fadeWork?.cancel()
        guard knobProportion < 0.999, isEnabled else { animator().alphaValue = 0; return }
        if alphaValue < 1 { NSAnimationContext.runAnimationGroup { $0.duration = 0.12; animator().alphaValue = 1 } }
        guard !hold && !hovering else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.hovering else { return }
            NSAnimationContext.runAnimationGroup { $0.duration = 0.45; self.animator().alphaValue = 0 }
        }
        fadeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }

    /// Install thin scrollers on a scroll view and flash them whenever it scrolls.
    static func install(on sv: NSScrollView) {
        if sv.verticalScroller is ThinScroller { return }
        // Legacy style so AppKit calls our drawing (overlay style draws through a private imp);
        // the fade is ours, and the 9pt column is transparent.
        sv.scrollerStyle = .legacy
        sv.autohidesScrollers = true
        let v = ThinScroller(); sv.verticalScroller = v
        if sv.hasHorizontalScroller { sv.horizontalScroller = ThinScroller() }
        sv.contentView.postsBoundsChangedNotifications = true
        let token = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: sv.contentView, queue: .main) { [weak sv] _ in
            MainActor.assumeIsolated {
                (sv?.verticalScroller as? ThinScroller)?.show()
                (sv?.horizontalScroller as? ThinScroller)?.show()
            }
        }
        objc_setAssociatedObject(sv, &tokenKey, ObserverBox(token), .OBJC_ASSOCIATION_RETAIN)
        // the system can switch scroller styles when the user's preference changes; keep ours
        let styleToken = NotificationCenter.default.addObserver(forName: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil, queue: .main) { [weak sv] _ in
            MainActor.assumeIsolated { sv?.scrollerStyle = .legacy }
        }
        objc_setAssociatedObject(sv, &styleKey, ObserverBox(styleToken), .OBJC_ASSOCIATION_RETAIN)
    }
}

private var tokenKey: UInt8 = 0
private var styleKey: UInt8 = 0
private final class ObserverBox {
    let token: NSObjectProtocol
    init(_ t: NSObjectProtocol) { token = t }
    deinit { NotificationCenter.default.removeObserver(token) }
}

/// Drop inside a SwiftUI ScrollView's content to give that scroll view Onyx's thin scrollers.
struct ThinScrollers: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Finder() }
    func updateNSView(_ v: NSView, context: Context) { (v as? Finder)?.attach() }
    final class Finder: NSView {
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); attach() }
        func attach() {
            DispatchQueue.main.async { [weak self] in
                guard let sv = self?.enclosingScrollView else { return }
                ThinScroller.install(on: sv)
            }
        }
    }
}

extension View {
    /// Onyx's minimal overlay scrollbars for this ScrollView (apply to the scroll content).
    func thinScrollers() -> some View { background(ThinScrollers().frame(width: 0, height: 0)) }
}

import WebKit

/// Test hook: with ONYX_SCROLL_TEST=<seconds>, scroll every scroll view and reader in small steps
/// that long after launch so the scrollbar fade can be screenshotted without synthetic input.
enum ScrollSelfTest {
    @MainActor static func scheduleIfRequested() {
        guard let v = ProcessInfo.processInfo.environment["ONYX_SCROLL_TEST"] else { return }
        let delay = Double(v).map { $0 > 1 ? $0 : 4 } ?? 4     // ONYX_SCROLL_TEST=<seconds>, default 4
        // small steps over ~1.5s, so a screenshot reliably lands mid-scroll
        for k in 0..<6 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + Double(k) * 0.3) {
                for w in NSApp.windows { if let v = w.contentView { poke(v) } }
            }
        }
    }
    @MainActor private static func poke(_ v: NSView) {
        if let wv = v as? WKWebView { wv.evaluateJavaScript("window.scrollBy(0, 70)", completionHandler: nil) }
        if let sv = v as? NSScrollView, let doc = sv.documentView, doc.frame.height > sv.contentView.bounds.height + 1 {
            var o = sv.contentView.bounds.origin; o.y += 40
            sv.contentView.scroll(to: o); sv.reflectScrolledClipView(sv.contentView)
        }
        v.subviews.forEach(poke)
    }
}

/// A scroll view whose thin scroller floats over the content instead of reserving a column,
/// so split panes meet at a hairline with no gutter.
final class ThinScrollView: NSScrollView {
    /// Called after a real size change (split, sidebar, window), so the owner can hold its
    /// reading position by source line instead of letting AppKit drift it.
    var onResize: (() -> Void)?
    private(set) var resizing = 0
    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        resizing += 1
        super.setFrameSize(newSize)
        resizing -= 1
        if changed { onResize?() }
    }
    override func tile() {
        super.tile()
        guard let v = verticalScroller, hasVerticalScroller else { return }
        var c = contentView.frame
        c.size.width = bounds.width - c.minX
        contentView.frame = c
        v.frame = NSRect(x: bounds.maxX - v.frame.width, y: v.frame.minY, width: v.frame.width, height: v.frame.height)
        if subviews.last !== v { addSubview(v, positioned: .above, relativeTo: nil) }
    }
}
