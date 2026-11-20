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
