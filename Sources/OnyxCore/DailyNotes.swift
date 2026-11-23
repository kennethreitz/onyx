import Foundation

public enum DailyNotes {
    public static let defaultFormat = "YYYY-MM-DD"

    /// Obsidian's Daily notes settings (`.obsidian/daily-notes.json`); missing keys → Obsidian's defaults.
    public struct Settings: Equatable {
        /// `format`: a moment.js format; may contain `/` to nest notes in dated folders.
        public var format: String
        /// `folder`: vault folder for new daily notes ("" = vault root).
        public var folder: String
        /// `template`: vault path of the template note, without or with `.md` ("" = Onyx's built-in shape).
        public var template: String
        /// `autorun`: open today's note when the vault opens.
        public var autorun: Bool

        public init(format: String = DailyNotes.defaultFormat, folder: String = "", template: String = "", autorun: Bool = false) {
            self.format = format; self.folder = folder; self.template = template; self.autorun = autorun
        }

        public init(json: [String: Any]?) {
            let j = json ?? [:]
            let f = (j["format"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            self.init(format: f.isEmpty ? DailyNotes.defaultFormat : f,
                      folder: vaultFolder(j["folder"] as? String ?? ""),
                      template: (j["template"] as? String ?? "").trimmingCharacters(in: .whitespaces),
                      autorun: j["autorun"] as? Bool ?? false)
        }

        /// Vault path of the template note, or nil when none is set.
        public var templatePath: String? {
            let t = vaultFolder(template)
            if t.isEmpty { return nil }
            return t.lowercased().hasSuffix(".md") ? t : t + ".md"
        }
    }

    public static func fileName(for date: Date, format: String = defaultFormat) -> String {
        MomentFormat.format(date, format) + ".md"
    }
    public static func path(for date: Date, folder: String, format: String = defaultFormat) -> String {
        let f = vaultFolder(folder)
        return f.isEmpty ? fileName(for: date, format: format) : f + "/" + fileName(for: date, format: format)
    }
    public static func path(for date: Date, settings: Settings) -> String {
        path(for: date, folder: settings.folder, format: settings.format)
    }
    /// The vault's own daily-note shape: `class: DailyNote` frontmatter and a long-date H1.
    public static func template(for date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "EEEE, MMMM d, yyyy"
        return "---\nclass: DailyNote\n---\n# \(f.string(from: date))\n\n"
    }
    public static func date(fromFileName name: String, format: String = defaultFormat) -> Date? {
        MomentFormat.parse((name as NSString).deletingPathExtension, format)
    }
    /// The date of a daily note at vault path `path`, or nil when it isn't one under these settings.
    public static func date(ofPath path: String, settings: Settings) -> Date? {
        guard path.lowercased().hasSuffix(".md") else { return nil }
        var rel = path
        if !settings.folder.isEmpty {
            guard path.hasPrefix(settings.folder + "/") else { return nil }
            rel = String(path.dropFirst(settings.folder.count + 1))
        }
        return MomentFormat.parse(String(rel.dropLast(3)), settings.format)
    }

    /// Fill a template the way Obsidian's Daily notes does: `{{date}}` and `{{title}}` are the note's
    /// date in the daily format, `{{time}}` is the time now, and `{{date:FORMAT}}` / `{{time:FORMAT}}`
    /// take their own moment format.
    public static func expand(template: String, date: Date, title: String, dateFormat: String,
                              timeFormat: String = "HH:mm", now: Date = Date()) -> String {
        guard template.contains("{{") else { return template }
        let re = try! NSRegularExpression(pattern: #"\{\{\s*(date|time|title)\s*(?::(.*?))?\s*\}\}"#, options: [.caseInsensitive])
        let ns = template as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: template, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let kind = ns.substring(with: m.range(at: 1)).lowercased()
            let fmt = m.range(at: 2).location == NSNotFound ? nil : ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
            switch kind {
            case "title": out += title
            case "time": out += MomentFormat.format(now, fmt ?? timeFormat)
            default: out += MomentFormat.format(date, fmt ?? dateFormat)
            }
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }
}

/// Obsidian's Templates settings (`.obsidian/templates.json`).
public struct TemplateSettings: Equatable {
    public static let defaultDateFormat = "YYYY-MM-DD"
    public static let defaultTimeFormat = "HH:mm"
    public var folder: String
    public var dateFormat: String
    public var timeFormat: String

    public init(folder: String = "", dateFormat: String = defaultDateFormat, timeFormat: String = defaultTimeFormat) {
        self.folder = folder; self.dateFormat = dateFormat; self.timeFormat = timeFormat
    }
    public init(json: [String: Any]?) {
        let j = json ?? [:]
        func s(_ k: String, _ d: String) -> String {
            let v = (j[k] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            return v.isEmpty ? d : v
        }
        self.init(folder: vaultFolder(j["folder"] as? String ?? ""),
                  dateFormat: s("dateFormat", Self.defaultDateFormat), timeFormat: s("timeFormat", Self.defaultTimeFormat))
    }
}
