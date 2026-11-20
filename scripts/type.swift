// usage: type <pid> <text>  — types the text into that process only (unicode, one character at a time)
import CoreGraphics
import Foundation
let a = CommandLine.arguments
let pid = pid_t(a[1])!
for ch in a[2] {
    let u = Array(String(ch).utf16)
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)!
        e.keyboardSetUnicodeString(stringLength: u.count, unicodeString: u)
        e.postToPid(pid); usleep(25_000)
    }
}
