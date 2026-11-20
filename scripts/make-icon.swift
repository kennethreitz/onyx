// Renders Onyx's icon: a polished black stone with a serif "O", typeset in Latin Modern.
import AppKit
import CoreText

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build"
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let fontURL = root.appendingPathComponent("Resources/fonts/LatinModernRoman12-Bold.woff2")
CTFontManagerRegisterFontURLs([fontURL] as CFArray, .process, false, nil)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.18, yRadius: s * 0.18)
    NSShadow().then { $0.shadowBlurRadius = s * 0.03; $0.shadowOffset = NSSize(width: 0, height: -s * 0.012); $0.shadowColor = NSColor.black.withAlphaComponent(0.35); $0.set() }
    NSGradient(colors: [NSColor(white: 0.20, alpha: 1), NSColor(white: 0.04, alpha: 1)])!.draw(in: path, angle: -90)
    NSShadow().set()
    // a soft polish on the stone
    NSGradient(colors: [NSColor(white: 1, alpha: 0.10), NSColor(white: 1, alpha: 0)])!.draw(in: NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.02, dy: s * 0.02).offsetBy(dx: 0, dy: s * 0.12), xRadius: s * 0.16, yRadius: s * 0.16), angle: -90)
    let font = NSFont(name: "LMRoman12-Bold", size: s * 0.56) ?? NSFont.systemFont(ofSize: s * 0.5, weight: .bold)
    let para = NSMutableParagraphStyle(); para.alignment = .center
    let str = NSAttributedString(string: "O", attributes: [.font: font, .foregroundColor: NSColor(srgbRed: 0.99, green: 0.99, blue: 0.98, alpha: 1), .paragraphStyle: para])
    let size = str.size()
    str.draw(in: NSRect(x: 0, y: (s - size.height) / 2 - s * 0.01, width: s, height: size.height))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
extension NSObject { @discardableResult func then(_ f: (Self) -> Void) -> Self { f(self); return self } }

let iconset = URL(fileURLWithPath: out).appendingPathComponent("Onyx.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: iconset.appendingPathComponent("icon_\(name).png"))
}
let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", URL(fileURLWithPath: out).appendingPathComponent("Onyx.icns").path]
try! p.run(); p.waitUntilExit()
print("icon: \(out)/Onyx.icns")
