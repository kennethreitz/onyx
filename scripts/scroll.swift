// usage: scroll <pid> <windowID> <x> <y> <lines>  — posts wheel events to that process only,
// positioned over the given window point (negative x/y measure from the right/bottom).
import CoreGraphics
import Foundation
let a = CommandLine.arguments
let pid = pid_t(a[1])!, wid = CGWindowID(a[2])!, x = Double(a[3])!, y = Double(a[4])!, lines = Int32(a[5])!
let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], wid) as! [[String: Any]]
let b = info[0][kCGWindowBounds as String] as! [String: Double]
let p = CGPoint(x: b["X"]! + (x < 0 ? b["Width"]! + x : x), y: b["Y"]! + (y < 0 ? b["Height"]! + y : y))
for _ in 0..<abs(lines) {
    let e = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines > 0 ? -3 : 3, wheel2: 0, wheel3: 0)!
    e.location = p
    e.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(wid))
    e.postToPid(pid); usleep(16_000)
}
