// usage: click <windowID> <x> <y>   (points from the window's top-left; negative = from right/bottom)
// Refuses to click unless that window is the topmost one under the point, so a test click
// can never land in another app.
import CoreGraphics
import Foundation
let a = CommandLine.arguments
let wid = CGWindowID(a[1])!, x = Double(a[2])!, y = Double(a[3])!
let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], wid) as! [[String: Any]]
let b = info[0][kCGWindowBounds as String] as! [String: Double]
let p = CGPoint(x: b["X"]! + (x < 0 ? b["Width"]! + x : x), y: b["Y"]! + (y < 0 ? b["Height"]! + y : y))
let onscreen = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
let top = onscreen.first { w in
    guard (w[kCGWindowLayer as String] as? Int) == 0, let r = w[kCGWindowBounds as String] as? [String: Double] else { return false }
    return CGRect(x: r["X"]!, y: r["Y"]!, width: r["Width"]!, height: r["Height"]!).contains(p)
}
guard (top?[kCGWindowNumber as String] as? Int).map({ CGWindowID($0) }) == wid else {
    FileHandle.standardError.write("click refused: window \(wid) is not topmost at \(p)\n".data(using: .utf8)!); exit(2)
}
for t in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
    CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap)
    usleep(90_000)
}
