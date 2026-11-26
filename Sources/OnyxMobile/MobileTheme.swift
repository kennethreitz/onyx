import SwiftUI
import UIKit

/// The same paper/ink palette as the Mac app, expressed with `UIColor` so the
/// graph and atlas can paint on iOS. Hex values are copied from `Theme` in
/// `Sources/Onyx/Theme.swift`.
enum MobileTheme {
    static func dyn(_ light: UInt32, _ dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat? = nil) -> Color {
        Color(uiColor: UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            return UIColor(hex: isDark ? dark : light, alpha: isDark ? (darkAlpha ?? lightAlpha) : lightAlpha)
        })
    }

    static func serif(_ size: CGFloat, bold: Bool = false, italic: Bool = false) -> Font {
        var font = Font.system(size: size, design: .serif)
        if bold { font = font.bold() }
        if italic { font = font.italic() }
        return font
    }

    static func titleSerif(_ size: CGFloat) -> Font {
        Font.system(size: size, weight: .bold, design: .serif)
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let r = CGFloat((hex >> 16) & 0xff) / 255.0
        let g = CGFloat((hex >> 8) & 0xff) / 255.0
        let b = CGFloat(hex & 0xff) / 255.0
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}

extension Color {
    static let paper = MobileTheme.dyn(0xfdfdfb, 0x1b1b19)
    static let ink = MobileTheme.dyn(0x1a1a18, 0xe9e8e1)
    static let muted = MobileTheme.dyn(0x565650, 0xb3b2a9)
    static let faint = MobileTheme.dyn(0x7f7f78, 0x7f7e76)
    static let hairline = MobileTheme.dyn(0xdedcd2, 0x34332e)
    static let cursorBlue = MobileTheme.dyn(0x5a7a9e, 0x7aa8cc)
}

/// Stable, muted cluster colors — the same hash, probe, and hues as the Mac
/// `ClusterPalette`. Slate blue stays reserved for the current note.
enum ClusterPalette {
    static let pairs: [(UInt32, UInt32)] = [
        (0xA0573A, 0xDE9474),
        (0x94741C, 0xD6B65E),
        (0x667634, 0xB0C072),
        (0x3F7A5C, 0x82C49E),
        (0x2C7775, 0x72C3BF),
        (0x6A5A9A, 0xAE9EE0),
        (0x8E4F7E, 0xD08FC0),
        (0xA34B5C, 0xE38E9E),
    ]

    static func index(_ key: String) -> Int {
        var h: UInt64 = 0xcbf29ce484222325
        for b in key.lowercased().utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return Int(h % UInt64(pairs.count))
    }

    nonisolated(unsafe) static var slots: [String: Int] = [:]

    static func assign(_ keysBySize: [String]) {
        let n = pairs.count
        var used: [Int] = [], out = slots
        func dist(_ a: Int, _ b: Int) -> Int { let d = abs(a - b) % n; return min(d, n - d) }
        for k in keysBySize {
            let h = index(k)
            let order = (0..<n).map { (h + $0) % n }
            let pick = order.first { c in used.allSatisfy { dist($0, c) >= 2 } }
                ?? order.first { !used.contains($0) } ?? h
            used.append(pick)
            out[k.lowercased()] = pick
        }
        slots = out
    }

    static func color(_ key: String) -> Color {
        let p = pairs[slots[key.lowercased()] ?? index(key)]
        return MobileTheme.dyn(p.0, p.1)
    }
}
