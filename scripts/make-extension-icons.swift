// Renders the Safari extension's icons into Extensions/Safari/Resources/images (committed):
//   icon-<n>.png     the full-color Onyx stone (same drawing as make-icon.swift), for the
//                    manifest "icons" Safari shows in Settings ▸ Extensions
//   toolbar-<n>.png  a monochrome serif "O" on transparency for the toolbar button. Safari
//                    tints single-color toolbar icons to match the toolbar (light, dark,
//                    active); the full stone there renders as a flat grey square.
// Run: swift scripts/make-extension-icons.swift
import AppKit
import CoreText

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let out = root.appendingPathComponent("Extensions/Safari/Resources/images")
CTFontManagerRegisterFontURLs([root.appendingPathComponent("Resources/fonts/LatinModernRoman12-Bold.woff2")] as CFArray, .process, false, nil)

func bitmap(_ px: Int, _ draw: (CGFloat) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGFloat(px))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func font(_ size: CGFloat) -> NSFont { NSFont(name: "LMRoman12-Bold", size: size) ?? NSFont.systemFont(ofSize: size, weight: .bold) }

func centeredO(_ s: CGFloat, size: CGFloat, color: NSColor, dy: CGFloat = 0) {
    let para = NSMutableParagraphStyle(); para.alignment = .center
    let str = NSAttributedString(string: "O", attributes: [.font: font(size), .foregroundColor: color, .paragraphStyle: para])
    let h = str.size().height
    str.draw(in: NSRect(x: 0, y: (s - h) / 2 + dy, width: s, height: h))
}

/// The app icon's stone (scripts/make-icon.swift), without the outer drop-shadow margin so it
/// reads at small sizes.
func stone(_ s: CGFloat) {
    let inset = s * 0.04
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.2, yRadius: s * 0.2)
    NSGradient(colors: [NSColor(white: 0.20, alpha: 1), NSColor(white: 0.04, alpha: 1)])!.draw(in: path, angle: -90)
    NSGradient(colors: [NSColor(white: 1, alpha: 0.10), NSColor(white: 1, alpha: 0)])!.draw(in: NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.02, dy: s * 0.02).offsetBy(dx: 0, dy: s * 0.12), xRadius: s * 0.18, yRadius: s * 0.18), angle: -90)
    centeredO(s, size: s * 0.66, color: NSColor(srgbRed: 0.99, green: 0.99, blue: 0.98, alpha: 1), dy: -s * 0.01)
}

/// Toolbar glyph: the same serif O, black on transparency, nearly filling the square.
func glyph(_ s: CGFloat) {
    centeredO(s, size: s * 1.02, color: .black, dy: -s * 0.02)
}

try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for px in [16, 19, 32, 38, 48, 64, 96, 128, 256, 512] {
    try! bitmap(px, stone).write(to: out.appendingPathComponent("icon-\(px).png"))
}
for px in [16, 19, 32, 38, 48, 64] {
    try! bitmap(px, glyph).write(to: out.appendingPathComponent("toolbar-\(px).png"))
}
print("icons: \(out.path)")
