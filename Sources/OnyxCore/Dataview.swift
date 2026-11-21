import Foundation

/// DQL: TABLE / LIST, FROM, WHERE, SORT, LIMIT, GROUP BY (with `rows`), and FLATTEN,
/// plus dates, durations, implicit `file.*` fields, and the usual function library.
public enum DVValue: Equatable, Sendable {
    case null
    case string(String)
    case number(Double)
    case bool(Bool)
    case link(path: String, name: String)
    case list([DVValue])
    case date(Date, dayOnly: Bool)
    case duration(DVDuration)
    case page(String)
    case task(DVTask)

    public var truthy: Bool {
        switch self {
        case .null: return false
        case .string(let s): return !s.isEmpty
        case .number(let n): return n != 0
        case .bool(let b): return b
        case .link, .date, .duration, .page, .task: return true
        case .list(let l): return !l.isEmpty
        }
    }
    public var text: String {
        switch self {
        case .null: return ""
        case .string(let s): return s
        case .number(let n): return n.rounded() == n && abs(n) < 1e15 ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        case .link(_, let name): return name
        case .list(let l): return l.map(\.text).joined(separator: ", ")
        case .date(let d, let dayOnly): return DVDate.format(d, dayOnly: dayOnly)
        case .duration(let d): return d.text
        case .page(let p): return ((p as NSString).lastPathComponent as NSString).deletingPathExtension
        case .task(let t): return t.text
        }
    }
    static func from(_ p: PropertyValue) -> DVValue {
        switch p {
        case .string(let s): return s.isEmpty ? .null : coerceScalar(s)
        case .number(let n): return .number(n)
        case .bool(let b): return .bool(b)
        case .list(let l): return .list(l.map { coerceScalar($0) })
        }
    }
    /// A bare ISO date/datetime string becomes a date; everything else stays a string.
    static func coerceScalar(_ s: String) -> DVValue {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return .null }
        if let d = DVDate.parse(t) { return .date(d, dayOnly: DVDate.isDayOnly(t)) }
        return .string(s)
    }
    func compare(_ o: DVValue) -> Int {
        if let a = dateValue, let b = o.dateValue { return a < b ? -1 : (a > b ? 1 : 0) }
        if case .duration(let a) = self, case .duration(let b) = o {
            let x = a.approxSeconds, y = b.approxSeconds
            return x < y ? -1 : (x > y ? 1 : 0)
        }
        switch (self, o) {
        case (.null, .null): return 0
        case (.null, _): return -1
        case (_, .null): return 1
        case (.number(let a), .number(let b)): return a < b ? -1 : (a > b ? 1 : 0)
        default:
            let a = text, b = o.text
            if let x = Double(a), let y = Double(b) { return x < y ? -1 : (x > y ? 1 : 0) }
            switch a.localizedStandardCompare(b) {
            case .orderedAscending: return -1
            case .orderedDescending: return 1
            default: return 0
            }
        }
    }
    var dateValue: Date? {
        switch self {
        case .date(let d, _): return d
        case .string(let s): return DVDate.parse(s)
        default: return nil
        }
    }
    var isList: Bool { if case .list = self { return true }; return false }
    var asList: [DVValue] {
        if case .list(let l) = self { return l }
        if self == .null { return [] }
        return [self]
    }
}

public struct DVDuration: Equatable, Sendable {
    public var years = 0, months = 0, weeks = 0, days = 0, hours = 0, minutes = 0, seconds = 0

    public var components: DateComponents {
        DateComponents(year: years, month: months, day: days + weeks * 7, hour: hours, minute: minutes, second: seconds)
    }
    public var approxSeconds: Double {
        Double(seconds + minutes * 60 + hours * 3600 + (days + weeks * 7) * 86400 + months * 30 * 86400 + years * 365 * 86400)
    }
    public var text: String {
        var parts: [String] = []
        func add(_ n: Int, _ one: String, _ many: String) {
            if n == 0 { return }
            parts.append(n == 1 || n == -1 ? "\(n) \(one)" : "\(n) \(many)")
        }
        add(years, "year", "years"); add(months, "month", "months"); add(weeks, "week", "weeks")
        add(days, "day", "days"); add(hours, "hour", "hours"); add(minutes, "minute", "minutes"); add(seconds, "second", "seconds")
        return parts.isEmpty ? "0 seconds" : parts.joined(separator: ", ")
    }
    public func added(_ o: DVDuration) -> DVDuration {
        DVDuration(years: years + o.years, months: months + o.months, weeks: weeks + o.weeks,
                   days: days + o.days, hours: hours + o.hours, minutes: minutes + o.minutes, seconds: seconds + o.seconds)
    }
    public var negated: DVDuration {
        DVDuration(years: -years, months: -months, weeks: -weeks, days: -days, hours: -hours, minutes: -minutes, seconds: -seconds)
    }
    public static func from(seconds total: Double) -> DVDuration {
        var r = Int(total.rounded())
        let sign = r < 0 ? -1 : 1
        r = abs(r)
        let d = r / 86400; r %= 86400
        let h = r / 3600; r %= 3600
        let m = r / 60; r %= 60
        return DVDuration(days: sign * d, hours: sign * h, minutes: sign * m, seconds: sign * r)
    }
    public static func parse(_ s: String) -> DVDuration? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return nil }
        let re = try! NSRegularExpression(pattern: #"([+-]?\d+(?:\.\d+)?)\s*(years?|yrs?|y|months?|weeks?|w|days?|d|hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)\b"#)
        let ns = t as NSString
        var d = DVDuration(), found = false
        re.enumerateMatches(in: t, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m, let n = Double(ns.substring(with: m.range(at: 1))) else { return }
            found = true
            let unit = ns.substring(with: m.range(at: 2))
            let whole = Int(n), frac = n - Double(Int(n))
            switch String(unit.prefix(1)) {
            case "y": d.years += whole; if frac != 0 { d.days += Int((frac * 365).rounded()) }
            case "w": d.weeks += whole; if frac != 0 { d.days += Int((frac * 7).rounded()) }
            case "d": d.days += whole; if frac != 0 { d.hours += Int((frac * 24).rounded()) }
            case "h": d.hours += whole; if frac != 0 { d.minutes += Int((frac * 60).rounded()) }
            case "s": d.seconds += Int(n.rounded())
            default:
                if unit.hasPrefix("mo") { d.months += whole; if frac != 0 { d.days += Int((frac * 30).rounded()) } }
                else { d.minutes += whole; if frac != 0 { d.seconds += Int((frac * 60).rounded()) } }
            }
        }
        return found ? d : nil
    }
}

public struct DVTask: Equatable, Sendable {
    public var text: String
    public var completed: Bool
    public var path: String
    public var line: Int
    public var indexInFile: Int
    public var due: Date? = nil
    public var scheduled: Date? = nil
    public var created: Date? = nil
    public var completion: Date? = nil
    public var tags: [String] = []
}

public indirect enum DVExpr: Sendable {
    case field(String)
    case literal(DVValue)
    case call(String, [DVExpr])
    case binary(String, DVExpr, DVExpr)
    case not(DVExpr)
    case lambda(String, DVExpr)
}

public enum DVClause: Sendable {
    case flatten(DVExpr, String)
    case whereExpr(DVExpr)
    case sort([(DVExpr, Bool)])
    case groupBy(DVExpr, String)
    case limit(Int)
}

public struct DVQuery: Sendable {
    public enum Kind: Sendable { case table, list, task, calendar }
    public var kind: Kind
    public var withoutID = false
    public var columns: [(DVExpr, String)] = []
    public var listExpr: DVExpr?
    public var from: [(String, Bool)] = []
    public var pipeline: [DVClause] = []
}

public struct DVTaskGroup: Sendable {
    public var heading: DVValue
    public var tasks: [DVTask]
}

public struct DVCalendarMonth: Sendable {
    public var year: Int
    public var month: Int
    /// Notes keyed by day-of-month (1...31).
    public var days: [Int: [DVValue]]
}

public struct DVResult: Sendable {
    public var headers: [String]
    public var rows: [[DVValue]]
    public var isList: Bool
    public var isTask: Bool = false
    public var taskGroups: [DVTaskGroup] = []
    public var isCalendar: Bool = false
    public var calendar: [DVCalendarMonth] = []
}

public enum DataviewError: Error, CustomStringConvertible {
    case parse(String)
    public var description: String { switch self { case .parse(let s): return s } }
}

enum DVDate {
    static let isoDay: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"; return f
    }()
    static let isoTime: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f
    }()

    static func format(_ d: Date, dayOnly: Bool) -> String {
        dayOnly ? isoDay.string(from: d) : isoTime.string(from: d)
    }
    static func isDayOnly(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.count == 10 && DVDate.parse(t) != nil && t[t.index(t.startIndex, offsetBy: 4)] == "-"
    }
    static func parse(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return nil }
        let fmts = [
            "yyyy-MM-dd'T'HH:mm:ssXXXXX", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd",
        ]
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        for fmt in fmts { f.dateFormat = fmt; if let d = f.date(from: t) { return d } }
        return nil
    }
    static func startOfDay(_ d: Date, calendar cal: Calendar = .current) -> Date {
        cal.startOfDay(for: d)
    }
    static func fromFileName(_ name: String) -> Date? {
        let re = try! NSRegularExpression(pattern: #"(\d{4}-\d{2}-\d{2})"#)
        let ns = name as NSString
        if let m = re.firstMatch(in: name, range: NSRange(location: 0, length: ns.length)) {
            return parse(ns.substring(with: m.range(at: 1)))
        }
        return nil
    }
    static func format(_ d: Date, pattern: String) -> String {
        var s = ""
        let cal = Calendar.current
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
        let chars = Array(pattern)
        var i = 0
        func take(_ ch: Character) -> Int {
            var n = 0; while i < chars.count && chars[i] == ch { n += 1; i += 1 }; return n
        }
        func pad(_ n: Int, _ w: Int) -> String { String(format: "%0\(w)d", n) }
        while i < chars.count {
            let ch = chars[i]
            switch ch {
            case "y":
                let n = take("y"), y = c.year ?? 0
                s += n >= 4 ? pad(y, n) : pad(y % 100, max(n, 2))
            case "M":
                let n = take("M"), m = c.month ?? 0
                s += n >= 2 ? pad(m, 2) : String(m)
            case "d":
                let n = take("d"), day = c.day ?? 0
                s += n >= 2 ? pad(day, 2) : String(day)
            case "H":
                let n = take("H"), h = c.hour ?? 0
                s += n >= 2 ? pad(h, 2) : String(h)
            case "h":
                let n = take("h"), h = c.hour ?? 0, h12 = h % 12 == 0 ? 12 : h % 12
                s += n >= 2 ? pad(h12, 2) : String(h12)
            case "m":
                let n = take("m"), m = c.minute ?? 0
                s += n >= 2 ? pad(m, 2) : String(m)
            case "s":
                let n = take("s"), sec = c.second ?? 0
                s += n >= 2 ? pad(sec, 2) : String(sec)
            case "a":
                _ = take("a")
                s += (c.hour ?? 0) >= 12 ? "PM" : "AM"
            default:
                s.append(ch); i += 1
            }
        }
        return s
    }
}

public enum Dataview {
    // MARK: Tokenizer
    enum Tok: Equatable { case ident(String), str(String), num(Double), op(String), lparen, rparen, comma, hash(String) }

    static func tokenize(_ s: String) throws -> [Tok] {
        var out: [Tok] = []
        let c = Array(s)
        var i = 0
        while i < c.count {
            let ch = c[i]
            if ch.isWhitespace { i += 1; continue }
            if ch == "\"" || ch == "'" {
                var j = i + 1; var v = ""
                while j < c.count && c[j] != ch { if c[j] == "\\" && j + 1 < c.count { j += 1 }; v.append(c[j]); j += 1 }
                out.append(.str(v)); i = j + 1; continue
            }
            if ch == "(" { out.append(.lparen); i += 1; continue }
            if ch == ")" { out.append(.rparen); i += 1; continue }
            if ch == "," { out.append(.comma); i += 1; continue }
            if ch == "#" {
                var j = i + 1; var v = ""
                while j < c.count && (c[j].isLetter || c[j].isNumber || "_-/".contains(c[j])) { v.append(c[j]); j += 1 }
                out.append(.hash(v)); i = j; continue
            }
            if "=!<>&|+*/-".contains(ch) {
                if i + 1 < c.count {
                    let two = String([ch, c[i + 1]])
                    if ["!=", "<=", ">=", "==", "&&", "||", "=>"].contains(two) {
                        out.append(.op(two)); i += 2; continue
                    }
                }
                if ch == "-" && i + 1 < c.count && (c[i + 1].isNumber || c[i + 1] == ".") && (out.last == nil || { if case .op = out.last! { return true }; return out.last == .lparen || out.last == .comma }()) {
                    // negative number
                } else {
                    out.append(.op(String(ch))); i += 1; continue
                }
            }
            if ch.isNumber || ch == "-" {
                var j = i; var v = ""
                if ch == "-" { v = "-"; j += 1 }
                while j < c.count && (c[j].isNumber || c[j] == ".") { v.append(c[j]); j += 1 }
                if let d = Double(v) { out.append(.num(d)) }
                i = j; continue
            }
            if ch.isLetter || ch == "_" {
                var j = i; var v = ""
                while j < c.count && (c[j].isLetter || c[j].isNumber || c[j] == "_" || c[j] == "." ||
                                      (c[j] == "-" && j + 1 < c.count && c[j + 1].isLetter)) { v.append(c[j]); j += 1 }
                out.append(.ident(v)); i = j; continue
            }
            throw DataviewError.parse("Unexpected character '\(ch)'")
        }
        return out
    }

    // MARK: Expression parser
    final class P {
        var t: [Tok]; var i = 0
        init(_ t: [Tok]) { self.t = t }
        var peek: Tok? { i < t.count ? t[i] : nil }
        func next() -> Tok? { defer { i += 1 }; return peek }
        func isKeyword(_ k: String) -> Bool { if case .ident(let s) = peek, s.uppercased() == k { return true }; return false }

        func expr() throws -> DVExpr { try orE() }
        func orE() throws -> DVExpr {
            var l = try andE()
            while isKeyword("OR") || peek == .op("||") || peek == .op("|") { i += 1; l = .binary("or", l, try andE()) }
            return l
        }
        func andE() throws -> DVExpr {
            var l = try cmp()
            while isKeyword("AND") || peek == .op("&&") || peek == .op("&") { i += 1; l = .binary("and", l, try cmp()) }
            return l
        }
        func cmp() throws -> DVExpr {
            var l = try add()
            while case .op(let o) = peek, ["=", "==", "!=", "<", ">", "<=", ">="].contains(o) { i += 1; l = .binary(o == "==" ? "=" : o, l, try add()) }
            return l
        }
        func add() throws -> DVExpr {
            var l = try mul()
            while case .op(let o) = peek, o == "+" || o == "-" { i += 1; l = .binary(o, l, try mul()) }
            return l
        }
        func mul() throws -> DVExpr {
            var l = try unary()
            while case .op(let o) = peek, o == "*" || o == "/" { i += 1; l = .binary(o, l, try unary()) }
            return l
        }
        func unary() throws -> DVExpr {
            if peek == .op("!") || isKeyword("NOT") { i += 1; return .not(try unary()) }
            return try primary()
        }
        func primary() throws -> DVExpr {
            // (x) => body   or   x => body
            if peek == .lparen, i + 3 < t.count, case .ident(let p) = t[i + 1], t[i + 2] == .rparen, t[i + 3] == .op("=>") {
                i += 4
                return .lambda(p, try expr())
            }
            if case .ident(let p) = peek, i + 1 < t.count, t[i + 1] == .op("=>") {
                i += 2
                return .lambda(p, try expr())
            }
            guard let tk = next() else { throw DataviewError.parse("Unexpected end of expression") }
            switch tk {
            case .str(let s): return .literal(.string(s))
            case .num(let n):
                if let unit = durationUnit(peek), let d = durationFrom(n, unit) {
                    i += 1
                    var acc = d
                    while case .num(let n2) = peek, let u2 = durationUnit(t[safe: i + 1]), let d2 = durationFrom(n2, u2) {
                        i += 2; acc = acc.added(d2)
                    }
                    return .literal(.duration(acc))
                }
                return .literal(.number(n))
            case .lparen:
                let e = try expr()
                if peek == .rparen { i += 1 }
                return e
            case .ident(let name):
                if name.lowercased() == "true" { return .literal(.bool(true)) }
                if name.lowercased() == "false" { return .literal(.bool(false)) }
                if name.lowercased() == "null" { return .literal(.null) }
                if peek == .lparen {
                    i += 1
                    if name.lowercased() == "dur" { return .literal(.duration(try parseDurArgs())) }
                    var args: [DVExpr] = []
                    while peek != nil && peek != .rparen { args.append(try expr()); if peek == .comma { i += 1 } }
                    if peek == .rparen { i += 1 }
                    return .call(name.lowercased(), args)
                }
                return .field(name)
            case .hash(let tag): return .literal(.string("#" + tag))
            default: throw DataviewError.parse("Unexpected token")
            }
        }
        static let units: Set<String> = [
            "year", "years", "yr", "yrs", "y",
            "month", "months",
            "week", "weeks", "w",
            "day", "days", "d",
            "hour", "hours", "hr", "hrs", "h",
            "minute", "minutes", "min", "mins", "m",
            "second", "seconds", "sec", "secs", "s",
        ]
        func durationUnit(_ tok: Tok?) -> String? {
            if case .ident(let s) = tok, Self.units.contains(s.lowercased()) { return s.lowercased() }
            return nil
        }
        func durationFrom(_ n: Double, _ unit: String) -> DVDuration? {
            DVDuration.parse("\(n) \(unit)")
        }
        func parseDurArgs() throws -> DVDuration {
            if case .str(let s) = peek {
                i += 1
                if peek == .rparen { i += 1 }
                if let d = DVDuration.parse(s) { return d }
                throw DataviewError.parse("Couldn’t parse duration “\(s)”")
            }
            var acc = DVDuration(), any = false
            while peek != nil && peek != .rparen {
                if case .num(let n) = peek, let unit = durationUnit(t[safe: i + 1]), let d = durationFrom(n, unit) {
                    i += 2; acc = acc.added(d); any = true; continue
                }
                if case .str(let s) = peek, let d = DVDuration.parse(s) {
                    i += 1; acc = acc.added(d); any = true; continue
                }
                throw DataviewError.parse("Expected a duration like 1 day inside dur()")
            }
            if peek == .rparen { i += 1 }
            if !any { throw DataviewError.parse("dur() needs a duration") }
            return acc
        }
    }

    // MARK: Query parser
    static let clauses = ["FROM", "WHERE", "SORT", "LIMIT", "GROUP", "FLATTEN"]

    public static func parseExpr(_ source: String) throws -> DVExpr {
        let p = P(try tokenize(source))
        let e = try p.expr()
        if p.peek != nil { throw DataviewError.parse("Unexpected trailing tokens in expression") }
        return e
    }

    public static func parse(_ source: String) throws -> DVQuery {
        let text = source.replacingOccurrences(of: "\n", with: " ")
        let toks = try tokenize(text)
        guard case .ident(let first)? = toks.first else { throw DataviewError.parse("Empty query") }
        var q: DVQuery
        switch first.uppercased() {
        case "TABLE": q = DVQuery(kind: .table)
        case "LIST": q = DVQuery(kind: .list)
        case "TASK": q = DVQuery(kind: .task)
        case "CALENDAR": q = DVQuery(kind: .calendar)
        default: throw DataviewError.parse("Onyx supports TABLE, LIST, TASK, and CALENDAR queries (got \(first))")
        }
        var sections: [(String, [Tok])] = [("HEAD", [])]
        for tk in toks.dropFirst() {
            if case .ident(let s) = tk, clauses.contains(s.uppercased()) { sections.append((s.uppercased(), [])); continue }
            if case .ident(let s) = tk, s.uppercased() == "BY", sections.last?.0 == "GROUP" { continue }
            sections[sections.count - 1].1.append(tk)
        }
        for (name, ts) in sections {
            switch name {
            case "HEAD":
                var t = ts
                if case .ident(let w)? = t.first, w.uppercased() == "WITHOUT", t.count > 1 { q.withoutID = true; t.removeFirst(2) }
                if t.isEmpty { break }
                let p = P(t)
                if q.kind == .list || q.kind == .task || q.kind == .calendar { q.listExpr = try p.expr(); break }
                while p.peek != nil {
                    let e = try p.expr()
                    var label = exprLabel(e)
                    if p.isKeyword("AS") {
                        p.i += 1
                        if case .str(let s)? = p.next() { label = s }
                        else if case .ident(let s)? = t[safe: p.i - 1] { label = s }
                    }
                    q.columns.append((e, label))
                    if p.peek == .comma { p.i += 1 }
                }
            case "FROM":
                var neg = false
                for tk in ts {
                    switch tk {
                    case .str(let s): q.from.append((s, neg)); neg = false
                    case .hash(let s): q.from.append(("#" + s, neg)); neg = false
                    case .op("-"), .op("!"): neg = true
                    default: break
                    }
                }
            case "WHERE":
                q.pipeline.append(.whereExpr(try P(ts).expr()))
            case "SORT":
                let p = P(ts)
                var keys: [(DVExpr, Bool)] = []
                while p.peek != nil {
                    let e = try p.expr()
                    var asc = true
                    if p.isKeyword("DESC") || p.isKeyword("DESCENDING") { asc = false; p.i += 1 }
                    else if p.isKeyword("ASC") || p.isKeyword("ASCENDING") { p.i += 1 }
                    keys.append((e, asc))
                    if p.peek == .comma { p.i += 1 }
                }
                q.pipeline.append(.sort(keys))
            case "LIMIT":
                if case .num(let n)? = ts.first { q.pipeline.append(.limit(Int(n))) }
            case "FLATTEN":
                let p = P(ts)
                let e = try p.expr()
                var label = exprLabel(e)
                if p.isKeyword("AS") {
                    p.i += 1
                    if case .str(let s)? = p.next() { label = s }
                    else if case .ident(let s)? = ts[safe: p.i - 1] { label = s }
                }
                q.pipeline.append(.flatten(e, label))
            case "GROUP":
                let p = P(ts)
                let e = try p.expr()
                var label = "key"
                if p.isKeyword("AS") {
                    p.i += 1
                    if case .str(let s)? = p.next() { label = s }
                    else if case .ident(let s)? = ts[safe: p.i - 1] { label = s }
                }
                q.pipeline.append(.groupBy(e, label))
            default:
                throw DataviewError.parse("\(name) isn’t supported")
            }
        }
        return q
    }

    static func exprLabel(_ e: DVExpr) -> String {
        switch e {
        case .field(let f): return f
        case .call(let n, _): return n
        default: return "value"
        }
    }

    // MARK: Evaluation
    struct Env {
        var snap: VaultSnapshot
        var page: NoteRecord?
        var task: DVTask? = nil
        var bindings: [String: DVValue] = [:]
        var now: Date
        var currentPath: String?
    }

    public static func run(_ source: String, in snap: VaultSnapshot, from currentPath: String? = nil, now: Date = Date()) throws -> DVResult {
        let q = try parse(source)
        var pages = snap.notes.values.filter { matchesFrom(q.from, $0, snap: snap, current: currentPath) }
        pages.sort { $0.path < $1.path }
        let hasSort = q.pipeline.contains { if case .sort = $0 { return true }; return false }
        var rows: [Env]
        if q.kind == .task {
            rows = pages.flatMap { page -> [Env] in
                tasks(in: page).map { t in
                    var env = Env(snap: snap, page: page, task: t, now: now, currentPath: currentPath)
                    env.bindings = taskBindings(t)
                    return env
                }
            }
            if !hasSort { rows.sort { a, b in
                let pa = a.task?.path ?? "", pb = b.task?.path ?? ""
                if pa != pb { return pa < pb }
                return (a.task?.line ?? 0) < (b.task?.line ?? 0)
            } }
        } else {
            rows = pages.map { Env(snap: snap, page: $0, now: now, currentPath: currentPath) }
        }
        for clause in q.pipeline {
            switch clause {
            case .flatten(let e, let name):
                rows = rows.flatMap { env in
                    let v = eval(e, env)
                    let items: [DVValue]
                    if case .list(let l) = v { items = l }
                    else { items = [v] }
                    return items.map { item in
                        var next = env
                        next.bindings[norm(name)] = item
                        return next
                    }
                }
            case .whereExpr(let e):
                rows = rows.filter { eval(e, $0).truthy }
            case .sort(let keys):
                rows.sort { a, b in
                    for (e, asc) in keys {
                        let c = eval(e, a).compare(eval(e, b))
                        if c != 0 { return asc ? c < 0 : c > 0 }
                    }
                    return (a.page?.path ?? "") < (b.page?.path ?? "")
                }
            case .groupBy(let e, let name):
                var order: [String] = []
                var groups: [String: (key: DVValue, rows: [Env])] = [:]
                for env in rows {
                    let key = eval(e, env)
                    let id = groupID(key)
                    if groups[id] == nil { order.append(id); groups[id] = (key, []) }
                    groups[id]!.rows.append(env)
                }
                rows = order.map { id in
                    let g = groups[id]!
                    let items = g.rows.map(rowValue)
                    var bindings: [String: DVValue] = [
                        "key": g.key,
                        "rows": .list(items),
                    ]
                    bindings[norm(name)] = g.key
                    return Env(snap: snap, page: nil, bindings: bindings, now: now, currentPath: currentPath)
                }
            case .limit(let n):
                rows = Array(rows.prefix(max(n, 0)))
            }
        }
        let present: (Env) -> DVValue = { env in
            if let p = env.page { return .link(path: p.path, name: p.name) }
            if let k = env.bindings["key"] { return display(k, snap) }
            return .null
        }
        switch q.kind {
        case .list:
            let out = rows.map { env -> [DVValue] in
                if let e = q.listExpr { return [present(env), display(eval(e, env), snap)] }
                return [present(env)]
            }
            return DVResult(headers: [], rows: out, isList: true)
        case .table:
            var headers = q.columns.map(\.1)
            if !q.withoutID {
                let grouped = rows.first?.page == nil && rows.first?.bindings["key"] != nil
                headers.insert(grouped ? exprLabel(groupExpr(q) ?? .field("Group")) : "File", at: 0)
            }
            let out = rows.map { env -> [DVValue] in
                var r = q.columns.map { display(eval($0.0, env), snap) }
                if !q.withoutID { r.insert(present(env), at: 0) }
                return r
            }
            return DVResult(headers: headers, rows: out, isList: false)
        case .task:
            return taskResult(rows, snap: snap, grouped: groupExpr(q) != nil)
        case .calendar:
            return calendarResult(rows, expr: q.listExpr ?? .field("file.day"), snap: snap)
        }
    }

    static func calendarResult(_ rows: [Env], expr: DVExpr, snap: VaultSnapshot) -> DVResult {
        let cal = Calendar.current
        var buckets: [String: (year: Int, month: Int, days: [Int: [DVValue]])] = [:]
        var order: [String] = []
        for env in rows {
            guard let date = eval(expr, env).dateValue else { continue }
            let c = cal.dateComponents([.year, .month, .day], from: date)
            guard let y = c.year, let m = c.month, let d = c.day else { continue }
            let key = String(format: "%04d-%02d", y, m)
            if buckets[key] == nil { order.append(key); buckets[key] = (y, m, [:]) }
            let link: DVValue
            if let p = env.page { link = display(.page(p.path), snap) }
            else if let t = env.task { link = .link(path: t.path, name: t.text) }
            else { link = display(env.bindings["key"] ?? .null, snap) }
            buckets[key]!.days[d, default: []].append(link)
        }
        // Fill months from the first result through the last, so a gap is still a page of the calendar.
        var months: [DVCalendarMonth] = []
        if let first = order.first, let last = order.last,
           let start = buckets[first], let end = buckets[last] {
            var y = start.year, m = start.month
            while (y, m) <= (end.year, end.month) {
                let key = String(format: "%04d-%02d", y, m)
                let days = buckets[key]?.days ?? [:]
                months.append(DVCalendarMonth(year: y, month: m, days: days))
                m += 1
                if m > 12 { m = 1; y += 1 }
            }
        }
        return DVResult(headers: [], rows: [], isList: false, isCalendar: true, calendar: months)
    }

    static func rowValue(_ env: Env) -> DVValue {
        if let t = env.task { return .task(t) }
        if let p = env.page { return .page(p.path) }
        return .null
    }

    static func taskBindings(_ t: DVTask) -> [String: DVValue] {
        [
            "text": .string(t.text),
            "visual": .string(t.text),
            "completed": .bool(t.completed),
            "done": .bool(t.completed),
            "path": .string(t.path),
            "line": .number(Double(t.line)),
            "due": t.due.map { .date($0, dayOnly: true) } ?? .null,
            "scheduled": t.scheduled.map { .date($0, dayOnly: true) } ?? .null,
            "created": t.created.map { .date($0, dayOnly: true) } ?? .null,
            "completion": t.completion.map { .date($0, dayOnly: true) } ?? .null,
            "tags": .list(t.tags.map { .string($0) }),
        ]
    }

    static func taskResult(_ rows: [Env], snap: VaultSnapshot, grouped: Bool) -> DVResult {
        var groups: [DVTaskGroup] = []
        if grouped {
            for env in rows {
                let heading = display(env.bindings["key"] ?? .null, snap)
                let tasks = (env.bindings["rows"]?.asList ?? []).compactMap { v -> DVTask? in
                    if case .task(let t) = v { return t }
                    return nil
                }
                groups.append(DVTaskGroup(heading: heading, tasks: tasks))
            }
        } else {
            var order: [String] = []
            var bucket: [String: [DVTask]] = [:]
            for env in rows {
                guard let t = env.task else { continue }
                if bucket[t.path] == nil { order.append(t.path) }
                bucket[t.path, default: []].append(t)
            }
            groups = order.map { p in
                let name = snap.notes[p]?.name ?? ((p as NSString).lastPathComponent as NSString).deletingPathExtension
                return DVTaskGroup(heading: .link(path: p, name: name), tasks: bucket[p] ?? [])
            }
        }
        let flat = groups.flatMap(\.tasks)
        return DVResult(headers: [], rows: flat.map { [.task($0)] }, isList: true, isTask: true, taskGroups: groups)
    }

    /// Flip the `index`-th task checkbox (document order, outside code fences) in `text`.
    public static func toggleTask(in text: String, index: Int) -> String? {
        let lines = text.components(separatedBy: "\n")
        var out = lines
        var n = 0
        var inFence = false
        let fm = Frontmatter.parse(text)
        let check = try! NSRegularExpression(pattern: #"^(\s*(?:[-*+]|\d+[.)])\s+)\[( |x|X)\]"#)
        for (i, line) in lines.enumerated() where i >= fm.lineCount {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") || t.hasPrefix("~~~") { inFence.toggle(); continue }
            if inFence { continue }
            let ns = line as NSString
            guard let m = check.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { continue }
            if n == index {
                let mark = ns.substring(with: m.range(at: 2))
                let flipped = mark == " " ? "x" : " "
                let prefix = ns.substring(with: m.range(at: 1))
                out[i] = prefix + "[" + flipped + "]" + ns.substring(from: m.range.upperBound)
                return out.joined(separator: "\n")
            }
            n += 1
        }
        return nil
    }

    static func groupExpr(_ q: DVQuery) -> DVExpr? {
        for c in q.pipeline { if case .groupBy(let e, _) = c { return e } }
        return nil
    }
    static func groupID(_ v: DVValue) -> String {
        switch v {
        case .null: return "∅"
        case .link(let p, _): return "l:" + p
        case .page(let p): return "p:" + p
        case .date(let d, let day): return "d:\(d.timeIntervalSince1970):\(day)"
        case .number(let n): return "n:\(n)"
        case .bool(let b): return "b:\(b)"
        default: return "s:" + v.text
        }
    }
    static func display(_ v: DVValue, _ snap: VaultSnapshot) -> DVValue {
        switch v {
        case .page(let p):
            return .link(path: p, name: snap.notes[p]?.name ?? ((p as NSString).lastPathComponent as NSString).deletingPathExtension)
        case .list(let l): return .list(l.map { display($0, snap) })
        default: return v
        }
    }

    public static func evalExpr(_ source: String, in snap: VaultSnapshot, from path: String, now: Date = Date()) throws -> DVValue {
        guard let page = snap.notes[path] else { throw DataviewError.parse("No such page") }
        return eval(try parseExpr(source), Env(snap: snap, page: page, now: now, currentPath: path))
    }

    /// Replace `` `= expr` `` (and `` `$= js` ``) inline code with placeholders. Code fences are left alone.
    /// `html[i]` is the rendered value (or a small error) for `data-i="i"`.
    public static func rewriteInlineQueries(_ body: String, in snap: VaultSnapshot, from path: String, now: Date = Date()) -> (text: String, html: [String]) {
        let re = try! NSRegularExpression(pattern: #"`(\$?=\s*[^`]+)`"#)
        let ns = body as NSString
        let code = NoteParser.codeRanges(body)
        func inFence(_ r: NSRange) -> Bool { code.contains { NSIntersectionRange($0, r).length > 0 } }
        var html: [String] = []
        var out = ""
        var last = 0
        for m in re.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
            if inFence(m.range) { continue }
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let raw = ns.substring(with: m.range(at: 1))
            html.append(inlineHTML(raw, snap: snap, path: path, now: now))
            out += "<span class=\"onyx-dv-inline\" data-i=\"\(html.count - 1)\"></span>"
            last = NSMaxRange(m.range)
        }
        out += ns.substring(from: last)
        return (out, html)
    }

    static func inlineHTML(_ raw: String, snap: VaultSnapshot, path: String, now: Date) -> String {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("$=") {
            let js = String(s.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            return DataviewJS.evalInline(js, in: snap, from: path, now: now)
        }
        let expr = String(s.drop(while: { $0 == "=" || $0.isWhitespace }))
        do {
            let v = display(try evalExpr(expr, in: snap, from: path, now: now), snap)
            return inlineCell(v)
        } catch {
            return "<span class=\"dataview-inline-error\">\(esc(String(describing: error)))</span>"
        }
    }

    static func inlineCell(_ v: DVValue) -> String {
        switch v {
        case .link(let p, let n):
            return "<a class=\"internal-link\" data-path=\"\(esc(p))\">\(esc(n))</a>"
        case .list(let l):
            return l.map(inlineCell).joined(separator: ", ")
        case .null:
            return "<span class=\"dataview-empty\">null</span>"
        default:
            return esc(v.text)
        }
    }

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func matchesFrom(_ from: [(String, Bool)], _ n: NoteRecord, snap: VaultSnapshot, current: String?) -> Bool {
        if from.isEmpty { return true }
        var anyPositive = false, matchedPositive = false
        for (src, neg) in from {
            let m: Bool
            if src.hasPrefix("#") {
                let t = String(src.dropFirst()).lowercased()
                m = n.summary.tags.contains { $0.lowercased() == t || $0.lowercased().hasPrefix(t + "/") }
            } else {
                let s = src.hasSuffix("/") ? String(src.dropLast()) : src
                m = n.path == s || n.path == s + ".md" || n.path.hasPrefix(s + "/")
            }
            if neg { if m { return false } } else { anyPositive = true; if m { matchedPositive = true } }
        }
        return !anyPositive || matchedPositive
    }

    static func norm(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "_", with: "-")
    }

    static func lookup(_ name: String, _ env: Env) -> DVValue {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        if parts.first?.lowercased() == "this" {
            guard let page = env.page else { return .null }
            if parts.count == 1 { return .page(page.path) }
            return field(parts.dropFirst().joined(separator: "."), page, env.snap)
        }
        if let first = parts.first, let bound = binding(first, env) {
            if parts.count == 1 { return bound }
            return swizzle(bound, Array(parts.dropFirst()), env)
        }
        if let page = env.page {
            let whole = field(name, page, env.snap)
            if whole != .null || parts.count <= 1 { return whole }
        }
        return .null
    }

    static func binding(_ name: String, _ env: Env) -> DVValue? {
        let n = norm(name)
        if let v = env.bindings[n] { return v }
        if let v = env.bindings[name] { return v }
        if let (k, v) = env.bindings.first(where: { norm($0.key) == n }) { _ = k; return v }
        return nil
    }

    static func swizzle(_ v: DVValue, _ parts: [String], _ env: Env) -> DVValue {
        if parts.isEmpty { return v }
        if case .list(let l) = v { return .list(l.map { swizzle($0, parts, env) }) }
        let rest = parts.joined(separator: ".")
        switch v {
        case .page(let p):
            if let n = env.snap.notes[p] { return field(rest, n, env.snap) }
            return .null
        case .task(let t):
            return taskField(rest, t)
        case .link(let p, _):
            if let n = env.snap.notes[p] { return field(rest, n, env.snap) }
            return .null
        default:
            return .null
        }
    }

    static func taskField(_ name: String, _ t: DVTask) -> DVValue {
        switch name.lowercased() {
        case "text", "visual": return .string(t.text)
        case "completed", "done": return .bool(t.completed)
        case "path", "file.path": return .string(t.path)
        case "line": return .number(Double(t.line))
        case "due": return t.due.map { .date($0, dayOnly: true) } ?? .null
        case "scheduled": return t.scheduled.map { .date($0, dayOnly: true) } ?? .null
        case "created": return t.created.map { .date($0, dayOnly: true) } ?? .null
        case "completion", "completeddate": return t.completion.map { .date($0, dayOnly: true) } ?? .null
        case "tags": return .list(t.tags.map { .string($0) })
        case "file", "file.link":
            let name = ((t.path as NSString).lastPathComponent as NSString).deletingPathExtension
            return .link(path: t.path, name: name)
        default: return .null
        }
    }

    static func field(_ name: String, _ n: NoteRecord, _ snap: VaultSnapshot) -> DVValue {
        let lower = name.lowercased()
        switch lower {
        case "file", "file.link": return .link(path: n.path, name: n.name)
        case "file.name": return .string(n.name)
        case "file.path": return .string(n.path)
        case "file.folder": return .string(n.folder)
        case "file.size": return .number(Double(n.size))
        case "file.mtime": return .date(n.mtime, dayOnly: false)
        case "file.ctime": return .date(n.ctime, dayOnly: false)
        case "file.mday": return .date(DVDate.startOfDay(n.mtime), dayOnly: true)
        case "file.cday": return .date(DVDate.startOfDay(n.ctime), dayOnly: true)
        case "file.day": return DVDate.fromFileName(n.name).map { .date($0, dayOnly: true) } ?? .null
        case "file.tags":
            var tags = Set<String>()
            for t in n.summary.tags {
                var acc = ""
                for part in t.split(separator: "/") {
                    acc = acc.isEmpty ? String(part) : acc + "/" + part
                    tags.insert(acc)
                }
            }
            return .list(tags.sorted().map { .string("#" + $0) })
        case "file.etags": return .list(n.summary.tags.sorted().map { .string("#" + $0) })
        case "file.outlinks":
            return .list(n.summary.links.compactMap { l in
                snap.resolve(l.target, from: n.path).map { DVValue.link(path: $0, name: (($0 as NSString).lastPathComponent as NSString).deletingPathExtension) }
            })
        case "file.inlinks":
            return .list((snap.backlinks[n.path] ?? []).sorted().map { .link(path: $0, name: (($0 as NSString).lastPathComponent as NSString).deletingPathExtension) })
        case "file.aliases": return .list(n.aliases.map { .string($0) })
        case "file.tasks": return .list(tasks(in: n).map { .task($0) })
        default: break
        }
        if let p = n.summary.frontmatter.properties.first(where: { norm($0.key) == norm(name) }) {
            let v = DVValue.from(p.value)
            if case .string(let s) = v, s.hasPrefix("[["), s.hasSuffix("]]") {
                let l = NoteParser.makeLink(inner: String(s.dropFirst(2).dropLast(2)), embed: false, range: NSRange())
                if let path = snap.resolve(l.target, from: n.path) { return .link(path: path, name: l.alias ?? l.target) }
            }
            return v
        }
        let fields = n.summary.fields.filter { norm($0.key) == norm(name) }
        if !fields.isEmpty {
            let vals: [DVValue] = fields.flatMap { f -> [DVValue] in
                if f.links.isEmpty { return [DVValue.coerceScalar(f.value)] }
                return f.links.map { l in snap.resolve(l.target, from: n.path).map { DVValue.link(path: $0, name: l.alias ?? (($0 as NSString).lastPathComponent as NSString).deletingPathExtension) } ?? .string(l.target) }
            }
            return vals.count == 1 ? vals[0] : .list(vals)
        }
        return .null
    }

    public static func tasks(in n: NoteRecord) -> [DVTask] {
        tasks(in: n.content, path: n.path)
    }
    public static func tasks(in text: String, path: String) -> [DVTask] {
        let lines = text.components(separatedBy: "\n")
        let fm = Frontmatter.parse(text)
        var out: [DVTask] = []
        var inFence = false
        var index = 0
        let check = try! NSRegularExpression(pattern: #"^(\s*(?:[-*+]|\d+[.)])\s+)\[( |x|X)\]\s?(.*)$"#)
        for (i, line) in lines.enumerated() where i >= fm.lineCount {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") || t.hasPrefix("~~~") { inFence.toggle(); continue }
            if inFence { continue }
            let ns = line as NSString
            guard let m = check.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { continue }
            let mark = ns.substring(with: m.range(at: 2))
            let body = ns.substring(with: m.range(at: 3))
            var due: Date?, scheduled: Date?, created: Date?, completion: Date?
            func eat(_ pattern: String, _ into: inout Date?) {
                let re = try! NSRegularExpression(pattern: pattern)
                if let mm = re.firstMatch(in: body, range: NSRange(location: 0, length: (body as NSString).length)) {
                    into = DVDate.parse((body as NSString).substring(with: mm.range(at: 1)))
                }
            }
            eat(#"📅\s*(\d{4}-\d{2}-\d{2}(?:[ T]\d{2}:\d{2}(?::\d{2})?)?)"#, &due)
            eat(#"⏳\s*(\d{4}-\d{2}-\d{2}(?:[ T]\d{2}:\d{2}(?::\d{2})?)?)"#, &scheduled)
            eat(#"➕\s*(\d{4}-\d{2}-\d{2}(?:[ T]\d{2}:\d{2}(?::\d{2})?)?)"#, &created)
            eat(#"✅\s*(\d{4}-\d{2}-\d{2}(?:[ T]\d{2}:\d{2}(?::\d{2})?)?)"#, &completion)
            eat(#"\[due::\s*([^\]]+)\]"#, &due)
            eat(#"\[scheduled::\s*([^\]]+)\]"#, &scheduled)
            eat(#"\[created::\s*([^\]]+)\]"#, &created)
            eat(#"\[completion::\s*([^\]]+)\]"#, &completion)
            var tags: [String] = []
            let tagRe = try! NSRegularExpression(pattern: #"(?<![\w/&#])#([A-Za-z0-9_\-/]*[A-Za-z_\-/][A-Za-z0-9_\-/]*)"#)
            tagRe.enumerateMatches(in: body, range: NSRange(location: 0, length: (body as NSString).length)) { m, _, _ in
                if let m { tags.append((body as NSString).substring(with: m.range(at: 1))) }
            }
            out.append(DVTask(text: body.trimmingCharacters(in: .whitespaces), completed: mark.lowercased() == "x", path: path, line: i, indexInFile: index,
                              due: due, scheduled: scheduled, created: created, completion: completion, tags: tags))
            index += 1
        }
        return out
    }

    static func eval(_ e: DVExpr, _ env: Env) -> DVValue {
        switch e {
        case .literal(let v): return v
        case .field(let f): return lookup(f, env)
        case .not(let x): return .bool(!eval(x, env).truthy)
        case .lambda: return .null
        case .binary(let op, let a, let b):
            if op == "and" { return .bool(eval(a, env).truthy && eval(b, env).truthy) }
            if op == "or" { return .bool(eval(a, env).truthy || eval(b, env).truthy) }
            let x = eval(a, env), y = eval(b, env)
            switch op {
            case "=": return .bool(equal(x, y))
            case "!=": return .bool(!equal(x, y))
            case "<": return .bool(x.compare(y) < 0)
            case ">": return .bool(x.compare(y) > 0)
            case "<=": return .bool(x.compare(y) <= 0)
            case ">=": return .bool(x.compare(y) >= 0)
            case "+": return add(x, y, env)
            case "-": return subtract(x, y, env)
            case "*":
                if case .number(let p) = x, case .number(let q) = y { return .number(p * q) }
                return .null
            case "/":
                if case .number(let p) = x, case .number(let q) = y, q != 0 { return .number(p / q) }
                return .null
            default: return .null
            }
        case .call(let name, let args):
            return call(name, args, env)
        }
    }

    static func add(_ x: DVValue, _ y: DVValue, _ env: Env) -> DVValue {
        if let d = x.dateValue, case .duration(let dur) = y {
            let dayOnly = if case .date(_, let day) = x { day } else { true }
            if let n = Calendar.current.date(byAdding: dur.components, to: d) { return .date(n, dayOnly: dayOnly) }
            return .null
        }
        if case .duration(let dur) = x, let d = y.dateValue {
            let dayOnly = if case .date(_, let day) = y { day } else { true }
            if let n = Calendar.current.date(byAdding: dur.components, to: d) { return .date(n, dayOnly: dayOnly) }
            return .null
        }
        if case .duration(let a) = x, case .duration(let b) = y { return .duration(a.added(b)) }
        if case .number(let p) = x, case .number(let q) = y { return .number(p + q) }
        return .string(x.text + y.text)
    }
    static func subtract(_ x: DVValue, _ y: DVValue, _ env: Env) -> DVValue {
        if let a = x.dateValue, let b = y.dateValue { return .duration(DVDuration.from(seconds: a.timeIntervalSince(b))) }
        if let d = x.dateValue, case .duration(let dur) = y {
            let dayOnly = if case .date(_, let day) = x { day } else { true }
            if let n = Calendar.current.date(byAdding: dur.negated.components, to: d) { return .date(n, dayOnly: dayOnly) }
            return .null
        }
        if case .duration(let a) = x, case .duration(let b) = y { return .duration(a.added(b.negated)) }
        if case .number(let p) = x, case .number(let q) = y { return .number(p - q) }
        return .null
    }

    static func call(_ name: String, _ args: [DVExpr], _ env: Env) -> DVValue {
        switch name {
        case "date": return callDate(args, env)
        case "dur":
            let v = args.first.map { eval($0, env) } ?? .null
            if case .duration(let d) = v { return .duration(d) }
            if case .string(let s) = v, let d = DVDuration.parse(s) { return .duration(d) }
            return .null
        case "choice":
            let v = args.map { eval($0, env) }
            return v.count == 3 ? (v[0].truthy ? v[1] : v[2]) : .null
        case "default":
            let v = args.map { eval($0, env) }
            return v.count == 2 ? (v[0] == .null ? v[1] : v[0]) : .null
        case "contains", "icontains", "econtains":
            guard args.count == 2 else { return .null }
            return contains(eval(args[0], env), eval(args[1], env), mode: name)
        case "length":
            let v = eval(args.first ?? .literal(.null), env)
            if case .list(let l) = v { return .number(Double(l.count)) }
            return .number(Double(v.text.count))
        case "lower": return .string(eval(args.first ?? .literal(.null), env).text.lowercased())
        case "upper": return .string(eval(args.first ?? .literal(.null), env).text.uppercased())
        case "join":
            let v = args.map { eval($0, env) }
            if case .list(let l) = v.first { return .string(l.map(\.text).joined(separator: v.count > 1 ? v[1].text : ", ")) }
            return v.first ?? .null
        case "link":
            let v = args.map { eval($0, env) }
            if let p = env.snap.resolve(v.first?.text ?? "", from: env.page?.path ?? env.currentPath) {
                return .link(path: p, name: v.count > 1 ? v[1].text : (env.snap.notes[p]?.name ?? (v.first?.text ?? "")))
            }
            return .null
        case "number":
            let t = eval(args.first ?? .literal(.null), env)
            if case .number(let n) = t { return .number(n) }
            return Double(t.text).map { .number($0) } ?? .null
        case "string": return .string(eval(args.first ?? .literal(.null), env).text)
        case "round":
            let v = args.map { eval($0, env) }
            guard case .number(let n) = v.first else { return .null }
            let digits = v.count > 1 ? Int(v[1].text) ?? 0 : 0
            let p = pow(10.0, Double(max(digits, 0)))
            return .number((n * p).rounded() / p)
        case "min", "max", "sum":
            return reduceNumbers(name, args, env)
        case "dateformat":
            guard args.count >= 2, let d = eval(args[0], env).dateValue else { return .null }
            return .string(DVDate.format(d, pattern: eval(args[1], env).text))
        case "striptime":
            guard let d = eval(args.first ?? .literal(.null), env).dateValue else { return .null }
            return .date(DVDate.startOfDay(d), dayOnly: true)
        case "regexmatch":
            guard args.count == 2 else { return .null }
            return .bool(regex(eval(args[1], env).text, in: eval(args[0], env).text) != nil)
        case "replace":
            guard args.count == 3 else { return .null }
            let src = eval(args[0], env).text, pat = eval(args[1], env).text, tmpl = eval(args[2], env).text
            guard let re = try? NSRegularExpression(pattern: pat) else { return .null }
            return .string(re.stringByReplacingMatches(in: src, range: NSRange(location: 0, length: (src as NSString).length), withTemplate: tmpl))
        case "startswith":
            guard args.count == 2 else { return .null }
            return .bool(eval(args[0], env).text.hasPrefix(eval(args[1], env).text))
        case "endswith":
            guard args.count == 2 else { return .null }
            return .bool(eval(args[0], env).text.hasSuffix(eval(args[1], env).text))
        case "nonnull":
            return .list(eval(args.first ?? .literal(.null), env).asList.filter { $0 != .null })
        case "filter":
            return filterMap(args, env, keep: true)
        case "map":
            return filterMap(args, env, keep: false)
        case "any", "all":
            return anyAll(name == "all", args, env)
        default:
            return .null
        }
    }

    static func callDate(_ args: [DVExpr], _ env: Env) -> DVValue {
        guard let first = args.first else { return .date(env.now, dayOnly: false) }
        if case .field(let n) = first {
            switch n.lowercased() {
            case "today": return .date(DVDate.startOfDay(env.now), dayOnly: true)
            case "yesterday":
                let y = Calendar.current.date(byAdding: .day, value: -1, to: env.now) ?? env.now
                return .date(DVDate.startOfDay(y), dayOnly: true)
            case "tomorrow":
                let t = Calendar.current.date(byAdding: .day, value: 1, to: env.now) ?? env.now
                return .date(DVDate.startOfDay(t), dayOnly: true)
            case "now": return .date(env.now, dayOnly: false)
            default: break
            }
        }
        let v = eval(first, env)
        if let d = v.dateValue {
            let dayOnly = if case .date(_, let day) = v { day } else { DVDate.isDayOnly(v.text) }
            return .date(d, dayOnly: dayOnly)
        }
        return .null
    }

    static func contains(_ a: DVValue, _ b: DVValue, mode: String) -> DVValue {
        if case .list(let l) = a {
            if mode == "econtains" { return .bool(l.contains { equal($0, b) }) }
            let ci = mode == "icontains"
            return .bool(l.contains { equal($0, b) || (ci ? $0.text.lowercased() == b.text.lowercased() : $0.text.contains(b.text)) })
        }
        if mode == "econtains" { return .bool(a.text == b.text) }
        if mode == "icontains" { return .bool(a.text.lowercased().contains(b.text.lowercased())) }
        return .bool(a.text.contains(b.text))
    }

    static func reduceNumbers(_ name: String, _ args: [DVExpr], _ env: Env) -> DVValue {
        var nums: [Double] = []
        for a in args {
            let v = eval(a, env)
            for item in v.asList {
                if case .number(let n) = item { nums.append(n) }
                else if let n = Double(item.text), item != .null { nums.append(n) }
            }
        }
        guard !nums.isEmpty else { return .null }
        switch name {
        case "min": return .number(nums.min()!)
        case "max": return .number(nums.max()!)
        default: return .number(nums.reduce(0, +))
        }
    }

    static func filterMap(_ args: [DVExpr], _ env: Env, keep: Bool) -> DVValue {
        guard args.count == 2 else { return .null }
        let list = eval(args[0], env).asList
        guard case .lambda(let param, let body) = args[1] else { return .null }
        var out: [DVValue] = []
        for item in list {
            var next = env
            next.bindings[norm(param)] = item
            next.bindings[param] = item
            let r = eval(body, next)
            if keep { if r.truthy { out.append(item) } } else { out.append(r) }
        }
        return .list(out)
    }

    static func anyAll(_ all: Bool, _ args: [DVExpr], _ env: Env) -> DVValue {
        let list: [DVValue]
        let pred: DVExpr?
        if args.count >= 2 { list = eval(args[0], env).asList; pred = args[1] }
        else { list = eval(args.first ?? .literal(.null), env).asList; pred = nil }
        if let pred, case .lambda(let param, let body) = pred {
            let flags = list.map { item -> Bool in
                var next = env
                next.bindings[norm(param)] = item
                next.bindings[param] = item
                return eval(body, next).truthy
            }
            return .bool(all ? flags.allSatisfy { $0 } : flags.contains(true))
        }
        return .bool(all ? list.allSatisfy(\.truthy) : list.contains(where: \.truthy))
    }

    static func regex(_ pattern: String, in text: String) -> NSTextCheckingResult? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        return re.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }

    static func equal(_ a: DVValue, _ b: DVValue) -> Bool {
        if case .list(let l) = a, !b.isList { return l.contains { equal($0, b) } }
        if case .link(let p, _) = a, case .link(let q, _) = b { return p == q }
        if case .page(let p) = a, case .page(let q) = b { return p == q }
        if case .page(let p) = a, case .link(let q, _) = b { return p == q }
        if case .link(let p, _) = a, case .page(let q) = b { return p == q }
        if case .number(let x) = a, case .number(let y) = b { return x == y }
        if case .bool(let x) = a, case .bool(let y) = b { return x == y }
        if let x = a.dateValue, let y = b.dateValue {
            let dayA = if case .date(_, let d) = a { d } else { DVDate.isDayOnly(a.text) }
            let dayB = if case .date(_, let d) = b { d } else { DVDate.isDayOnly(b.text) }
            if dayA || dayB { return Calendar.current.isDate(x, inSameDayAs: y) }
            return abs(x.timeIntervalSince(y)) < 0.5
        }
        if case .duration(let x) = a, case .duration(let y) = b { return x.approxSeconds == y.approxSeconds }
        if case .task(let x) = a, case .task(let y) = b { return x.path == y.path && x.line == y.line }
        return a.text == b.text
    }
}

extension Array { subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil } }
