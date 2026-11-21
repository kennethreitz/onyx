// usage: click <windowID> <x> <y> [dbl | drag <x2> <y2> | cmd | shift | cmdshift]
//   points from the window's top-left; negative = from right/bottom
// Refuses to click unless that window is the topmost one under the point, so a test click
// can never land in another app.
import CoreGraphics
import Foundation
let a = CommandLine.arguments
let wid = CGWindowID(a[1])!, x = Double(a[2])!, y = Double(a[3])!
let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], wid) as! [[String: Any]]
let b = info[0][kCGWindowBounds as String] as! [String: Double]
func at(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: b["X"]! + (x < 0 ? b["Width"]! + x : x), y: b["Y"]! + (y < 0 ? b["Height"]! + y : y)) }
let p = at(x, y)
let onscreen = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
let top = onscreen.first { w in
    guard (w[kCGWindowLayer as String] as? Int) == 0, let r = w[kCGWindowBounds as String] as? [String: Double] else { return false }
    return CGRect(x: r["X"]!, y: r["Y"]!, width: r["Width"]!, height: r["Height"]!).contains(p)
}
guard (top?[kCGWindowNumber as String] as? Int).map({ CGWindowID($0) }) == wid else {
    FileHandle.standardError.write("click refused: window \(wid) is not topmost at \(p)\n".data(using: .utf8)!); exit(2)
}
func post(_ t: CGEventType, _ q: CGPoint, clicks: Int64 = 1, flags: CGEventFlags = []) {
    let e = CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: q, mouseButton: .left)!
    e.setIntegerValueField(.mouseEventClickState, value: clicks)
    e.flags = flags
    e.post(tap: .cghidEventTap)
}
let mode = a.count > 4 ? a[4] : "click"
let cmdFlags: CGEventFlags = {
    switch mode {
    case "cmd": return .maskCommand
    case "shift": return .maskShift
    case "cmdshift": return [.maskCommand, .maskShift]
    default: return []
    }
}()
post(.mouseMoved, p); usleep(250_000)
switch mode {
case "dbl":
    post(.leftMouseDown, p, clicks: 1); post(.leftMouseUp, p, clicks: 1); usleep(60_000)
    post(.leftMouseDown, p, clicks: 2); post(.leftMouseUp, p, clicks: 2)
case "drag":
    let q = at(Double(a[5])!, Double(a[6])!)
    post(.leftMouseDown, p); usleep(80_000)
    for i in 1...20 { let t = Double(i) / 20; post(.leftMouseDragged, CGPoint(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t)); usleep(16_000) }
    post(.leftMouseUp, q)
default:
    post(.leftMouseDown, p, flags: cmdFlags); usleep(60_000); post(.leftMouseUp, p, flags: cmdFlags)
}
usleep(90_000)
