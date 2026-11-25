import Foundation

/// One commit that touched a note, from `git log --follow`.
public struct NoteHistoryEntry: Equatable, Sendable, Identifiable, Hashable {
    public var id: String { hash + "\u{1f}" + path }
    public var hash: String
    public var date: Date
    public var author: String
    public var subject: String
    /// The note's path in this commit (follows renames).
    public var path: String
    public var shortHash: String { String(hash.prefix(7)) }

    public init(hash: String, date: Date, author: String, subject: String, path: String) {
        self.hash = hash; self.date = date; self.author = author; self.subject = subject; self.path = path
    }
}

/// What `git show` produced for one historical path.
public enum NoteVersionContent: Equatable, Sendable {
    case text(String)
    case binary
    case missing
}

/// The text side of per-note version history: parse `git log --follow`, a line diff,
/// and a small store that only *reads* a repo (never checkout, reset, or write).
public enum NoteHistory {
    public static let recordSep: Character = "\u{1e}"
    public static let fieldSep: Character = "\u{1f}"

    /// Pretty format used with `--name-only` so each record is
    /// `RS hash US date US author US subject LF path`.
    public static let prettyFormat = "%x1e%H%x1f%aI%x1f%an%x1f%s"

    public static func gitBinary() -> String? {
        ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/usr/bin/git"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    /// The vault folder itself is a git work tree (its own `.git`).
    public static func isRepository(_ root: URL) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path)
    }

    /// Parse the output of
    /// `git log --follow --pretty=format:%x1e%H%x1f%aI%x1f%an%x1f%s --name-only`.
    public static func parseLog(_ output: String) -> [NoteHistoryEntry] {
        output.split(separator: recordSep, omittingEmptySubsequences: true).compactMap { rec in
            let text = rec.trimmingCharacters(in: .newlines)
            guard !text.isEmpty else { return nil }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let header = lines.first else { return nil }
            let f = header.split(separator: fieldSep, omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 4, !f[0].isEmpty, let date = parseDate(f[1]) else { return nil }
            let path = lines.dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
            return NoteHistoryEntry(hash: f[0], date: date, author: f[2], subject: f[3], path: path)
        }
    }

    public static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withColonSeparatorInTimeZone]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

/// Read-only access to a note's git history. Never mutates the repository.
public struct NoteHistoryStore: Sendable {
    public let root: URL
    public let git: String
    public var limit = 200

    public static func detect(_ root: URL) -> NoteHistoryStore? {
        guard NoteHistory.isRepository(root), let g = NoteHistory.gitBinary() else { return nil }
        return NoteHistoryStore(root: root, git: g)
    }

    public init(root: URL, git: String) { self.root = root; self.git = git }

    public func entries(for path: String) -> [NoteHistoryEntry] {
        let rel = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !rel.isEmpty else { return [] }
        let r = run(["log", "--follow", "-n", "\(limit)", "--pretty=format:\(NoteHistory.prettyFormat)", "--name-only", "--", rel])
        guard r.code == 0 else { return [] }
        return NoteHistory.parseLog(r.out)
    }

    public func content(of entry: NoteHistoryEntry) -> NoteVersionContent {
        let spec = "\(entry.hash):\(entry.path)"
        let r = run(["show", spec])
        guard r.code == 0 else { return .missing }
        if r.data.contains(0) { return .binary }
        guard let s = String(data: r.data, encoding: .utf8) else { return .binary }
        return .text(s)
    }

    public struct Out: Sendable { public var code: Int32; public var out: String; public var data: Data }

    @discardableResult
    public func run(_ args: [String], timeout: TimeInterval = 30) -> Out {
        #if os(macOS)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: git)
        p.arguments = ["-C", root.path] + args
        var e = ProcessInfo.processInfo.environment
        e["GIT_TERMINAL_PROMPT"] = "0"
        e["GIT_EDITOR"] = "true"
        e["LC_ALL"] = "C"
        e["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (e["PATH"] ?? "")
        p.environment = e
        let o = Pipe(), er = Pipe()
        p.standardOutput = o; p.standardError = er; p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return Out(code: -1, out: "", data: Data()) }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        var od = Data()
        let g = DispatchGroup()
        g.enter(); DispatchQueue.global().async { od = o.fileHandleForReading.readDataToEndOfFile(); g.leave() }
        g.enter(); DispatchQueue.global().async { _ = er.fileHandleForReading.readDataToEndOfFile(); g.leave() }
        g.wait(); p.waitUntilExit(); killer.cancel()
        return Out(code: p.terminationStatus, out: String(decoding: od, as: UTF8.self), data: od)
        #else
        return Out(code: -1, out: "", data: Data())
        #endif
    }
}

// MARK: - Line diff (Myers)

/// A line-oriented diff of two texts: the historical version (`old`) against the current note (`new`).
public enum NoteDiff {
    public enum Line: Equatable, Sendable {
        case same(String)
        case insert(String)
        case delete(String)
        public var text: String {
            switch self { case .same(let s), .insert(let s), .delete(let s): return s }
        }
        public var isChange: Bool {
            if case .same = self { return false }
            return true
        }
    }

    public static func splitLines(_ s: String) -> [String] {
        if s.isEmpty { return [] }
        var parts = s.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if s.hasSuffix("\n") { parts.removeLast() }
        return parts
    }

    public static func lines(old: String, new: String) -> [Line] {
        myers(splitLines(old), splitLines(new))
    }

    /// True when the two texts are identical as split lines (and both empty).
    public static func isIdentical(_ old: String, _ new: String) -> Bool {
        old == new
    }

    public static func unified(old: String, new: String, oldLabel: String = "a", newLabel: String = "b") -> String {
        let rows = lines(old: old, new: new)
        if rows.isEmpty || rows.allSatisfy({ !$0.isChange }) { return "" }
        var out = "--- \(oldLabel)\n+++ \(newLabel)\n"
        for r in rows {
            switch r {
            case .same(let s): out += " \(s)\n"
            case .insert(let s): out += "+\(s)\n"
            case .delete(let s): out += "-\(s)\n"
            }
        }
        return out
    }

    /// Myers O((N+M)D) edit script, with matching prefix/suffix stripped first.
    static func myers(_ aIn: [String], _ bIn: [String]) -> [Line] {
        var a = aIn, b = bIn
        var prefix: [Line] = []
        while let x = a.first, let y = b.first, x == y {
            prefix.append(.same(x)); a.removeFirst(); b.removeFirst()
        }
        var suffix: [Line] = []
        while let x = a.last, let y = b.last, x == y {
            suffix.append(.same(x)); a.removeLast(); b.removeLast()
        }
        suffix.reverse()
        return prefix + myersCore(a, b) + suffix
    }

    static func myersCore(_ a: [String], _ b: [String]) -> [Line] {
        let n = a.count, m = b.count
        if n == 0 { return b.map { .insert($0) } }
        if m == 0 { return a.map { .delete($0) } }
        let offset = n + m
        var v = Array(repeating: 0, count: 2 * offset + 1)
        var trace: [[Int]] = []
        var dFound: Int?
        for d in 0...(n + m) {
            var vd = v
            for k in stride(from: -d, through: d, by: 2) {
                let idx = k + offset
                var x: Int
                if k == -d || (k != d && v[idx - 1] < v[idx + 1]) {
                    x = v[idx + 1]
                } else {
                    x = v[idx - 1] + 1
                }
                var y = x - k
                while x < n && y < m && a[x] == b[y] { x += 1; y += 1 }
                vd[idx] = x
                if x >= n && y >= m {
                    v = vd
                    trace.append(vd)
                    dFound = d
                    break
                }
            }
            if dFound != nil { break }
            v = vd
            trace.append(vd)
        }
        guard let D = dFound, trace.indices.contains(D) else {
            return a.map { .delete($0) } + b.map { .insert($0) }
        }
        var x = n, y = m
        var rev: [Line] = []
        for d in stride(from: D, through: 0, by: -1) {
            let tv = trace[d]
            let k = x - y
            if d == 0 {
                while x > 0 && y > 0 { x -= 1; y -= 1; rev.append(.same(a[x])) }
                break
            }
            let down = k == -d || (k != d && tv[k - 1 + offset] < tv[k + 1 + offset])
            let prevK = down ? k + 1 : k - 1
            let prevX = tv[prevK + offset]
            let prevY = prevX - prevK
            while x > prevX && y > prevY {
                x -= 1; y -= 1
                rev.append(.same(a[x]))
            }
            if down {
                y -= 1
                if y >= 0 { rev.append(.insert(b[y])) }
            } else {
                x -= 1
                if x >= 0 { rev.append(.delete(a[x])) }
            }
        }
        return rev.reversed()
    }
}
