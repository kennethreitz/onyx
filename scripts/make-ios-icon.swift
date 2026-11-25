// Renders the iOS app icon, Resources/iOS/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png,
// from the Mac app icon (Resources/AppIcon.icns: the onyx crystal with its note graph).
// iOS wants one opaque, full-bleed 1024px square and rounds the corners itself, so the Mac
// icon's rounded tile (10%–90% of its canvas) is scaled to fill the square over the tile's own
// dark diagonal gradient, which fills in the tile's
// transparent corners.
// Run: swift scripts/make-ios-icon.swift
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let out = root.appendingPathComponent("Resources/iOS/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
let appIcon = NSImage(contentsOf: root.appendingPathComponent("Resources/AppIcon.icns"))!
let px = 1024, s = CGFloat(px)

// Opaque (no alpha channel): App Store Connect rejects icons with one.
let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.interpolationQuality = .high
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
// The tile's background behind the transparent corners: its colors just inside each rounded
// corner (sampled from the 1024px icon), blended bilinearly across the square.
let rep = appIcon.representations.compactMap { $0 as? NSBitmapImageRep }.max { $0.pixelsWide < $1.pixelsWide }!
func near(_ fx: CGFloat, _ fy: CGFloat) -> NSColor {  // fractions of the canvas, y down
    rep.colorAt(x: Int(fx * CGFloat(rep.pixelsWide)), y: Int(fy * CGFloat(rep.pixelsHigh)))!.usingColorSpace(.sRGB)!
}
let bg = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                   space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
for (x, y, c) in [(0, 1, near(0.17, 0.17)), (1, 1, near(0.83, 0.17)), (0, 0, near(0.17, 0.83)), (1, 0, near(0.83, 0.83))] {
    bg.setFillColor(c.cgColor); bg.fill(CGRect(x: x, y: y, width: 1, height: 1))
}
ctx.draw(bg.makeImage()!, in: CGRect(x: 0, y: 0, width: s, height: s))
let size = appIcon.size
let tile = NSRect(origin: .zero, size: size).insetBy(dx: size.width * 0.105, dy: size.height * 0.105)
// Clip just inside the tile's rounded corners so its thin light rim doesn't show as an arc.
NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: s, height: s), xRadius: s * 0.25, yRadius: s * 0.25).addClip()
appIcon.draw(in: NSRect(x: 0, y: 0, width: s, height: s), from: tile, operation: .sourceOver, fraction: 1,
             respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high.rawValue])
NSGraphicsContext.restoreGraphicsState()
let png = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
try! png.write(to: out)
print(out.path)
