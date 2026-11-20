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
    static let faint = dyn(0x8a8a82, 0x7f7e76)
    static let border = dyn(0xdedcd2, 0x34332e)
    static let cursor = dyn(0x5a7a9e, 0x7aa8cc)
    static let selection = dyn(0xffdc28, 0xffdc28, 0.22, 0.14)
    static let findMatch = dyn(0xffb020, 0xffb020, 0.20, 0.18)     // every ⌘F match
    static let findCurrent = dyn(0xff8a00, 0xffa526, 0.45, 0.42)   // the one you're on
    static let activeLine = NSColor(name: nil) { ap in
        ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.025) : NSColor(red: 1, green: 0.86, blue: 0.16, alpha: 0.07)
    }
    static let highlight = dyn(0xffdc28, 0xffdc28, 0.30, 0.22)

    /// Highlightr palette from the vault's plugin settings (8-digit hex, alpha A6).
    static let highlighters: [(String, UInt32)] = [
        ("Pink", 0xFFB8EB), ("Red", 0xFF5582), ("Orange", 0xFFB86C), ("Yellow", 0xFFF3A3), ("Green", 0xBBFABB),
        ("Cyan", 0xABF7F7), ("Blue", 0xADCCFF), ("Purple", 0xD2B3FF), ("Grey", 0xCACFD9),
    ]

    // Typography
    static var editorSize: CGFloat { Prefs.editorPoints }
    static let editorLineHeight: CGFloat = 1.8
    static var editorMeasure: CGFloat { Prefs.editorMeasure }
    static func editorFont(_ size: CGFloat = editorSize, bold: Bool = false, italic: Bool = false) -> NSFont {
        let name = bold ? "IBMPlexMono-Bold" : (italic ? "IBMPlexMono-Italic" : "IBMPlexMono")
        return NSFont(name: name, size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
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
    static let faint = Color(nsColor: Theme.faint)
    static let hairline = Color(nsColor: Theme.border)
    static let cursorBlue = Color(nsColor: Theme.cursor)
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
