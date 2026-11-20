import Foundation

public enum DailyNotes {
    public static func fileName(for date: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter(); f.calendar = calendar; f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date) + ".md"
    }
    public static func path(for date: Date, folder: String) -> String {
        folder.isEmpty ? fileName(for: date) : folder + "/" + fileName(for: date)
    }
    /// The vault's own daily-note shape: `class: DailyNote` frontmatter and a long-date H1.
    public static func template(for date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "EEEE, MMMM d, yyyy"
        return "---\nclass: DailyNote\n---\n# \(f.string(from: date))\n\n"
    }
    public static func date(fromFileName name: String) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: (name as NSString).deletingPathExtension)
    }
}
