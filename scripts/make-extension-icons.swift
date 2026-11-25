// Renders the Safari extension's icons into Extensions/Safari/Resources/images (committed):
//   icon-<n>.png     the app icon (Resources/AppIcon.icns, the onyx crystal with its note
//                    graph), cropped to its rounded tile, for the manifest "icons" Safari shows
//                    in Settings ▸ Extensions
//   toolbar-<n>.png  a monochrome crystal on transparency, with the note graph cut out, for the
//                    toolbar button. Safari uses toolbar icons as templates (only the alpha
//                    counts) and tints them for light, dark, and active toolbars; the full-color
//                    icon there renders as a flat grey square.
// Run: swift scripts/make-extension-icons.swift
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let out = root.appendingPathComponent("Extensions/Safari/Resources/images")
let appIcon = NSImage(contentsOf: root.appendingPathComponent("Resources/AppIcon.icns"))!

func bitmap(_ px: Int, _ draw: (CGFloat) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.imageInterpolation = .high
    draw(CGFloat(px))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

/// The app icon without macOS's transparent margin (the tile spans 10%–90% of the canvas), so
/// it reads at Safari's small sizes.
func tile(_ s: CGFloat) {
    let size = appIcon.size  // points (512 for a 1024px @2x icon)
    let src = NSRect(origin: .zero, size: size).insetBy(dx: size.width * 0.1, dy: size.height * 0.1)
    appIcon.draw(in: NSRect(x: 0, y: 0, width: s, height: s), from: src, operation: .sourceOver, fraction: 1,
                 respectFlipped: false, hints: [.ctm: NSAffineTransform(), .interpolation: NSImageInterpolation.high.rawValue])
}

// The crystal and its note graph, in the 1024px app icon's coordinates (y down).
let crystal: [CGPoint] = [(512, 203), (690, 340), (763, 513), (706, 684), (515, 815), (330, 690), (266, 510), (340, 340)].map { CGPoint(x: $0.0, y: $0.1) }
let nodes: [CGPoint] = [(418, 402), (609, 437), (515, 520), (397, 610), (636, 612)].map { CGPoint(x: $0.0, y: $0.1) }
let edges = [(0, 1), (0, 2), (1, 2), (0, 3), (3, 2), (2, 4), (1, 4)]

/// Toolbar glyph, black on transparency: the crystal's outline with the note graph inside
/// (lines and nodes), like the app icon's, drawn heavy enough to hold up at 16px.
func glyph(_ s: CGFloat) {
    let k = s * 0.92 / 612, cx: CGFloat = 514, cy: CGFloat = 509
    func p(_ q: CGPoint) -> NSPoint { NSPoint(x: s / 2 + (q.x - cx) * k, y: s / 2 - (q.y - cy) * k) }
    NSColor.black.set()
    let body = NSBezierPath()
    body.move(to: p(crystal[0])); crystal.dropFirst().forEach { body.line(to: p($0)) }; body.close()
    body.lineWidth = max(1.25, s * 0.075); body.lineJoinStyle = .round
    body.stroke()
    let lines = NSBezierPath(); lines.lineWidth = max(1, s * 0.04); lines.lineCapStyle = .round
    for (a, b) in edges { lines.move(to: p(nodes[a])); lines.line(to: p(nodes[b])) }
    lines.stroke()
    let r = max(1.2, s * 0.065)
    for n in nodes { let c = p(n); NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).fill() }
}

try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for px in [16, 19, 32, 38, 48, 64, 96, 128, 256, 512] {
    try! bitmap(px, tile).write(to: out.appendingPathComponent("icon-\(px).png"))
}
for px in [16, 19, 32, 38, 48, 64] {
    try! bitmap(px, glyph).write(to: out.appendingPathComponent("toolbar-\(px).png"))
}
print("icons: \(out.path)")
