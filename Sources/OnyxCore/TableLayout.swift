import Foundation

/// How a Markdown table should divide a measure so no column collapses and
/// short cells (dates, numbers, compact tokens) stay on one line. Widths are
/// in ems. If they still sum to more than `available`, the table should
/// scroll horizontally rather than shrink. The reader applies the same policy
/// in CSS and a small typesetting pass.
public enum TableLayout {

    /// Floor for a wrapping column, in ems — enough for a few words of
    /// Latin Modern, not so large that a four-column table always overflows
    /// a typical 41rem measure.
    public static let minimumEm: Double = 8

    /// A cell at most this many characters, with no whitespace, is compact
    /// (a date, a number, a short token) and should not wrap.
    public static let shortLimit = 12

    /// Rough average for Latin Modern: two characters per em.
    public static let charsPerEm: Double = 2

    public struct Column: Equatable, Sendable {
        public var width: Double
        public var nowrap: Bool
        public init(width: Double, nowrap: Bool) {
            self.width = width
            self.nowrap = nowrap
        }
    }

    /// `rows` is row-major cell text, including the header row when there is one.
    /// Empty or missing cells are ignored when judging whether a column is compact.
    public static func columns(_ rows: [[String]], available: Double) -> [Column] {
        let n = rows.map(\.count).max() ?? 0
        guard n > 0 else { return [] }
        var nowrap = Array(repeating: true, count: n)
        var minContent = Array(repeating: 0.0, count: n)
        var maxContent = Array(repeating: 0.0, count: n)
        var filled = Array(repeating: false, count: n)
        for row in rows {
            for c in 0..<n {
                let cell = c < row.count ? row[c] : ""
                let t = cell.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty { continue }
                filled[c] = true
                if !isCompact(t) { nowrap[c] = false }
                let maxCh = Double((t as NSString).length)
                let minCh = nowrap[c] ? maxCh : Double(longestToken(t))
                minContent[c] = max(minContent[c], minCh / charsPerEm)
                maxContent[c] = max(maxContent[c], maxCh / charsPerEm)
            }
        }
        // A column with no text at all is treated as wrapping so it still
        // gets the floor rather than collapsing to zero.
        var cols = (0..<n).map { c in
            let wrap = !filled[c] || !nowrap[c]
            let natural = filled[c] ? (wrap ? max(minimumEm, minContent[c]) : minContent[c]) : minimumEm
            return Column(width: natural, nowrap: !wrap)
        }
        let assigned = cols.reduce(0.0) { $0 + $1.width }
        if assigned < available {
            let weights = (0..<n).map { c -> Double in
                if cols[c].nowrap { return 0 }
                return max(0.01, maxContent[c])
            }
            let weightSum = weights.reduce(0, +)
            let extra = available - assigned
            if weightSum > 0 {
                for c in 0..<n where !cols[c].nowrap {
                    cols[c].width += extra * (weights[c] / weightSum)
                }
            } else {
                // Every column is nowrap: leave leftover unused so they stay tight.
            }
        }
        return cols
    }

    /// Sum of each column's minimum (8em for wrapping columns, natural
    /// width for compact ones). If this is at most `available`, the table
    /// should stay in the measure and wrap prose rather than bleed or scroll.
    public static func minWidth(_ rows: [[String]]) -> Double {
        columns(rows, available: 0).reduce(0) { $0 + $1.width }
    }

    /// True when the column minimums fit in `available` and leftover
    /// measure can be given to wrapping columns.
    public static func fits(_ rows: [[String]], available: Double) -> Bool {
        minWidth(rows) <= available
    }

    /// True for a date, a numeric cell, or a short token with no spaces.
    public static func isCompact(_ cell: String) -> Bool {
        let t = cell.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }
        if matches(number, t) || matches(date, t) { return true }
        return (t as NSString).length <= shortLimit && t.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
    }

    // ISO or slash/dot dates (`2026-11-09`, `11/9/26`).
    static let date = try! NSRegularExpression(pattern: #"^(\d{4}-\d{2}-\d{2}|\d{1,2}[/.]\d{1,2}[/.]\d{2,4})$"#)
    // Same shape the typesetter uses for right-aligned numeric columns.
    static let number = try! NSRegularExpression(pattern: #"^[\s(]*[-+\u2212\u2013]?[$€£¥]?\s?\d[\d,.\u2009\u00a0 ]*(%|[kKMB]|x|×)?\)?\s*$"#)

    static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }

    static func longestToken(_ s: String) -> Int {
        s.split(whereSeparator: { $0.isWhitespace }).map { (String($0) as NSString).length }.max() ?? 0
    }
}

