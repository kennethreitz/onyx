import Foundation

/// A calendar-aware duration used by Bases date arithmetic (`now() + "1d"`, `duration("2w")`).
public struct BaseDuration: Equatable, Sendable {
    public var years: Int
    public var months: Int
    public var weeks: Int
    public var days: Int
    public var hours: Int
    public var minutes: Int
    public var seconds: Double

    public init(years: Int = 0, months: Int = 0, weeks: Int = 0, days: Int = 0, hours: Int = 0, minutes: Int = 0, seconds: Double = 0) {
        self.years = years; self.months = months; self.weeks = weeks
        self.days = days; self.hours = hours; self.minutes = minutes; self.seconds = seconds
    }

    public var isZero: Bool {
        years == 0 && months == 0 && weeks == 0 && days == 0 && hours == 0 && minutes == 0 && seconds == 0
    }

    public var interval: TimeInterval {
        Double(years) * 365 * 86_400
            + Double(months) * 30 * 86_400
            + Double(weeks) * 7 * 86_400
            + Double(days) * 86_400
            + Double(hours) * 3_600
            + Double(minutes) * 60
            + seconds
    }

    public func adding(to date: Date, calendar cal: Calendar = .current) -> Date {
        var d = date
        d = cal.date(byAdding: .year, value: years, to: d) ?? d
        d = cal.date(byAdding: .month, value: months, to: d) ?? d
        d = cal.date(byAdding: .weekOfYear, value: weeks, to: d) ?? d
        d = cal.date(byAdding: .day, value: days, to: d) ?? d
        d = cal.date(byAdding: .hour, value: hours, to: d) ?? d
        d = cal.date(byAdding: .minute, value: minutes, to: d) ?? d
        return d.addingTimeInterval(seconds)
    }

    public static func + (a: BaseDuration, b: BaseDuration) -> BaseDuration {
        BaseDuration(
            years: a.years + b.years, months: a.months + b.months, weeks: a.weeks + b.weeks,
            days: a.days + b.days, hours: a.hours + b.hours, minutes: a.minutes + b.minutes,
            seconds: a.seconds + b.seconds
        )
    }

    public static func - (a: BaseDuration, b: BaseDuration) -> BaseDuration {
        BaseDuration(
            years: a.years - b.years, months: a.months - b.months, weeks: a.weeks - b.weeks,
            days: a.days - b.days, hours: a.hours - b.hours, minutes: a.minutes - b.minutes,
            seconds: a.seconds - b.seconds
        )
    }

    public static func * (a: BaseDuration, n: Double) -> BaseDuration {
        func scale(_ x: Int) -> (Int, Double) {
            let v = Double(x) * n
            let i = Int(v.rounded(.towardZero))
            return (i, v - Double(i))
        }
        // Scale whole units; leftover fractional years/months/weeks/days spill into seconds.
        var out = BaseDuration()
        var spill: TimeInterval = 0
        let y = scale(a.years); out.years = y.0; spill += y.1 * 365 * 86_400
        let m = scale(a.months); out.months = m.0; spill += m.1 * 30 * 86_400
        let w = scale(a.weeks); out.weeks = w.0; spill += w.1 * 7 * 86_400
        let d = scale(a.days); out.days = d.0; spill += d.1 * 86_400
        let h = scale(a.hours); out.hours = h.0; spill += h.1 * 3_600
        let mi = scale(a.minutes); out.minutes = mi.0; spill += mi.1 * 60
        out.seconds = a.seconds * n + spill
        return out
    }

    public var text: String {
        if isZero { return "0s" }
        var parts: [String] = []
        if years != 0 { parts.append("\(years)y") }
        if months != 0 { parts.append("\(months)M") }
        if weeks != 0 { parts.append("\(weeks)w") }
        if days != 0 { parts.append("\(days)d") }
        if hours != 0 { parts.append("\(hours)h") }
        if minutes != 0 { parts.append("\(minutes)m") }
        if seconds != 0 {
            if seconds.rounded() == seconds { parts.append("\(Int(seconds))s") }
            else { parts.append(String(format: "%gs", seconds)) }
        }
        let sign = (interval < 0 && !parts.isEmpty && !parts[0].hasPrefix("-")) ? "-" : ""
        return sign + parts.joined()
    }

    /// Parse official-style duration literals: `1d`, `2w`, `1h30m`, `1d 2h`, `1.5d`,
    /// and a few word forms (`2 weeks`, `1 day`, `1 month`, `1 year`).
    public static func parse(_ raw: String) -> BaseDuration? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        var t = s.lowercased().replacingOccurrences(of: " ", with: "")
        t = t.replacingOccurrences(of: "years", with: "y")
        t = t.replacingOccurrences(of: "year", with: "y")
        t = t.replacingOccurrences(of: "months", with: "M")
        t = t.replacingOccurrences(of: "month", with: "M")
        t = t.replacingOccurrences(of: "weeks", with: "w")
        t = t.replacingOccurrences(of: "week", with: "w")
        t = t.replacingOccurrences(of: "days", with: "d")
        t = t.replacingOccurrences(of: "day", with: "d")
        t = t.replacingOccurrences(of: "hours", with: "h")
        t = t.replacingOccurrences(of: "hour", with: "h")
        t = t.replacingOccurrences(of: "minutes", with: "m")
        t = t.replacingOccurrences(of: "minute", with: "m")
        t = t.replacingOccurrences(of: "seconds", with: "s")
        t = t.replacingOccurrences(of: "second", with: "s")
        // Restore month token: we lowercased, so "M" became... wait, we lowercased first so month is "m" which clashes with minutes.
        // Re-parse from the original (non-lowercased) for M vs m, and accept case-insensitive words only.
        return parseTokens(s)
    }

    static func parseTokens(_ raw: String) -> BaseDuration? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        // Word forms, case-insensitive, longest first.
        let words: [(String, Character)] = [
            ("years", "y"), ("year", "y"),
            ("months", "M"), ("month", "M"),
            ("weeks", "w"), ("week", "w"),
            ("days", "d"), ("day", "d"),
            ("hours", "h"), ("hour", "h"),
            ("minutes", "m"), ("minute", "m"),
            ("seconds", "s"), ("second", "s"),
        ]
        var lowered = s
        for (w, u) in words {
            if let r = lowered.range(of: w, options: .caseInsensitive) {
                lowered.replaceSubrange(r, with: String(u))
            }
        }
        s = lowered.replacingOccurrences(of: " ", with: "")
        var sign = 1.0
        if s.hasPrefix("+") { s.removeFirst() }
        else if s.hasPrefix("-") { sign = -1; s.removeFirst() }
        var out = BaseDuration()
        var i = s.startIndex
        var found = false
        while i < s.endIndex {
            // number
            var j = i
            if s[j] == "." || s[j].isNumber {
                if s[j] == "." { j = s.index(after: j) }
                while j < s.endIndex, s[j].isNumber { j = s.index(after: j) }
                if j < s.endIndex, s[j] == "." {
                    j = s.index(after: j)
                    while j < s.endIndex, s[j].isNumber { j = s.index(after: j) }
                }
            } else {
                return nil
            }
            let num = Double(s[i..<j]) ?? 0
            guard j < s.endIndex else { return nil }
            let u = s[j]
            i = s.index(after: j)
            found = true
            let v = num * sign
            switch u {
            case "y", "Y": out.years += Int(v); if v != Double(Int(v)) { out.days += Int((v - Double(Int(v))) * 365) }
            case "M": out.months += Int(v)
            case "w": out.weeks += Int(v)
            case "d":
                if v == Double(Int(v)) { out.days += Int(v) }
                else { out.seconds += v * 86_400 }
            case "h":
                if v == Double(Int(v)) { out.hours += Int(v) }
                else { out.seconds += v * 3_600 }
            case "m":
                if v == Double(Int(v)) { out.minutes += Int(v) }
                else { out.seconds += v * 60 }
            case "s": out.seconds += v
            default: return nil
            }
        }
        return found ? out : nil
    }

    /// Difference between two dates, stored as days + leftover seconds.
    public static func between(_ a: Date, _ b: Date) -> BaseDuration {
        let s = b.timeIntervalSince(a)
        let days = Int(s / 86_400)
        return BaseDuration(days: days, seconds: s - Double(days) * 86_400)
    }
}

extension Bases {
    /// File-level custom summary formulas plus the built-in names (count, sum, average, …).
    static func parseSummaries(_ v: YAML.Value?) -> [String: String] {
        guard let v, v != .null else { return [:] }
        if let m = v.map {
            var out: [String: String] = [:]
            for (k, val) in m { if let s = val.string { out[k] = s } }
            return out
        }
        return [:]
    }

    static func attachSummaries(_ result: inout BaseResult, file: BaseFile, snap: VaultSnapshot) {
        let specs = result.view.summaries
        guard !specs.isEmpty else { return }
        func row(_ rows: [BaseRowView]) -> [String: BaseValue] {
            var out: [String: BaseValue] = [:]
            var warnings: [String] = []
            for col in result.columns {
                guard let name = specs[col.key] ?? specs[col.displayName] else { continue }
                let vals = rows.map { $0.cells[col.key] ?? .null }
                out[col.key] = summarize(name, values: vals, custom: file.summaries, snap: snap, warnings: &warnings)
            }
            for (key, name) in specs where out[key] == nil {
                let vals = rows.map { $0.cells[key] ?? .null }
                out[key] = summarize(name, values: vals, custom: file.summaries, snap: snap, warnings: &warnings)
            }
            result.warnings.append(contentsOf: warnings)
            result.warnings = uniq(result.warnings)
            return out
        }
        result.summaries = row(result.rows)
        if var groups = result.groups {
            for i in groups.indices {
                groups[i].summaries = row(groups[i].rows)
            }
            result.groups = groups
        }
    }

    public static func summarize(_ name: String, values: [BaseValue], custom: [String: String], snap: VaultSnapshot, warnings: inout [String]) -> BaseValue {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let lower = trimmed.lowercased()
        let nums = values.compactMap { number(of: $0) }
        let dates = values.compactMap { date(of: $0) }
        switch lower {
        case "count":
            return .number(Double(values.count))
        case "sum":
            return nums.isEmpty ? .null : .number(nums.reduce(0, +))
        case "average", "avg", "mean":
            return nums.isEmpty ? .null : .number(nums.reduce(0, +) / Double(nums.count))
        case "min":
            if let n = nums.min() { return .number(n) }
            let rest = values.filter { $0 != .null }
            return rest.min { $0.compare($1) < 0 } ?? .null
        case "max":
            if let n = nums.max() { return .number(n) }
            let rest = values.filter { $0 != .null }
            return rest.max { $0.compare($1) < 0 } ?? .null
        case "earliest":
            return dates.min().map { .date($0) } ?? .null
        case "latest":
            return dates.max().map { .date($0) } ?? .null
        case "unique":
            var seen = Set<String>()
            for v in values where v != .null { seen.insert(v.text.lowercased()) }
            return .number(Double(seen.count))
        case "empty":
            return .number(Double(values.filter { !$0.isTruthy }.count))
        case "filled":
            return .number(Double(values.filter { $0.isTruthy }.count))
        default:
            let formula = custom[trimmed] ?? custom.first { $0.key.lowercased() == lower }?.value
            if let src = formula {
                var ctx = EvalCtx(snap: snap, formulas: [:], current: nil, item: nil, memo: [:], warnings: [], bindings: ["values": .list(values)])
                let v = eval(src, ctx: &ctx)
                warnings.append(contentsOf: ctx.warnings)
                return v
            }
            warnings.append("Unknown summary “\(name)”.")
            return .null
        }
    }

    static func number(of v: BaseValue) -> Double? {
        if case .number(let n) = v { return n }
        if case .duration(let d) = v { return d.interval }
        if v == .null { return nil }
        return Double(v.text)
    }

    static func date(of v: BaseValue) -> Date? {
        if case .date(let d) = v { return d }
        if case .string(let s) = v { return BaseValue.day.date(from: s) ?? BaseValue.iso.date(from: s) }
        return nil
    }

    static func binaryDate(_ op: String, _ l: BaseValue, _ r: BaseValue) -> BaseValue? {
        func dur(_ v: BaseValue) -> BaseDuration? {
            if case .duration(let d) = v { return d }
            if case .string(let s) = v { return BaseDuration.parse(s) }
            return nil
        }
        if op == "+" {
            if case .date(let d) = l, let du = dur(r) { return .date(du.adding(to: d)) }
            if case .date(let d) = r, let du = dur(l) { return .date(du.adding(to: d)) }
            if case .duration(let a) = l, case .duration(let b) = r { return .duration(a + b) }
            if case .duration(let a) = l, let du = dur(r) { return .duration(a + du) }
            if case .duration(let a) = l, case .number(let n) = r { return .duration(a * n) }
            return nil
        }
        if op == "-" {
            if case .date(let a) = l, case .date(let b) = r { return .duration(BaseDuration.between(b, a)) }
            if case .date(let d) = l, let du = dur(r) {
                var neg = du
                neg.years = -neg.years; neg.months = -neg.months; neg.weeks = -neg.weeks
                neg.days = -neg.days; neg.hours = -neg.hours; neg.minutes = -neg.minutes; neg.seconds = -neg.seconds
                return .date(neg.adding(to: d))
            }
            if case .duration(let a) = l, case .duration(let b) = r { return .duration(a - b) }
            if case .duration(let a) = l, let du = dur(r) { return .duration(a - du) }
            return nil
        }
        if op == "*" {
            if case .duration(let a) = l, case .number(let n) = r { return .duration(a * n) }
            if case .number(let n) = l, case .duration(let a) = r { return .duration(a * n) }
            return nil
        }
        if op == "/" {
            if case .duration(let a) = l, case .number(let n) = r, n != 0 { return .duration(a * (1 / n)) }
            return nil
        }
        return nil
    }

    static func extraMethod(_ name: String, _ args: [BaseValue], recv: BaseValue, lambda: (param: String, body: Expr)?, ctx: inout EvalCtx) -> BaseValue? {
        let n = name.lowercased()
        switch recv {
        case .date(let d):
            switch n {
            case "format":
                let pat = args.first?.text ?? "YYYY-MM-DD"
                return .string(formatDate(d, pattern: pat))
            case "relative":
                return .string(relativeDate(d))
            case "year": return .number(Double(Calendar.current.component(.year, from: d)))
            case "month": return .number(Double(Calendar.current.component(.month, from: d)))
            case "day": return .number(Double(Calendar.current.component(.day, from: d)))
            case "hour": return .number(Double(Calendar.current.component(.hour, from: d)))
            case "minute": return .number(Double(Calendar.current.component(.minute, from: d)))
            case "second": return .number(Double(Calendar.current.component(.second, from: d)))
            case "date": return .date(Calendar.current.startOfDay(for: d))
            default: break
            }
        case .duration:
            break
        case .number(let x):
            switch n {
            case "round":
                let digits = Int((args.first.flatMap { number(of: $0) }) ?? 0)
                if digits <= 0 { return .number((x as Double).rounded()) }
                let p = pow(10.0, Double(max(0, min(digits, 10))))
                return .number((x * p).rounded() / p)
            case "abs": return .number(abs(x))
            case "ceil": return .number((x as Double).rounded(.up))
            case "floor": return .number((x as Double).rounded(.down))
            default: break
            }
        case .string, .link, .bool, .null:
            break
        case .list(let l):
            switch n {
            case "length", "count": return .number(Double(l.count))
            case "join":
                let sep = args.first?.text ?? ","
                return .string(l.map(\.text).joined(separator: sep))
            case "contains":
                return nil // existing handler
            case "filter":
                return listFilter(l, args: args, lambda: lambda, ctx: &ctx)
            case "map":
                return listMap(l, args: args, lambda: lambda, ctx: &ctx)
            case "sum":
                let nums = l.compactMap { number(of: $0) }
                return nums.isEmpty ? .null : .number(nums.reduce(0, +))
            case "mean", "average":
                let nums = l.compactMap { number(of: $0) }
                return nums.isEmpty ? .null : .number(nums.reduce(0, +) / Double(nums.count))
            case "min":
                let nums = l.compactMap { number(of: $0) }
                return nums.min().map { .number($0) } ?? .null
            case "max":
                let nums = l.compactMap { number(of: $0) }
                return nums.max().map { .number($0) } ?? .null
            case "unique":
                var seen = Set<String>(), out: [BaseValue] = []
                for v in l {
                    if seen.insert(v.text).inserted { out.append(v) }
                }
                return .list(out)
            default: break
            }
        }
        // String methods — also work on the text of other values.
        let text = recv.text
        switch n {
        case "length", "count":
            if case .list = recv { break }
            return .number(Double(text.count))
        case "slice":
            let start = Int((args.first.flatMap { number(of: $0) }) ?? 0)
            let end = args.count > 1 ? Int(number(of: args[1]) ?? Double(text.count)) : text.count
            return .string(slice(text, start: start, end: end))
        case "replace":
            let old = args.first?.text ?? ""
            let new = args.count > 1 ? args[1].text : ""
            return .string(text.replacingOccurrences(of: old, with: new))
        case "split":
            let sep = args.first?.text ?? ""
            if sep.isEmpty { return .list(text.map { .string(String($0)) }) }
            return .list(text.components(separatedBy: sep).map { .string($0) })
        case "title":
            return .string(text.capitalized)
        case "trim":
            return .string(text.trimmingCharacters(in: .whitespacesAndNewlines))
        case "format":
            if case .date(let d) = recv { return .string(formatDate(d, pattern: args.first?.text ?? "YYYY-MM-DD")) }
            return nil
        case "relative":
            if case .date(let d) = recv { return .string(relativeDate(d)) }
            return nil
        default:
            return nil
        }
        return nil
    }

    static func listFilter(_ l: [BaseValue], args: [BaseValue], lambda: (param: String, body: Expr)?, ctx: inout EvalCtx) -> BaseValue {
        if let lambda {
            var out: [BaseValue] = []
            for v in l {
                let saved = ctx.bindings
                ctx.bindings[lambda.param] = v
                if ctx.bindings["value"] == nil { ctx.bindings["value"] = v }
                if evalExpr(lambda.body, ctx: &ctx).isTruthy { out.append(v) }
                ctx.bindings = saved
            }
            return .list(out)
        }
        if let want = args.first {
            return .list(l.filter { equal($0, want) || $0.text.localizedCaseInsensitiveContains(want.text) })
        }
        return .list(l.filter { $0.isTruthy })
    }

    static func listMap(_ l: [BaseValue], args: [BaseValue], lambda: (param: String, body: Expr)?, ctx: inout EvalCtx) -> BaseValue {
        if let lambda {
            var out: [BaseValue] = []
            for v in l {
                let saved = ctx.bindings
                ctx.bindings[lambda.param] = v
                if ctx.bindings["value"] == nil { ctx.bindings["value"] = v }
                out.append(evalExpr(lambda.body, ctx: &ctx))
                ctx.bindings = saved
            }
            return .list(out)
        }
        return .list(l)
    }

    static func slice(_ s: String, start: Int, end: Int) -> String {
        let chars = Array(s)
        var a = start, b = end
        if a < 0 { a = max(0, chars.count + a) }
        if b < 0 { b = max(0, chars.count + b) }
        a = min(max(0, a), chars.count)
        b = min(max(a, b), chars.count)
        return String(chars[a..<b])
    }

    /// Moment-style tokens used by Bases `date.format()`: YYYY, YY, MMMM, MMM, MM, M, DD, D, HH, H, mm, m, ss, s, A, a.
    static func formatDate(_ d: Date, pattern: String) -> String {
        let cal = Calendar.current
        let y = cal.component(.year, from: d)
        let mo = cal.component(.month, from: d)
        let day = cal.component(.day, from: d)
        let h = cal.component(.hour, from: d)
        let mi = cal.component(.minute, from: d)
        let s = cal.component(.second, from: d)
        let months = DateFormatter()
        months.locale = Locale(identifier: "en_US")
        let tokens: [(String, String)] = [
            ("YYYY", String(format: "%04d", y)),
            ("YY", String(format: "%02d", y % 100)),
            ("MMMM", months.monthSymbols[max(0, min(11, mo - 1))]),
            ("MMM", months.shortMonthSymbols[max(0, min(11, mo - 1))]),
            ("MM", String(format: "%02d", mo)),
            ("DD", String(format: "%02d", day)),
            ("HH", String(format: "%02d", h)),
            ("mm", String(format: "%02d", mi)),
            ("ss", String(format: "%02d", s)),
            ("A", h >= 12 ? "PM" : "AM"),
            ("a", h >= 12 ? "pm" : "am"),
        ]
        // Replace longest tokens first; then single-letter M, D, H, m, s that remain.
        var out = pattern
        var holders: [String: String] = [:]
        for (i, (tok, val)) in tokens.enumerated() {
            let h = "\u{1A}\(i)\u{1A}"
            if out.contains(tok) {
                out = out.replacingOccurrences(of: tok, with: h)
                holders[h] = val
            }
        }
        let singles: [(Character, String)] = [
            ("M", String(mo)),
            ("D", String(day)),
            ("H", String(h)),
            ("m", String(mi)),
            ("s", String(s)),
        ]
        var built = ""
        for ch in out {
            if let v = singles.first(where: { $0.0 == ch })?.1 {
                built.append(v)
            } else {
                built.append(ch)
            }
        }
        out = built
        for (h, val) in holders { out = out.replacingOccurrences(of: h, with: val) }
        return out
    }

    static func relativeDate(_ d: Date, now: Date = Date()) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        f.locale = Locale(identifier: "en_US")
        return f.localizedString(for: d, relativeTo: now)
    }
}
