// usage: key <pid> <keycode> [cmd|shift|ctrl|opt ...]  — posts one keystroke to that process only
import CoreGraphics
import Foundation
let a = CommandLine.arguments
let pid = pid_t(a[1])!
let code = CGKeyCode(a[2])!
var flags: CGEventFlags = []
for m in a.dropFirst(3) { switch m { case "cmd": flags.insert(.maskCommand); case "shift": flags.insert(.maskShift); case "ctrl": flags.insert(.maskControl); case "opt": flags.insert(.maskAlternate); default: break } }
for down in [true, false] {
    let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
    e.flags = flags; e.postToPid(pid); usleep(60_000)
}
