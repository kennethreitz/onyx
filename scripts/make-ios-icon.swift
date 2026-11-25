// Renders the iOS app icon (Resources/iOS/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png):
// the same black stone and Latin Modern "O" as scripts/make-icon.swift, but full-bleed and
// opaque, because iOS masks the corners itself and rejects transparency.
// Run: swift scripts/make-ios-icon.swift
import AppKit
import CoreText

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
CTFontManagerRegisterFontURLs([root.appendingPathComponent("Resources/fonts/LatinModernRoman12-Bold.woff2")] as CFArray, .process, false, nil)
let px = 1024
let s = CGFloat(px)
// An opaque RGB context (no alpha channel at all, which App Store icons require).
let cg = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)
let full = NSRect(x: 0, y: 0, width: s, height: s)
NSGradient(colors: [NSColor(white: 0.20, alpha: 1), NSColor(white: 0.04, alpha: 1)])!.draw(in: full, angle: -90)
// a soft polish across the top, edge to edge (iOS rounds the corners)
NSGradient(colors: [NSColor(white: 1, alpha: 0.08), NSColor(white: 1, alpha: 0)])!.draw(in: NSRect(x: 0, y: s * 0.45, width: s, height: s * 0.55), angle: -90)
let font = NSFont(name: "LMRoman12-Bold", size: s * 0.62) ?? NSFont.systemFont(ofSize: s * 0.55, weight: .bold)
let para = NSMutableParagraphStyle(); para.alignment = .center
let str = NSAttributedString(string: "O", attributes: [.font: font, .foregroundColor: NSColor(srgbRed: 0.99, green: 0.99, blue: 0.98, alpha: 1), .paragraphStyle: para])
let h = str.size().height
str.draw(in: NSRect(x: 0, y: (s - h) / 2 - s * 0.01, width: s, height: h))
NSGraphicsContext.restoreGraphicsState()
let out = root.appendingPathComponent("Resources/iOS/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")
let rep = NSBitmapImageRep(cgImage: cg.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("icon: \(out.path)")
