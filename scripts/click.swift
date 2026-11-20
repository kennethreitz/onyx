// usage: click <windowID> <x> <y>   (points from the window's top-left; negative = from right/bottom)
import CoreGraphics
import Foundation
let a = CommandLine.arguments
let wid = CGWindowID(a[1])!, x = Double(a[2])!, y = Double(a[3])!
let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], wid) as! [[String: Any]]
let b = info[0][kCGWindowBounds as String] as! [String: Double]
// negative values measure from the right / bottom edge
let p = CGPoint(x: b["X"]! + (x < 0 ? b["Width"]! + x : x), y: b["Y"]! + (y < 0 ? b["Height"]! + y : y))
for t in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
    CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap)
    usleep(90_000)
}
