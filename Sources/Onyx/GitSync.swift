import Foundation
import AppKit
import OnyxCore

/// Continuous git for a vault that is a git repository: commit a moment after edits settle
/// (and at once on delete / rename / move / switching notes / leaving the app / quit), push
/// after every commit, and pull --rebase on launch, on focus, before each push and every 30s.
///
/// Never force-pushes, never rewrites published history, never drops work: on a rebase
/// conflict the local version keeps the path and the remote one is written beside it as
/// "Note (conflict YYYY-MM-DD HHMM).md", both committed. Anything unexpected → rebase --abort,
/// which leaves the local branch exactly as it was.
@Observable @MainActor final class GitSync {
    enum State: Equatable { case synced, committing, pulling, pushing, offline, conflict, localOnly, failed }
    private(set) var state: State = .synced
    private(set) var detail = ""
    private(set) var lastSync: Date?
    private(set) var lastCommit: String?
    private(set) var conflictCopies: [String] = []
    let root: URL

    @ObservationIgnored private let git: String
    @ObservationIgnored private let queue = DispatchQueue(label: "onyx.git", qos: .utility)
    @ObservationIgnored private var debounce: DispatchWorkItem?
    @ObservationIgnored private var retry: DispatchWorkItem?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var inFlight = false
    @ObservationIgnored private var pending: (sync: Bool, reason: String?)?
    /// Called on the main thread before each commit (Workspace flushes its pending save).
    @ObservationIgnored var beforeCommit: () -> Void = {}
    /// Called on the main thread after a commit, pull, push, conflict, or error.
    @ObservationIgnored var onLog: (SyncLogEvent, String) -> Void = { _, _ in }
    @ObservationIgnored var settle: TimeInterval = 1.0
    @ObservationIgnored var interval: TimeInterval = 30

    static func gitBinary() -> String? {
        ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/usr/bin/git"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    /// A GitSync when `root` itself is a git work tree (its own .git) and git is installed.
    static func detect(_ root: URL) -> GitSync? {
        guard ProcessInfo.processInfo.environment["ONYX_NO_GIT"] == nil,
              FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path),
              let g = gitBinary() else { return nil }
        return GitSync(root: root, git: g)
    }
    private init(root: URL, git: String) { self.root = root; self.git = git }

    func start() {
        if let s = ProcessInfo.processInfo.environment["ONYX_GIT_INTERVAL"], let v = Double(s) { interval = v }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncNow() }
        }
        syncNow()
    }
    func stop() { timer?.invalidate(); timer = nil; debounce?.cancel(); retry?.cancel() }

    // MARK: Triggers

    /// Something was written: commit and push once things have been quiet for `settle`.
    func edited() {
        debounce?.cancel()
        let w = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.request(sync: true, reason: nil) } }
        debounce = w
        DispatchQueue.main.asyncAfter(deadline: .now() + settle, execute: w)
    }
    /// Commit (and push) right away, e.g. "Delete Old Note".
    func commitNow(reason: String? = nil) { debounce?.cancel(); request(sync: true, reason: reason) }
    func syncNow() { request(sync: true, reason: nil) }

    /// Quit: commit synchronously, then try to push for a few seconds.
    func finishForQuit() {
        stop()
        beforeCommit()
        let done = DispatchSemaphore(value: 0)
        let ops = Ops(root: root, git: git)
        queue.async { _ = ops.commit(reason: nil); _ = ops.sync(timeout: 6); done.signal() }
        _ = done.wait(timeout: .now() + 8)
    }

    private func request(sync: Bool, reason: String?) {
        if inFlight {
            pending = (sync || (pending?.sync ?? false), reason ?? pending?.reason)
            return
        }
        inFlight = true
        beforeCommit()
        let ops = Ops(root: root, git: git)
        queue.async { [weak self] in
            let commit = ops.commit(reason: reason)
            let result = sync ? ops.sync(timeout: 60) : .ok(Ops.Report())
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.finished(commit: commit, result: result) } }
        }
        if state != .conflict { state = sync ? .pulling : .committing }
    }

    private func finished(commit: String?, result: Ops.Result) {
        inFlight = false
        if let commit { lastCommit = commit }
        switch result {
        case .ok(let report):
            failures = 0; retry?.cancel()
            lastSync = Date()
            if !report.copies.isEmpty {
                conflictCopies += report.copies
                state = .conflict
                detail = "Kept both versions: " + report.copies.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
            } else if state != .conflict || conflictCopies.allSatisfy({ !FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }) {
                conflictCopies = []
                state = .synced; detail = "Synced"
            }
            if let commit { onLog(.commit, commit) }
            if report.pulled > 0 { onLog(.pull, report.pulled == 1 ? "Received 1 commit" : "Received \(report.pulled) commits") }
            if report.pushed > 0 { onLog(.push, report.pushed == 1 ? "Pushed 1 commit" : "Pushed \(report.pushed) commits") }
            if !report.copies.isEmpty {
                onLog(.conflict, "Kept both versions: " + report.copies.map { ($0 as NSString).lastPathComponent }.joined(separator: ", "))
            }
        case .localOnly:
            failures = 0; state = .localOnly; detail = "Committed locally (no remote)"
            if let commit { onLog(.commit, commit) }
        case .offline(let msg):
            failures += 1
            let wait = GitText.backoff(failures)
            state = .offline; detail = "Offline, retrying in \(Int(wait))s. \(msg)"
            if let commit { onLog(.commit, commit) }
            onLog(.error, "Offline: \(msg)")
            retry?.cancel()
            let w = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.syncNow() } }
            retry = w
            DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: w)
        case .failed(let msg):
            state = .failed; detail = msg
            if let commit { onLog(.commit, commit) }
            onLog(.error, msg)
        case .busy(let msg):
            state = .conflict; detail = msg
            onLog(.conflict, msg)
        }
        if let p = pending { pending = nil; request(sync: p.sync, reason: p.reason) }
    }

    var help: String {
        var s: String
        switch state {
        case .synced: s = "Git: synced"
        case .committing: s = "Git: committing…"
        case .pulling: s = "Git: syncing…"
        case .pushing: s = "Git: pushing…"
        case .offline: s = "Git: offline"
        case .conflict: s = "Git: conflict"
        case .localOnly: s = "Git: local only"
        case .failed: s = "Git: needs attention"
        }
        if !detail.isEmpty, detail != "Synced" { s += " · " + detail }
        if let d = lastSync { s += " · last sync \(d.formatted(date: .omitted, time: .shortened))" }
        if let c = lastCommit { s += "\nLast commit: \(c)" }
        return s
    }
}

/// The git work itself, off the main thread. Stateless; every call reads the repo fresh.
struct Ops: Sendable {
    let root: URL
    let git: String

    struct Report: Sendable { var copies: [String] = []; var pulled = 0; var pushed = 0 }
    enum Result: Sendable { case ok(Report), localOnly, offline(String), failed(String), busy(String) }

    struct Out { var code: Int32; var out: String; var err: String; var data: Data }
    @discardableResult
    func run(_ args: [String], timeout: TimeInterval = 30, env: [String: String] = [:]) -> Out {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: git)
        p.arguments = ["-C", root.path] + args
        var e = ProcessInfo.processInfo.environment
        e["GIT_TERMINAL_PROMPT"] = "0"
        e["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes -o ConnectTimeout=10"
        e["GIT_EDITOR"] = "true"
        e["LC_ALL"] = "C"
        e["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (e["PATH"] ?? "")
        for (k, v) in env { e[k] = v }
        p.environment = e
        let o = Pipe(), er = Pipe()
        p.standardOutput = o; p.standardError = er; p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return Out(code: -1, out: "", err: error.localizedDescription, data: Data()) }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        var od = Data(), ed = Data()
        let g = DispatchGroup()
        g.enter(); DispatchQueue.global().async { od = o.fileHandleForReading.readDataToEndOfFile(); g.leave() }
        g.enter(); DispatchQueue.global().async { ed = er.fileHandleForReading.readDataToEndOfFile(); g.leave() }
        g.wait(); p.waitUntilExit(); killer.cancel()
        let timedOut = p.terminationReason == .uncaughtSignal
        return Out(code: p.terminationStatus, out: String(decoding: od, as: UTF8.self),
                   err: String(decoding: ed, as: UTF8.self) + (timedOut ? "\noperation timed out" : ""), data: od)
    }
    func line(_ args: [String]) -> String? {
        let r = run(args); return r.code == 0 ? r.out.trimmingCharacters(in: .whitespacesAndNewlines) : nil
    }

    var gitDir: URL { URL(fileURLWithPath: line(["rev-parse", "--absolute-git-dir"]) ?? root.appendingPathComponent(".git").path) }
    var rebasing: Bool {
        let fm = FileManager.default, d = gitDir
        return fm.fileExists(atPath: d.appendingPathComponent("rebase-merge").path) || fm.fileExists(atPath: d.appendingPathComponent("rebase-apply").path)
    }
    var merging: Bool { FileManager.default.fileExists(atPath: gitDir.appendingPathComponent("MERGE_HEAD").path) }

    /// Stage everything and commit it with a message naming the notes. Returns the subject.
    func commit(reason: String?) -> String? {
        guard !rebasing, !merging else { return nil }
        run(["add", "-A"])
        let ns = run(["diff", "--cached", "--name-status", "-M"]).out
        let changes = GitText.parseNameStatus(ns)
        guard !changes.isEmpty else { return nil }
        let msg = GitText.commitMessage(changes, reason: reason)
        var args = ["commit", "-q", "--no-verify", "-m", msg]
        if (line(["config", "user.email"]) ?? "").isEmpty {
            args = ["-c", "user.name=Onyx", "-c", "user.email=onyx@\(ProcessInfo.processInfo.hostName)"] + args
        }
        let r = run(args)
        return r.code == 0 ? String(msg.split(separator: "\n").first ?? "") : nil
    }

    /// fetch → rebase onto upstream (resolving conflicts by keeping both) → push; retried on
    /// a non-fast-forward. No remote: local only.
    func sync(timeout: TimeInterval) -> Result {
        if rebasing || merging { return .busy("A rebase or merge is in progress in the vault; Onyx is waiting") }
        let remotes = (line(["remote"]) ?? "").split(separator: "\n").map(String.init)
        guard !remotes.isEmpty else { return .localOnly }
        guard let branch = line(["symbolic-ref", "--short", "-q", "HEAD"]) else { return .failed("Detached HEAD; not syncing") }
        var upstream = line(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"])
        let remote = upstream.map { String($0.split(separator: "/").first ?? "origin") } ?? (remotes.contains("origin") ? "origin" : remotes[0])
        var report = Report()
        for _ in 0..<4 {
            let f = run(["fetch", "--quiet", "--prune", remote], timeout: timeout)
            if f.code != 0 { return GitText.isNetworkError(f.err) ? .offline(firstLine(f.err)) : .failed(firstLine(f.err)) }
            if upstream == nil, line(["rev-parse", "--verify", "-q", "\(remote)/\(branch)"]) != nil {
                run(["branch", "--set-upstream-to=\(remote)/\(branch)"]); upstream = "\(remote)/\(branch)"
            }
            if let u = upstream, let behind = Int(line(["rev-list", "--count", "HEAD..\(u)"]) ?? "0"), behind > 0 {
                let r = run(["-c", "rebase.autoStash=true", "rebase", "--quiet", u], timeout: timeout)
                if r.code != 0 {
                    guard rebasing else { return .failed("Rebase failed: " + firstLine(r.err)) }
                    switch resolveRebase() {
                    case .some(let c): report.copies += c
                    case .none:
                        run(["rebase", "--abort"])
                        return .failed("Couldn’t replay local commits onto \(u); left them as they were (nothing lost)")
                    }
                }
                report.pulled += behind
            }
            let ahead = upstream.flatMap { Int(line(["rev-list", "--count", "\($0)..HEAD"]) ?? "0") } ?? 1
            guard ahead > 0 else { return .ok(report) }
            let p = upstream == nil ? run(["push", "--quiet", "-u", remote, "HEAD"], timeout: timeout)
                                    : run(["push", "--quiet", remote, "HEAD:\(branch)"], timeout: timeout)
            if p.code == 0 {
                if upstream == nil { upstream = "\(remote)/\(branch)" }
                report.pushed += ahead
                return .ok(report)
            }
            if GitText.isNetworkError(p.err) { return .offline(firstLine(p.err)) }
            if !GitText.isNonFastForward(p.err) { return .failed("Push refused: " + firstLine(p.err)) }
            // the remote moved on between fetch and push: go round again
        }
        return .failed("The remote keeps moving; will try again")
    }

    /// Inside a stopped rebase: for every conflicted file keep the local version at its path and
    /// write the remote version beside it as a conflict copy, then continue. Returns the copies,
    /// or nil if the rebase couldn't be finished this way (caller aborts).
    func resolveRebase() -> [String]? {
        var copies: [String] = []
        for _ in 0..<100 {
            guard rebasing else { return copies }
            let unmerged = Set(run(["diff", "--name-only", "--diff-filter=U", "-z"]).out.split(separator: "\0").map(String.init))
            if unmerged.isEmpty {
                let c = run(["rebase", "--continue"])
                if c.code != 0, rebasing, Set(run(["diff", "--name-only", "--diff-filter=U", "-z"]).out.split(separator: "\0")).isEmpty {
                    // the replayed commit became empty
                    if run(["rebase", "--skip"]).code != 0 && rebasing { return nil }
                }
                continue
            }
            for p in unmerged.sorted() {
                let remoteSide = show(":2:\(p)")   // upstream (what's already on the remote)
                let localSide = show(":3:\(p)")    // the local commit being replayed
                let url = root.appendingPathComponent(p)
                do {
                    switch (remoteSide, localSide) {
                    case let (r?, l?):
                        if r == l { try l.write(to: url, options: .atomic); run(["add", "--", p]); continue }
                        let copy = GitText.conflictCopy(p, exists: { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) })
                        try l.write(to: url, options: .atomic)
                        try r.write(to: root.appendingPathComponent(copy), options: .atomic)
                        run(["add", "--", p, copy]); copies.append(copy)
                    case let (nil, l?):   // deleted on the remote, edited here: keep the edit
                        try l.write(to: url, options: .atomic); run(["add", "--", p])
                    case let (r?, nil):   // deleted here, edited on the remote: keep their edit
                        try r.write(to: url, options: .atomic); run(["add", "--", p])
                    case (nil, nil):
                        run(["rm", "-q", "--cached", "--ignore-unmatch", "--", p])
                    }
                } catch { return nil }
            }
            let c = run(["rebase", "--continue"])
            if c.code != 0, rebasing, !Set(run(["diff", "--name-only", "--diff-filter=U", "-z"]).out.split(separator: "\0")).isEmpty { continue }
        }
        return rebasing ? nil : copies
    }
    func show(_ spec: String) -> Data? { let r = run(["show", spec]); return r.code == 0 ? r.data : nil }
    func firstLine(_ s: String) -> String {
        s.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty && !$0.hasPrefix("hint:") } ?? "git error"
    }
}
