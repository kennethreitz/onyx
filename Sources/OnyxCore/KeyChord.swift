import Foundation

/// Modifier flags that belong on a keyboard shortcut. Raw values are stable in UserDefaults.
public struct KeyModifiers: OptionSet, Hashable, Sendable, Codable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let shift   = KeyModifiers(rawValue: 1 << 1)
    public static let option  = KeyModifiers(rawValue: 1 << 2)
    public static let control = KeyModifiers(rawValue: 1 << 3)
}

/// One key combination, such as ⌘O or ⌃⇧⇥.
public struct KeyChord: Hashable, Sendable, Codable {
    /// The key equivalent, stored lowercase for letters. Special keys use
    /// `"\u{7F}"` (delete), `"\r"` (return), `"\t"` (tab), `" "` (space), `"\u{1b}"` (escape).
    public var key: String
    public var modifiers: KeyModifiers

    public init(key: String, modifiers: KeyModifiers) {
        self.key = Self.normalize(key)
        self.modifiers = modifiers
    }

    /// ⌘ plus `key`, with optional extra modifiers.
    public static func command(_ key: String, shift: Bool = false, option: Bool = false, control: Bool = false) -> KeyChord {
        var m: KeyModifiers = .command
        if shift { m.insert(.shift) }
        if option { m.insert(.option) }
        if control { m.insert(.control) }
        return KeyChord(key: key, modifiers: m)
    }

    public static func chord(_ key: String, _ modifiers: KeyModifiers) -> KeyChord {
        KeyChord(key: key, modifiers: modifiers)
    }

    public var display: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        s += keyGlyph
        return s
    }

    public var keyGlyph: String {
        switch key {
        case "\u{7F}", "\u{08}": return "⌫"
        case "\r": return "↩"
        case "\t": return "⇥"
        case " ": return "Space"
        case "\u{1b}": return "Esc"
        case "\u{F700}": return "↑"
        case "\u{F701}": return "↓"
        case "\u{F702}": return "←"
        case "\u{F703}": return "→"
        default: return key.uppercased()
        }
    }

    /// Build a chord from a key event. Returns nil for modifier-only presses and unknown keys.
    public init?(charactersIgnoringModifiers: String?, keyCode: UInt16, modifiers: KeyModifiers) {
        let key: String
        switch keyCode {
        case 51: key = "\u{7F}"           // kVK_Delete (⌫)
        case 36, 76: key = "\r"           // return / keypad enter
        case 48: key = "\t"
        case 53: key = "\u{1b}"
        case 49: key = " "
        case 126: key = "\u{F700}"        // up
        case 125: key = "\u{F701}"
        case 123: key = "\u{F702}"
        case 124: key = "\u{F703}"
        default:
            guard let raw = charactersIgnoringModifiers, let ch = raw.first, ch.isASCII || ch == "\\" else { return nil }
            guard !ch.isWhitespace || ch == " " else { return nil }
            let s = String(ch)
            guard s != "" else { return nil }
            key = s
        }
        // A shortcut needs a real key, not just held modifiers.
        if key.isEmpty { return nil }
        self.init(key: key, modifiers: modifiers)
    }

    public func matches(charactersIgnoringModifiers: String?, keyCode: UInt16, modifiers: KeyModifiers) -> Bool {
        KeyChord(charactersIgnoringModifiers: charactersIgnoringModifiers, keyCode: keyCode, modifiers: modifiers) == self
    }

    private static func normalize(_ key: String) -> String {
        if key.count == 1, let ch = key.first, ch.isLetter { return key.lowercased() }
        if key == "\u{08}" { return "\u{7F}" }
        return key
    }
}

extension KeyChord {
    /// System and standard editing combinations we warn about before assigning.
    public static let reserved: [(KeyChord, String)] = [
        (.command("q"), "Quit"),
        (.command("h"), "Hide Onyx"),
        (.command("h", option: true), "Hide Others"),
        (.command("m"), "Minimize"),
        (.command(","), "Settings"),
        (.command(" "), "Spotlight"),
        (.chord("\t", .command), "Switch apps"),
        (.command("`"), "Cycle windows"),
        (.command("c"), "Copy"),
        (.command("v"), "Paste"),
        (.command("x"), "Cut"),
        (.command("a"), "Select All"),
        (.command("z"), "Undo"),
        (.command("z", shift: true), "Redo"),
        (.command("\u{7F}"), "Delete to Beginning of Line"),
        (.chord("\u{7F}", .option), "Delete Word Backward"),
    ]

    public static func reservedReason(_ chord: KeyChord) -> String? {
        reserved.first(where: { $0.0 == chord })?.1
    }

    public var isReserved: Bool { Self.reservedReason(self) != nil }

    /// ⌘⌫ and ⌥⌫ belong to the text system (delete to the start of the line,
    /// delete the previous word). A menu item with either as its key equivalent
    /// would steal them from the editor and from text fields.
    public var yieldsToTextInput: Bool {
        (key == "\u{7F}" || key == "\u{08}") && (modifiers == .command || modifiers == .option)
    }
}
