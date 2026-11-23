import Foundation

/// Reading and writing Obsidian's per-vault config files (`.obsidian/app.json`, `daily-notes.json`,
/// `templates.json`) without disturbing what Obsidian or Obsidian Sync put there: unknown keys keep
/// their place and their exact text, unchanged values are copied byte for byte, and new keys go at the
/// end, in Obsidian's own `JSON.stringify(…, null, 2)` shape.
public enum ObsidianConfig {
    public enum ConfigError: Error, Equatable {
        /// The file on disk isn't a JSON object; Onyx won't overwrite it.
        case notAnObject
    }

    /// The config files Onyx reads and edits, watched for outside changes (Obsidian, Sync).
    public static let watchedFiles: Set<String> = ["app.json", "daily-notes.json", "templates.json"]

    public static func parse(_ data: Data?) -> [String: Any]? {
        guard let data, let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return o
    }

    /// Top-level keys of a JSON object in file order, with the exact source text of each value.
    static func topLevelEntries(_ text: String) -> [(key: String, raw: String)]? {
        let s = Array(text.utf8)
        var i = 0
        func skipWS() { while i < s.count, s[i] == 0x20 || s[i] == 0x0A || s[i] == 0x0D || s[i] == 0x09 { i += 1 } }
        func scanString() -> Bool {   // at the opening quote; leaves i past the closing quote
            guard i < s.count, s[i] == 0x22 else { return false }
            i += 1
            while i < s.count {
                if s[i] == 0x5C { i += 2; continue }
                if s[i] == 0x22 { i += 1; return true }
                i += 1
            }
            return false
        }
        func scanValue() -> Bool {
            skipWS()
            guard i < s.count else { return false }
            if s[i] == 0x22 { return scanString() }
            if s[i] == 0x7B || s[i] == 0x5B {
                var depth = 0
                while i < s.count {
                    let c = s[i]
                    if c == 0x22 { if !scanString() { return false }; continue }
                    if c == 0x7B || c == 0x5B { depth += 1 }
                    if c == 0x7D || c == 0x5D { depth -= 1; if depth == 0 { i += 1; return true } }
                    i += 1
                }
                return false
            }
            while i < s.count, ![0x2C, 0x7D, 0x5D, 0x20, 0x0A, 0x0D, 0x09].contains(s[i]) { i += 1 }
            return true
        }
        skipWS()
        guard i < s.count, s[i] == 0x7B else { return nil }
        i += 1
        var out: [(String, String)] = []
        while true {
            skipWS()
            guard i < s.count else { return nil }
            if s[i] == 0x7D { return out }
            if s[i] == 0x2C { i += 1; continue }
            let ks = i
            guard scanString() else { return nil }
            guard let key = try? JSONSerialization.jsonObject(with: Data(s[ks..<i]), options: .fragmentsAllowed) as? String else { return nil }
            skipWS()
            guard i < s.count, s[i] == 0x3A else { return nil }
            i += 1
            skipWS()
            let vs = i
            guard scanValue() else { return nil }
            out.append((key, String(decoding: s[vs..<i], as: UTF8.self)))
        }
    }

    /// A value as Obsidian would write it at the top level of a config file (2-space indent).
    static func encode(_ value: Any) -> String {
        let opts: JSONSerialization.WritingOptions = [.fragmentsAllowed, .prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        guard let d = try? JSONSerialization.data(withJSONObject: value, options: opts) else { return "null" }
        let text = String(decoding: d, as: UTF8.self)
        // Nested lines sit one level deeper inside the file's top-level object.
        return text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            .map { $0.offset == 0 ? String($0.element) : "  " + $0.element }.joined(separator: "\n")
    }

    static func same(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?):
            if let xb = x as? NSNumber, let yb = y as? NSNumber,
               CFGetTypeID(xb) == CFBooleanGetTypeID(), CFGetTypeID(yb) == CFBooleanGetTypeID() { return xb.boolValue == yb.boolValue }
            return (x as AnyObject).isEqual(y)
        default: return false
        }
    }

    /// Apply `changes` (a nil value removes the key) to the file's text. Returns nil when nothing
    /// would change. Unchanged entries keep their exact text and order; new keys are appended.
    public static func updatedText(original: String?, changes: [String: Any?]) throws -> String? {
        let text = original?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let current: [String: Any]
        let entries: [(key: String, raw: String)]
        if text.isEmpty { current = [:]; entries = [] }
        else {
            guard let o = parse(Data(text.utf8)), let e = topLevelEntries(text) else { throw ConfigError.notAnObject }
            current = o; entries = e
        }
        let effective = changes.filter { !same(current[$0.key], $0.value) }
        if effective.isEmpty { return nil }
        var lines: [String] = []
        var seen = Set<String>()
        for (key, raw) in entries where !seen.contains(key) {
            seen.insert(key)
            if let change = effective[key] {
                if let v = change { lines.append("  \(encode(key)): \(encode(v))") }
            } else {
                lines.append("  \(encode(key)): \(raw)")
            }
        }
        for key in effective.keys.sorted() where !seen.contains(key) {
            if let v = effective[key] ?? nil { lines.append("  \(encode(key)): \(encode(v))") }
        }
        return lines.isEmpty ? "{}" : "{\n" + lines.joined(separator: ",\n") + "\n}"
    }

    /// Read-modify-write `url` atomically, creating it (and `.obsidian`) when missing.
    /// Returns false when nothing needed writing.
    @discardableResult
    public static func update(_ url: URL, changes: [String: Any?]) throws -> Bool {
        let original = try? String(contentsOf: url, encoding: .utf8)
        guard let text = try updatedText(original: original, changes: changes) else { return false }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: .atomic)
        return true
    }
}

/// "Default location for new attachments" (`attachmentFolderPath`), as Obsidian's picker shows it.
public enum AttachmentLocation: Equatable {
    case vaultRoot, sameFolder, subfolder(String), folder(String)

    public init(setting: String?) {
        let s = (setting ?? "").trimmingCharacters(in: .whitespaces)
        if s.isEmpty || s == "/" { self = .vaultRoot }
        else if s == "." || s == "./" { self = .sameFolder }
        else if s.hasPrefix("./") { self = .subfolder(String(s.dropFirst(2)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))) }
        else { self = .folder(s.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) }
    }

    /// The `attachmentFolderPath` value Obsidian writes for this choice.
    public var setting: String {
        switch self {
        case .vaultRoot: return "/"
        case .sameFolder: return "./"
        case .subfolder(let n): return n.isEmpty ? "./" : "./" + n
        case .folder(let f): return f.isEmpty ? "/" : f
        }
    }

    public var kind: String {
        switch self {
        case .vaultRoot: "root"
        case .sameFolder: "current"
        case .subfolder: "subfolder"
        case .folder: "folder"
        }
    }
}

/// "Default location for new notes" (`newFileLocation`, `newFileFolderPath`).
public enum NewNoteLocation {
    /// Folder for a new note. `contextual` is what Onyx would pick on its own (the selected folder,
    /// else the open note's); it's used for "current" and when app.json doesn't say.
    public static func folder(location: String?, folderPath: String?, contextual: String) -> String {
        switch location {
        case "root": return ""
        case "folder": return vaultFolder(folderPath ?? "")
        default: return contextual
        }
    }
}

/// Validating a vault-relative folder or file typed into Settings.
public func vaultFolder(_ raw: String) -> String {
    raw.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
}

public enum VaultPathCheck: Equatable {
    case ok, empty, outsideVault, invalidCharacters
    public static func check(_ raw: String) -> VaultPathCheck {
        let p = vaultFolder(raw)
        if p.isEmpty { return .empty }
        if raw.hasPrefix("~") || p.split(separator: "/").contains(where: { $0 == ".." || $0 == "." }) { return .outsideVault }
        if p.rangeOfCharacter(from: CharacterSet(charactersIn: "*\"\\<>:|?")) != nil { return .invalidCharacters }
        return .ok
    }
}

/// Obsidian's dates are moment.js formats (`YYYY-MM-DD`, `dddd, MMMM Do YYYY`). This formats them
/// token by token, and turns them into an ICU pattern for parsing daily-note names back into dates.
public enum MomentFormat {
    enum Piece: Equatable { case literal(String), icu(String), ordinalDay, unix, unixMillis }

    static let tokens: [(String, Piece)] = [
        ("YYYY", .icu("yyyy")), ("YY", .icu("yy")), ("Y", .icu("y")),
        ("GGGG", .icu("YYYY")), ("gggg", .icu("YYYY")), ("GG", .icu("YY")), ("gg", .icu("YY")),
        ("Qo", .icu("Q")), ("Q", .icu("Q")),
        ("MMMM", .icu("MMMM")), ("MMM", .icu("MMM")), ("MM", .icu("MM")), ("Mo", .icu("M")), ("M", .icu("M")),
        ("DDDD", .icu("DDD")), ("DDD", .icu("D")), ("DD", .icu("dd")), ("Do", .ordinalDay), ("D", .icu("d")),
        ("dddd", .icu("EEEE")), ("ddd", .icu("EEE")), ("dd", .icu("EEEEEE")), ("d", .icu("e")),
        ("E", .icu("e")), ("e", .icu("e")),
        ("WW", .icu("ww")), ("W", .icu("w")), ("ww", .icu("ww")), ("w", .icu("w")),
        ("HH", .icu("HH")), ("H", .icu("H")), ("hh", .icu("hh")), ("h", .icu("h")), ("kk", .icu("kk")), ("k", .icu("k")),
        ("mm", .icu("mm")), ("m", .icu("m")), ("ss", .icu("ss")), ("s", .icu("s")),
        ("SSS", .icu("SSS")), ("SS", .icu("SS")), ("S", .icu("S")),
        ("A", .icu("a")), ("a", .icu("a")),
        ("ZZ", .icu("xx")), ("Z", .icu("xxx")),
        ("X", .unix), ("x", .unixMillis),
    ]

    static func pieces(_ format: String) -> [Piece] {
        var out: [Piece] = []
        var rest = Substring(format)
        func lit(_ s: String) {
            if case .literal(let prev)? = out.last { out[out.count - 1] = .literal(prev + s) } else { out.append(.literal(s)) }
        }
        while !rest.isEmpty {
            if rest.first == "[" {
                if let close = rest.firstIndex(of: "]") {
                    lit(String(rest[rest.index(after: rest.startIndex)..<close])); rest = rest[rest.index(after: close)...]; continue
                }
            }
            if let (t, p) = tokens.first(where: { rest.hasPrefix($0.0) }) {
                out.append(p); rest = rest.dropFirst(t.count); continue
            }
            lit(String(rest.first!)); rest = rest.dropFirst()
        }
        return out
    }

    static func formatter(_ pattern: String, _ timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = timeZone
        f.dateFormat = pattern
        return f
    }

    static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 100, n % 10) {
        case (11...13, _): suffix = "th"
        case (_, 1): suffix = "st"
        case (_, 2): suffix = "nd"
        case (_, 3): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }

    public static func format(_ date: Date, _ format: String, timeZone: TimeZone = .current) -> String {
        var out = ""
        for p in pieces(format) {
            switch p {
            case .literal(let s): out += s
            case .icu(let pat): out += formatter(pat, timeZone).string(from: date)
            case .ordinalDay:
                var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
                out += ordinal(cal.component(.day, from: date))
            case .unix: out += String(Int(date.timeIntervalSince1970))
            case .unixMillis: out += String(Int(date.timeIntervalSince1970 * 1000))
            }
        }
        return out
    }

    /// The ICU pattern for `format`, or nil when it can't be parsed back (ordinals, Unix time).
    public static func icuPattern(_ format: String) -> String? {
        var out = ""
        for p in pieces(format) {
            switch p {
            case .literal(let s):
                out += s.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) || $0 == "'" })
                    ? "'" + s.replacingOccurrences(of: "'", with: "''") + "'" : s
            case .icu(let pat): out += pat
            case .ordinalDay, .unix, .unixMillis: return nil
            }
        }
        return out
    }

    /// A date from text written with `format` (strict: it has to format back to the same text).
    public static func parse(_ text: String, _ format: String, timeZone: TimeZone = .current) -> Date? {
        guard let pat = icuPattern(format) else { return nil }
        let f = formatter(pat, timeZone)
        f.isLenient = false
        guard let d = f.date(from: text), self.format(d, format, timeZone: timeZone) == text else { return nil }
        return d
    }
}
