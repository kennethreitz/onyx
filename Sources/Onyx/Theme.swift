import AppKit
import SwiftUI

/// Reitz LaTeX, translated from CSS custom properties into native colors.
/// Light is ink on paper; dark is the same Latin Modern on dark paper.
enum Theme {
    static func dyn(_ light: UInt32, _ dark: UInt32, _ la: CGFloat = 1, _ da: CGFloat? = nil) -> NSColor {
        NSColor(name: nil) { ap in
            let isDark = ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light, alpha: isDark ? (da ?? la) : la)
        }
    }
    static let paper = dyn(0xfdfdfb, 0x1b1b19)
    static let paperAlt = dyn(0xf6f6f1, 0x222220)
    static let secondary = dyn(0xf4f4ef, 0x201f1d)
    static let secondaryAlt = dyn(0xecece6, 0x262521)
    static let ink = dyn(0x1a1a18, 0xe9e8e1)
    static let muted = dyn(0x565650, 0xb3b2a9)
    /// Markdown syntax in the editor: as quiet as iA Writer's.
    static let faint = dyn(0x8a8a82, 0x7f7e76)
    /// Chrome labels at 9.5–11pt: a shade darker in light mode so they clear ~4:1 on paper.
    static let faintLabel = dyn(0x7f7f78, 0x7f7e76)
    static let border = dyn(0xdedcd2, 0x34332e)
    static let cursor = dyn(0x5a7a9e, 0x7aa8cc)
    static let selection = dyn(0xffdc28, 0xffdc28, 0.22, 0.14)
    static let findMatch = dyn(0xffb020, 0xffb020, 0.20, 0.18)     // every ⌘F match
    static let findCurrent = dyn(0xff8a00, 0xffa526, 0.45, 0.42)   // the one you're on
    static let activeLine = NSColor(name: nil) { ap in
        ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.025) : NSColor(red: 1, green: 0.86, blue: 0.16, alpha: 0.07)
    }
    static let highlight = dyn(0xffdc28, 0xffdc28, 0.30, 0.22)
    /// Semantic tints, inked rather than system-bright: conflicts, refused drops, errors, recording.
    static let warn = dyn(0xa8612a, 0xe0a060)       // burnt amber
    static let danger = dyn(0xa8423c, 0xe2827a)     // madder red

    /// Highlightr palette from the vault's plugin settings (8-digit hex, alpha A6).
    static let highlighters: [(String, UInt32)] = [
        ("Pink", 0xFFB8EB), ("Red", 0xFF5582), ("Orange", 0xFFB86C), ("Yellow", 0xFFF3A3), ("Green", 0xBBFABB),
        ("Cyan", 0xABF7F7), ("Blue", 0xADCCFF), ("Purple", 0xD2B3FF), ("Grey", 0xCACFD9),
    ]

    // Typography
    static var editorSize: CGFloat { Prefs.editorPoints }
    /// OpenDyslexic’s x-height is large; a slightly smaller body size keeps the editor presentable.
    static var editorBodySize: CGFloat { Typeset.openDyslexicEnabled ? editorSize * 0.88 : editorSize }
    static var editorLineHeight: CGFloat { Typeset.openDyslexicEnabled ? 1.9 : 1.8 }
    /// Tight tracking for Plex Mono; OpenDyslexic already has wide glyphs, so no extra kern.
    static var editorKern: CGFloat { Typeset.openDyslexicEnabled ? 0 : -0.14 }
    static var editorMeasure: CGFloat { Prefs.editorMeasure }
    static func editorMonoFont(_ size: CGFloat = editorSize, bold: Bool = false, italic: Bool = false) -> NSFont {
        let name = bold ? "IBMPlexMono-Bold" : (italic ? "IBMPlexMono-Italic" : "IBMPlexMono")
        return NSFont(name: name, size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
    }
    static func editorFont(_ size: CGFloat = editorBodySize, bold: Bool = false, italic: Bool = false) -> NSFont {
        guard Typeset.openDyslexicEnabled else { return editorMonoFont(size, bold: bold, italic: italic) }
        let name: String
        switch (bold, italic) {
        case (true, true): name = "OpenDyslexic-BoldItalic"
        case (true, false): name = "OpenDyslexic-Bold"
        case (false, true): name = "OpenDyslexic-Italic"
        default: name = "OpenDyslexic-Regular"
        }
        return NSFont(name: name, size: size) ?? editorMonoFont(size, bold: bold, italic: italic)
    }
    static func serif(_ size: CGFloat, bold: Bool = false, italic: Bool = false) -> Font {
        .custom(bold ? "LMRoman10-Bold" : (italic ? "LMRoman10-Italic" : "LMRoman10-Regular"), size: size)
    }
    static func titleSerif(_ size: CGFloat) -> Font { .custom("LMRoman12-Bold", size: size) }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }
    var cssRGBA: String {
        let c = usingColorSpace(.sRGB) ?? self
        return "rgba(\(Int(c.redComponent * 255)),\(Int(c.greenComponent * 255)),\(Int(c.blueComponent * 255)),\(String(format: "%.3f", c.alphaComponent)))"
    }
}

extension Color {
    static let paper = Color(nsColor: Theme.paper)
    static let paperAlt = Color(nsColor: Theme.paperAlt)
    static let secondaryPaper = Color(nsColor: Theme.secondary)
    static let ink = Color(nsColor: Theme.ink)
    static let muted = Color(nsColor: Theme.muted)
    static let faint = Color(nsColor: Theme.faintLabel)
    static let hairline = Color(nsColor: Theme.border)
    static let cursorBlue = Color(nsColor: Theme.cursor)
    static let warn = Color(nsColor: Theme.warn)
    static let danger = Color(nsColor: Theme.danger)
}

// MARK: - Scales (see docs/DESIGN.md › Scales)

/// Spacing steps for chrome. Prefer these to one-off numbers; the page itself is typeset by the reader/editor.
enum Space {
    static let xxs: CGFloat = 2, xs: CGFloat = 4, s: CGFloat = 6, m: CGFloat = 8, l: CGFloat = 12, xl: CGFloat = 16, xxl: CGFloat = 24
}

/// Corner radii: four sizes, picked by how big the thing is.
enum Radius {
    static let small: CGFloat = 4     // chips, keycaps, ≤22pt icon buttons
    static let control: CGFloat = 6   // list rows, tabs, fields
    static let card: CGFloat = 8      // popovers, find bar, cards
    static let panel: CGFloat = 12    // summoned panels (panelChrome)
}

/// Chrome type scale (SF, points). The page uses Latin Modern / Plex at the user's size.
enum TypeScale {
    static let label: CGFloat = 9.5     // UPPERCASE section labels, tracked
    static let caption: CGFloat = 10.5  // counts, hints, secondary lines
    static let small: CGFloat = 11.5    // panel text, properties, toasts
    static let body: CGFloat = 12.5     // rows, fields
    static let row: CGFloat = 13.5      // palette rows
}

/// Motion: a few named curves, and Reduce Motion respected everywhere. With Reduce Motion on,
/// springs become a short dissolve and slides/scales become plain fades.
/// The title path sits over the page; body text scrolls under a soft paper fade.
enum ReadingChrome {
    /// Height of the title-path fade, in points (RootView.titleLine).
    static let titleFade: CGFloat = 46
    /// Breathing room below the visible top (just under the fade) when jumping to a heading.
    static let outlineGap: CGFloat = 20
    static func outlineOffset(focusMode: Bool) -> CGFloat {
        (focusMode ? 0 : titleFade) + outlineGap
    }
}

@MainActor enum Motion {
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// Hover and press feedback (color/opacity only, so it stays on with Reduce Motion).
    static let hover: Animation = .easeOut(duration: 0.12)
    /// Selection, disclosure, small toggles.
    static var quick: Animation { reduced ? .easeOut(duration: 0.1) : .easeOut(duration: 0.15) }
    /// Read ⇄ edit, cross-fades.
    static var fade: Animation { .easeInOut(duration: reduced ? 0.12 : 0.18) }
    /// Summoned overlays (switcher, palette, graph).
    static var overlay: Animation { reduced ? .easeOut(duration: 0.12) : .spring(response: 0.26, dampingFraction: 0.9) }
    /// Docking panels, splits, layout changes.
    static var layout: Animation { reduced ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.88) }
    /// Slide in from an edge, or just fade with Reduce Motion.
    static func slide(_ edge: Edge) -> AnyTransition { reduced ? .opacity : .move(edge: edge).combined(with: .opacity) }
    /// A slight scale-in, or just fade with Reduce Motion.
    static func pop(_ scale: CGFloat = 0.98, anchor: UnitPoint = .center) -> AnyTransition {
        reduced ? .opacity : .opacity.combined(with: .scale(scale: scale, anchor: anchor))
    }
}

/// Keyboard shortcuts drawn as quiet keycaps: "⇧⌘P" → [⇧][⌘][P]; chords separated by two spaces
/// ("⌘[  ⌘]") get a little air between them.
struct Keycaps: View {
    var keys: String
    var size: CGFloat = TypeScale.caption
    var body: some View {
        HStack(spacing: Space.s) {
            ForEach(Array(Self.chords(keys).enumerated()), id: \.offset) { _, chord in
                HStack(spacing: Space.xxs) {
                    ForEach(Array(chord.enumerated()), id: \.offset) { _, k in
                        Text(k)
                            .font(.system(size: size, weight: .medium).monospacedDigit())
                            .foregroundStyle(Color.muted)
                            .frame(minWidth: size + 5)
                            .padding(.horizontal, k.count > 1 ? 4 : 1)
                            .frame(height: size + 6.5)
                            .background(RoundedRectangle(cornerRadius: Radius.small).fill(Color.ink.opacity(0.045)))
                            .overlay(RoundedRectangle(cornerRadius: Radius.small).strokeBorder(Color.hairline, lineWidth: 0.8))
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys)
    }
    static let modifiers: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]
    /// Chords (split on runs of 2+ spaces, " · " or " / "), each split into modifier glyphs plus the key.
    static func chords(_ s: String) -> [[String]] {
        let parts = s.replacingOccurrences(of: " · ", with: "  ").replacingOccurrences(of: " / ", with: "  ")
            .components(separatedBy: "  ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return parts.map { chord in
            var caps: [String] = [], rest = ""
            for ch in chord where ch != " " {
                if modifiers.contains(ch) && rest.isEmpty { caps.append(String(ch)) } else { rest.append(ch) }
            }
            if !rest.isEmpty { caps.append(rest) }
            return caps
        }
    }
}

/// Stable, muted cluster colors: a folder or tag name hashes into a palette of
/// ink-like hues (terracotta, ochre, olive, sage, teal, violet, plum, rose, umber, moss).
/// Slate blue is reserved for the current note's accent.
enum ClusterPalette {
    // ordered around the hue wheel so "far apart in the list" means "far apart in hue"
    static let pairs: [(UInt32, UInt32)] = [
        (0xA0573A, 0xDE9474), // terracotta
        (0x94741C, 0xD6B65E), // ochre
        (0x667634, 0xB0C072), // olive
        (0x3F7A5C, 0x82C49E), // sage
        (0x2C7775, 0x72C3BF), // teal
        (0x6A5A9A, 0xAE9EE0), // violet
        (0x8E4F7E, 0xD08FC0), // plum
        (0xA34B5C, 0xE38E9E), // rose
    ]
    static func index(_ key: String) -> Int {
        var h: UInt64 = 0xcbf29ce484222325
        for b in key.lowercased().utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return Int(h % UInt64(pairs.count))
    }
    /// Collision-free slots for the regions currently on the map: largest first keeps its
    /// hashed hue, later ones probe to the next unused hue, so neighbors never share a color.
    nonisolated(unsafe) static var slots: [String: Int] = [:]
    static func assign(_ keysBySize: [String]) {
        let n = pairs.count
        var used: [Int] = [], out = slots
        func dist(_ a: Int, _ b: Int) -> Int { let d = abs(a - b) % n; return min(d, n - d) }
        for k in keysBySize {
            let h = index(k)
            // prefer the hashed hue; otherwise the nearest slot that is ≥2 steps from every hue in use
            let order = (0..<n).map { (h + $0) % n }
            let pick = order.first { c in used.allSatisfy { dist($0, c) >= 2 } }
                ?? order.first { !used.contains($0) } ?? h
            used.append(pick); out[k.lowercased()] = pick
        }
        slots = out
    }
    static func nsColor(_ key: String) -> NSColor { let p = pairs[slots[key.lowercased()] ?? index(key)]; return Theme.dyn(p.0, p.1) }
    static func color(_ key: String) -> Color { Color(nsColor: nsColor(key)) }
}
