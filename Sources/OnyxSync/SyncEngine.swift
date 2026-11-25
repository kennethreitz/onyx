import Foundation

public enum SyncPhase: Equatable, Sendable {
    case connecting
    case syncing(String)
    case synced
    case paused
    case offline(String)
    case error(String)
    /// Stopped and waiting for the user (e.g. a mass deletion); call `confirmPendingAction()` or fix it.
    case needsAttention(String)
}

public struct SyncStatus: Equatable, Sendable {
    public var phase: SyncPhase
    public var lastSynced: Date?
    public var initialMerge: Bool
    public init(phase: SyncPhase, lastSynced: Date?, initialMerge: Bool) {
        self.phase = phase; self.lastSynced = lastSynced; self.initialMerge = initialMerge
    }
}

/// Exponential reconnect backoff, Obsidian's `NA(0, 300 s, 5 s, jitter)`.
struct Backoff {
    var min = 0.0, max = 300.0, base = 5.0, jitter = true
    var count = 0
    var next = Date.distantPast
    mutating func success() { count = 0; next = Date().addingTimeInterval(timeout()) }
    mutating func fail() { count += 1; next = Date().addingTimeInterval(timeout()) }
    var isReady: Bool { Date() > next }
    func timeout() -> TimeInterval {
        if count == 0 { return min }
        var e = base * pow(2, Double(count - 1))
        if jitter { e *= 0.5 + 0.5 * Double.random(in: 0..<1) }
        return Swift.min(max, min + e)
    }
}

/// Two-way sync of one local folder with one Obsidian Sync vault. A port of the desktop client's `_sync` loop
/// (Obsidian 1.15.1), one operation per pass, plus Onyx safety rails:
/// - first connect: no deletions on either side, differing files kept twice (see `SyncState.initialMerge`);
/// - an empty-looking vault folder or a mass deletion pauses instead of propagating;
/// - local deletions go to the Trash, overwritten Markdown is backed up first.
public actor SyncEngine {
    public enum DeleteMode: Sendable { case trash, remove }
    public struct Options: Sendable {
        public var allowLocalHost = false
        public var deleteMode = DeleteMode.trash
        /// Where overwritten local text is copied before a merge/download replaces it (nil = no backups).
        public var backupDir: URL?
        public var periodic: TimeInterval = 30
        public var massDeleteThreshold = 20
        public var userAgent: String? = ObsidianAPI.defaultUserAgent
        public var now: @Sendable () -> Date = { Date() }
        public init() {}
    }

    public private(set) var state: SyncState
    private let root: URL
    private let scanner: LocalScanner
    private let crypto: any SyncEncryptionProvider
    private let token: String
    private let stateURL: URL?
    private let options: Options
    private let onStatus: @Sendable (SyncStatus) -> Void
    private let onLog: @Sendable (String, String?) -> Void

    private var conn: SyncConnection?
    private var eventsTask: Task<Void, Never>?
    private var loop: Task<Void, Never>?
    private var ready = false
    private var backoff = Backoff()
    private var fileRetry: [String: (count: Int, error: String, ts: Date)] = [:]
    private var syncingPath: String?
    private var localDirty = true
    private var wake = false
    private var dirty = false
    private var allowMassDelete = false
    private var phase: SyncPhase = .connecting
    public private(set) var log: [String] = []
    public var currentPhase: SyncPhase { phase }

    public init(root: URL, state: SyncState, crypto: any SyncEncryptionProvider, token: String, stateURL: URL?,
                options: Options = Options(), onStatus: @escaping @Sendable (SyncStatus) -> Void = { _ in },
                onLog: @escaping @Sendable (String, String?) -> Void = { _, _ in }) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        self.state = state; self.crypto = crypto; self.token = token; self.stateURL = stateURL
        self.options = options; self.onStatus = onStatus; self.onLog = onLog
        scanner = LocalScanner(root: root, configDir: state.filter.configDir)
    }

    // MARK: - Control

    public func start() {
        guard loop == nil else { return }
        loop = Task { await self.run() }
    }

    public func stop() async {
        loop?.cancel(); loop = nil
        eventsTask?.cancel(); eventsTask = nil
        await conn?.disconnect(); conn = nil; ready = false
        saveIfDirty(force: true)
    }

    /// Something changed locally (or just "check now").
    public func requestSync(localChanged: Bool = true) { if localChanged { localDirty = true }; wake = true }

    public func setPaused(_ p: Bool) {
        state.paused = p; dirty = true; saveIfDirty(force: true)
        publish(p ? .paused : .connecting); if !p { requestSync() }
    }

    /// Proceed past a `needsAttention` stop (e.g. the user confirmed a mass deletion).
    public func confirmPendingAction() { allowMassDelete = true; state.paused = false; dirty = true; requestSync() }

    /// Run passes until fully synced (or blocked). Used by tests and "Sync now"; the background loop calls it too.
    @discardableResult
    public func syncNow(maxPasses: Int = 100_000) async -> SyncPhase {
        guard !state.paused else {
            if case .needsAttention = phase { return phase }   // keep the reason visible until the user acts
            publish(.paused); return .paused
        }
        var passes = 0
        while passes < maxPasses, !Task.isCancelled, !state.paused {
            passes += 1
            var result = PassResult.done
            do {
                syncingPath = nil
                result = try await pass()
                if let p = syncingPath { fileRetry[p] = nil }
            } catch {
                failed(error)
                saveIfDirty()
                return phase
            }
            saveIfDirty()
            if result == .done { break }
            if result == .waiting { break }
        }
        if case .needsAttention = phase { return phase }
        if conn == nil { return phase }
        if fileRetry.isEmpty, ready, !state.paused {
            state.lastSynced = options.now(); dirty = true; saveIfDirty()
            publish(.synced)
        }
        return phase
    }

    private func run() async {
        while !Task.isCancelled {
            wake = false
            let r = await syncNow()
            var waited = 0.0
            let limit = (r == .synced || r == .paused) ? options.periodic : min(options.periodic, max(1, backoff.next.timeIntervalSinceNow))
            while !wake && waited < limit && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000); waited += 0.25
            }
        }
    }

    // MARK: - Status & persistence

    private func publish(_ p: SyncPhase) {
        phase = p
        onStatus(SyncStatus(phase: p, lastSynced: state.lastSynced, initialMerge: state.initialMerge))
    }
    private func note(_ s: String, _ path: String? = nil) {
        log.append(path.map { "\(s): \($0)" } ?? s); if log.count > 500 { log.removeFirst(log.count - 500) }
        onLog(s, path)
    }
    private func saveIfDirty(force: Bool = false) {
        guard dirty || force, let stateURL else { return }
        try? state.save(stateURL); dirty = false
    }
    private func failed(_ error: Error) {
        let msg = "\(error)"
        note("Error \(msg)", syncingPath)
        if let p = syncingPath {
            var r = fileRetry[p] ?? (0, "", Date.distantPast)
            r.count += 1; r.error = msg
            r.ts = options.now().addingTimeInterval(min(pow(2, Double(r.count)) * 5, 300))
            fileRetry[p] = r
        }
        let text = SyncErrorText.describe(error, log: { _ in })   // raw details are in the log above
        publish(.error(syncingPath.map { "\($0): \(text)" } ?? text))
    }
    private func canSyncPath(_ p: String) -> Bool {
        let now = options.now()
        return !fileRetry.contains { $0.value.ts > now && p.hasPrefix($0.key) }
    }
    private func canSyncLocalFile(_ e: LocalEntry) -> Bool {
        guard e.synctime > 0 else { return true }
        let wait = e.size > 100 * 1024 ? 30 : (e.size > 10 * 1024 ? 20 : 10)
        return nowMs() - e.synctime > wait * 1000
    }
    private func nowMs() -> Int { Int(options.now().timeIntervalSince1970 * 1000) }

    // MARK: - Connection

    private func server() async -> SyncConnection? {
        if let c = conn, await c.isOpen { return c }
        if conn != nil { conn = nil; ready = false; backoff.fail() }
        guard backoff.isReady else { publish(.offline("Waiting to reconnect")); return nil }
        publish(.connecting)
        let c = SyncConnection(crypto: crypto, userAgent: options.userAgent)
        do {
            let url = try SyncConnection.url(forHost: state.binding.host, allowLocal: options.allowLocalHost)
            eventsTask?.cancel()
            eventsTask = Task { [weak self] in
                for await e in c.events { await self?.handle(e, from: c) }
            }
            try await c.connect(url: url, token: token, vaultID: state.binding.vaultID, version: state.version,
                                initial: state.initial, device: state.binding.deviceName)
            conn = c; backoff.success(); note("Connected")
            return c
        } catch {
            await c.disconnect()
            backoff.fail()
            let msg = "\(error)"
            note("Connect failed \(msg)")
            let text = SyncErrorText.describe(error, log: { _ in })
            if msg.contains("subscription") || msg.contains("Vault not found") || msg.contains("authFailed") {
                publish(.error(text))
            } else { publish(.offline(text)) }
            return nil
        }
    }

    private func handle(_ e: SyncEvent, from c: SyncConnection) {
        guard conn === c || conn == nil else { return }
        switch e {
        case .ready(let v):
            ready = true
            if state.initial { state.initial = false }
            if state.version < v { state.version = v }
            dirty = true; requestSync(localChanged: false)
        case .push(let f):
            state.version = f.uid
            dirty = true
            if state.initial && f.deleted { return }
            let r = RemoteEntry(f, initial: state.initial)
            if f.wasJustPushed {
                state.pending.removeAll { $0.path == f.path }
                state.remote[f.path] = r
                return
            }
            state.pending.append(r)
            requestSync(localChanged: false)
        case .disconnected(let why):
            if conn === c { conn = nil; ready = false; backoff.fail(); note("Disconnected \(why)"); publish(.offline(why)) }
        }
    }

    // MARK: - Local scan

    private func rescan() throws {
        let items = try scanner.scan()
        let liveRemote = state.remote.values.filter { !$0.deleted }.count
        if items.isEmpty && state.local.count > 0 && liveRemote > 0 {
            state.paused = true; dirty = true
            publish(.needsAttention("The vault folder looks empty; sync paused so nothing gets deleted remotely."))
            throw CancellationError()
        }
        var removed: [LocalEntry] = []
        for (p, e) in state.local where items[p] == nil { removed.append(e); state.local[p] = nil }
        for (p, it) in items {
            var e = state.local[p] ?? LocalEntry(path: p)
            let isNew = state.local[p] == nil
            e.folder = it.folder
            if it.folder { e.ctime = 0; e.mtime = 0; e.size = 0; e.hash = "" }
            else {
                if e.mtime == 0 || e.mtime != it.mtime || e.size != it.size { e.hash = "" }
                e.mtime = it.mtime; e.ctime = it.ctime; e.size = it.size
            }
            // Rename detection (Obsidian gets this from vault events): same size + same content as a vanished file.
            if isNew && !it.folder, let gone = removed.first(where: { !$0.folder && $0.size == it.size && !$0.hash.isEmpty }) {
                if let d = try? Data(contentsOf: scanner.url(p)) {
                    let h = LocalScanner.sha256(d)
                    if h == gone.hash { e.hash = h; e.previouspath = gone.path; e.synchash = gone.synchash }
                }
            }
            state.local[p] = e
        }
        if !removed.isEmpty || items.count != state.local.count { dirty = true }
    }

    private func hashLocal(_ p: String) throws -> String {
        let h = LocalScanner.sha256(try Data(contentsOf: scanner.url(p)))
        state.local[p]?.hash = h
        return h
    }

    // MARK: - One pass (port of Obsidian's `_sync`)

    enum PassResult { case didWork, waiting, done }

    private func pass() async throws -> PassResult {
        if state.paused { return .done }
        if localDirty { localDirty = false; try rescan() }
        guard let c = await server() else { return .done }
        let filter = state.filter
        var skipped = 0

        // 1. Apply pending server changes.
        var i = 0
        while i < state.pending.count {
            let y = state.pending[i]
            let k = y.path
            let E = state.remote[k]
            let x = state.local[k]
            func accept(_ quiet: Bool = false, record: Bool = true) -> PassResult {
                if !quiet { note("Accepted", k) }
                if x != nil { state.local[k]?.synctime = nowMs() }
                if record { state.remote[k] = y }
                state.pending.remove(at: i); dirty = true
                return .didWork
            }
            if !SyncPath.isValidRemoteName(k) { note("Ignoring remote file with illegal name", k); return accept(true, record: false) }
            if !filter.allows(k, folder: y.folder) { return accept(true) }
            if !canSyncPath(k) { skipped += 1; i += 1; continue }
            syncingPath = k
            if let x, !x.folder, x.hash.isEmpty { _ = try hashLocal(k) }
            let xh = state.local[k]?.hash ?? ""
            if let x, !x.folder, !y.folder, xh == y.hash { return accept(true) }
            if state.pending[(i + 1)...].contains(where: { $0.path == k }) { note("Skipped", k); return accept(true, record: false) }

            guard let x else {
                if y.deleted { return accept(true) }
                publish(.syncing("Downloading \(k)"))
                try await download(c, y)
                return accept()
            }
            if x.folder && y.folder {
                if y.deleted && !state.initialMerge { try deleteLocalFolderIfEmpty(k) }
                return accept(true)
            }
            if let E, (x.folder && E.folder) || (!x.folder && xh == E.hash) {
                // Unchanged locally since we last synced: take the server's version.
                if y.deleted {
                    if state.initialMerge { return accept(true) }
                    publish(.syncing("Deleting \(k)")); note("Deleting", k)
                    try deleteLocal(k)
                    return accept()
                }
                publish(.syncing("Downloading \(k)"))
                try await download(c, y)
                return accept()
            }
            if !x.folder && y.folder {
                let dest = SyncPath.stripExt(k) + " (Conflicted copy)" + (SyncPath.ext(SyncPath.basename(k)).isEmpty ? "" : "." + SyncPath.ext(SyncPath.basename(k)))
                note("Renaming conflicted file", k)
                try move(k, to: availablePath(dest))
                localDirty = true
                return .didWork
            }
            if y.deleted { return accept(true) }   // remote deleted but we changed it: our version will be re-uploaded

            // Both sides changed.
            if state.initialMerge && !x.folder && !y.folder {
                // First connect: keep both. Remote goes beside ours; ours stays and is uploaded afterwards.
                publish(.syncing("Keeping both versions of \(k)"))
                let copy = conflictCopyPath(k)
                guard let data = try await c.pull(uid: y.uid) else { return accept(true) }
                try writeFile(copy, data, ctime: y.ctime, mtime: y.mtime)
                note("Kept remote version as \(copy)", k)
                return accept()
            }
            if y.initial && y.mtime > x.mtime {
                publish(.syncing("Downloading \(k)"))
                try backup(k)
                try await download(c, y)
                return accept()
            }
            if !y.initial && !x.folder && !y.folder && SyncPath.ext(SyncPath.basename(k)) == "md" && y.hash != x.synchash {
                publish(.syncing("Merging \(k)"))
                note("Merging conflicted file", k)
                guard let I = try? String(contentsOf: scanner.url(k), encoding: .utf8) else { note("Merge failed", k); return accept(true) }
                if I.isEmpty { try await download(c, y); return accept() }
                var T = ""
                if let E, !E.deleted { T = String(decoding: try await c.pull(uid: E.uid) ?? Data(), as: UTF8.self) }
                let L = String(decoding: try await c.pull(uid: y.uid) ?? Data(), as: UTF8.self)
                if T == L || I == L || L.isEmpty { return accept() }
                if state.conflictStrategy == .conflict {
                    let copy = conflictCopyPath(k)
                    try writeFile(copy, Data(I.utf8), ctime: x.ctime, mtime: x.mtime)
                    try writeFile(k, Data(L.utf8), ctime: y.ctime, mtime: y.mtime)
                    note("Conflicted copy stored", k)
                    return accept()
                }
                try backup(k)
                if T.isEmpty {
                    if nowMs() - x.ctime < 180_000 || y.mtime > x.mtime {
                        try writeFile(k, Data(L.utf8), ctime: y.ctime, mtime: y.mtime)
                    }
                    return accept()
                }
                let merged = TextMerge.shared.merge(base: T, local: I, remote: L)
                try writeFile(k, Data(merged.utf8), ctime: nil, mtime: nil)
                note("Merge successful", k)
                return accept()
            }
            if !y.folder && !y.deleted && y.size > 0 && k.hasPrefix(filter.configDir + "/") {
                if SyncPath.ext(SyncPath.basename(k)) == "json",
                   let localJSON = try? String(contentsOf: scanner.url(k), encoding: .utf8),
                   let remoteData = try await c.pull(uid: y.uid),
                   let merged = TextMerge.shared.mergeJSONObjects(local: localJSON, remote: String(decoding: remoteData, as: UTF8.self)) {
                    var out = merged
                    if k == filter.configDir + "/core-plugins.json" { out = Self.patchCorePlugins(out) }
                    try writeFile(k, Data(out.utf8), ctime: nil, mtime: nil)
                    note("Merge successful", k)
                    return accept(true)
                }
                try await download(c, y)
                return accept()
            }
            note("Rejected server change", k)
            return accept(true)
        }
        syncingPath = nil
        if !ready { return .done }

        // 2. Push local deletions (deepest file first, then deepest folder). Never during the initial merge.
        if !state.initialMerge {
            var gone: [RemoteEntry] = []
            for (p, r) in state.remote where state.local[p] == nil {
                if r.deleted { state.remote[p] = nil; dirty = true; continue }
                if !SyncPath.isValidRemoteName(p) || !filter.allows(p, folder: r.folder) { continue }
                gone.append(r)
            }
            if !gone.isEmpty {
                let live = state.remote.values.filter { !$0.deleted }.count
                if !allowMassDelete && gone.count > options.massDeleteThreshold && gone.count * 4 > live {
                    state.paused = true; dirty = true
                    publish(.needsAttention("\(gone.count) of \(live) files are gone locally. Sync paused so they aren't deleted from Obsidian Sync."))
                    return .done
                }
                let f = gone.filter { !$0.folder }.max { $0.path.count < $1.path.count }
                let m = gone.filter { $0.folder }.max { $0.path.count < $1.path.count }
                if let target = f ?? m {
                    syncingPath = target.path
                    publish(.syncing("Deleting remote \(target.folder ? "folder" : "file") \(target.path)"))
                    note("Deleting remote", target.path)
                    try await c.push(path: target.path, folder: target.folder, deleted: true)
                    state.remote[target.path]?.deleted = true; dirty = true
                    return .didWork
                }
            } else { allowMassDelete = false }
        }

        // 3. Upload new folders (shallowest first) and new/changed files (smallest first).
        var g: LocalEntry?, b: LocalEntry?
        for (v, y0) in state.local {
            var y = y0
            let k = state.remote[v]
            if let k, !k.deleted, y.folder == k.folder, y.ctime == k.ctime, y.mtime == k.mtime, y.size == k.size, !y.hash.isEmpty, y.hash == k.hash { continue }
            guard filter.allows(v, folder: y.folder) else { continue }
            if !canSyncPath(v) { skipped += 1; continue }
            if !y.folder, y.size > (await c.perFileMax) { note("File too large to sync", v); continue }
            guard let k, !k.deleted else {
                if !canSyncLocalFile(y) { skipped += 1; continue }
                if y.folder { if g == nil || y.path.count < g!.path.count { g = y } }
                else if b == nil || y.size < b!.size { b = y }
                continue
            }
            if g == nil {
                if y.folder {
                    if !canSyncLocalFile(y) { skipped += 1; continue }
                    if !k.folder, g == nil || y.path.count < g!.path.count { g = y }
                    continue
                }
                if k.folder { if !canSyncLocalFile(y) { skipped += 1 }; continue }
                if y.hash.isEmpty { y.hash = try hashLocal(v) }
                if y.hash != k.hash {
                    if !canSyncLocalFile(y) { skipped += 1; continue }
                    if b == nil || y.size < b!.size { b = y }
                }
            }
        }
        if let g {
            let v = g.path
            syncingPath = v; publish(.syncing("Uploading \(v)")); note("Uploading", v)
            try await c.push(path: v, relatedPath: g.previouspath.isEmpty ? nil : g.previouspath, folder: true)
            if state.remote[v] != nil { state.remote[v]?.deleted = false }
            else { state.remote[v] = RemoteEntry(ServerFile(uid: 0, path: v, hash: "", size: 0, ctime: 0, mtime: 0, folder: true, deleted: false, device: state.binding.deviceName), initial: false) }
            state.local[v]?.previouspath = ""; state.local[v]?.synctime = nowMs(); dirty = true
            return .didWork
        }
        if let b {
            let v = b.path
            syncingPath = v; publish(.syncing("Uploading \(v)"))
            let data = try Data(contentsOf: scanner.url(v))
            let h = LocalScanner.sha256(data)
            state.local[v]?.hash = h
            if let y = state.remote[v], !y.deleted, y.hash == h { dirty = true; return .didWork }
            note("Uploading file", v)
            try await c.push(path: v, relatedPath: b.previouspath.isEmpty ? nil : b.previouspath, ctime: b.ctime, mtime: b.mtime, data: data)
            state.local[v]?.synchash = h; state.local[v]?.previouspath = ""; state.local[v]?.synctime = nowMs()
            // Provisional record until the server's echo arrives with the real uid.
            var r = state.remote[v] ?? RemoteEntry(ServerFile(uid: 0, path: v, hash: h, size: data.count, ctime: b.ctime, mtime: b.mtime, folder: false, deleted: false), initial: false)
            r.hash = h; r.deleted = false; r.folder = false; r.ctime = b.ctime; r.mtime = b.mtime; r.size = data.count
            state.remote[v] = r
            dirty = true
            note("Upload complete", v)
            return .didWork
        }
        if skipped == 0 {
            if state.initialMerge { state.initialMerge = false; dirty = true; note("Initial merge complete") }
            note("Fully synced")
            return .done
        }
        return .waiting
    }

    // MARK: - File operations (only ever inside the vault)

    private func checkedURL(_ rel: String) throws -> URL {
        guard SyncPath.isValidRemoteName(rel) else { throw CocoaError(.fileWriteInvalidFileName) }
        let u = scanner.url(rel).standardizedFileURL
        guard u.path.hasPrefix(root.path + "/") else { throw CocoaError(.fileWriteNoPermission) }
        return u
    }

    private func download(_ c: SyncConnection, _ y: RemoteEntry) async throws {
        let k = y.path
        let url = try checkedURL(k)
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: url.path, isDirectory: &isDir)
        if y.folder {
            if exists && isDir.boolValue { return }
            if exists { try move(k, to: availablePath(k + " (Conflicted copy)")) }
            note("Creating local folder", k)
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
            var e = state.local[k] ?? LocalEntry(path: k); e.folder = true; state.local[k] = e
            return
        }
        if exists && isDir.boolValue {
            if (try? fm.contentsOfDirectory(atPath: url.path))?.isEmpty == true { try fm.removeItem(at: url) }
            else { note("Renaming conflicted file", k); try move(k, to: availablePath(k + " (Conflicted copy)")); return }
        }
        note("Downloading file", k)
        let before = try? fm.attributesOfItem(atPath: url.path)
        guard var data = try await c.pull(uid: y.uid) else { throw SyncEngineError.noData(k) }
        if k == state.filter.configDir + "/core-plugins.json" {
            data = Data(Self.patchCorePlugins(String(decoding: data, as: UTF8.self)).utf8)
        }
        let after = try? fm.attributesOfItem(atPath: url.path)
        if (before?[.modificationDate] as? Date) != (after?[.modificationDate] as? Date) || (before?[.size] as? Int) != (after?[.size] as? Int) {
            throw SyncEngineError.changedLocally(k)
        }
        var ctime: Int? = y.ctime
        if exists, let lc = state.local[k]?.ctime, lc != 0, y.ctime >= lc { ctime = nil }
        try writeFile(k, data, ctime: ctime, mtime: y.mtime)
        let h = LocalScanner.sha256(data)
        state.local[k]?.hash = h; state.local[k]?.synchash = h
    }

    /// Atomic write; sets times (ms) and refreshes the local entry so our own write isn't seen as a local edit.
    private func writeFile(_ k: String, _ data: Data, ctime: Int?, mtime: Int?) throws {
        let url = try checkedURL(k)
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        var attrs: [FileAttributeKey: Any] = [:]
        if let mtime, mtime > 0 { attrs[.modificationDate] = Date(timeIntervalSince1970: Double(mtime) / 1000) }
        if let ctime, ctime > 0 { attrs[.creationDate] = Date(timeIntervalSince1970: Double(ctime) / 1000) }
        if !attrs.isEmpty { try? fm.setAttributes(attrs, ofItemAtPath: url.path) }
        let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey, .fileSizeKey])
        var e = state.local[k] ?? LocalEntry(path: k)
        e.folder = false
        e.mtime = LocalScanner.ms(v?.contentModificationDate); e.ctime = LocalScanner.ms(v?.creationDate); e.size = v?.fileSize ?? data.count
        e.hash = LocalScanner.sha256(data)
        state.local[k] = e
        // Parent folders we just created exist now too.
        var parent = SyncPath.parent(k)
        while !parent.isEmpty, state.local[parent] == nil {
            var f = LocalEntry(path: parent); f.folder = true; state.local[parent] = f
            parent = SyncPath.parent(parent)
        }
        dirty = true
    }

    private func deleteLocal(_ k: String) throws {
        let url = try checkedURL(k)
        if FileManager.default.fileExists(atPath: url.path) {
            switch options.deleteMode {
            case .trash:
                #if os(macOS)
                do { try FileManager.default.trashItem(at: url, resultingItemURL: nil); break } catch {}
                #endif
                // No user-visible Trash (iOS, or a volume without one): keep the file among the backups instead.
                if let dir = options.backupDir {
                    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HHmmss"
                    let dest = dir.appendingPathComponent("Deleted").appendingPathComponent(f.string(from: options.now())).appendingPathComponent(k)
                    try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
                    try FileManager.default.moveItem(at: url, to: dest)
                } else {
                    try FileManager.default.removeItem(at: url)
                }
            case .remove: try FileManager.default.removeItem(at: url)
            }
        }
        state.local[k] = nil
    }

    private func deleteLocalFolderIfEmpty(_ k: String) throws {
        let url = try checkedURL(k)
        guard let kids = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { state.local[k] = nil; return }
        if kids.filter({ $0 != ".DS_Store" }).isEmpty { try deleteLocal(k) }
    }

    private func move(_ from: String, to: String) throws {
        let a = try checkedURL(from), b = try checkedURL(to)
        try FileManager.default.createDirectory(at: b.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: a, to: b)
        if let e = state.local[from] { var n = e; n.path = to; state.local[to] = n; state.local[from] = nil }
        dirty = true
    }

    private func backup(_ k: String) throws {
        guard let dir = options.backupDir, let data = try? Data(contentsOf: scanner.url(k)) else { return }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HHmmss"
        let dest = dir.appendingPathComponent(f.string(from: options.now())).appendingPathComponent(k)
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: dest, options: .atomic)
    }

    /// "Note (Conflicted copy <device> <yyyyMMddHHmm>).md", made unique like Obsidian's getAvailablePath.
    func conflictCopyPath(_ k: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "sv_SE"); f.dateFormat = "yyyyMMddHHmm"
        let dev = SyncPath.sanitize(state.binding.deviceName.isEmpty ? Self.defaultDeviceName : state.binding.deviceName)
        let ext = SyncPath.ext(SyncPath.basename(k))
        return availablePath(SyncPath.stripExt(k) + " (Conflicted copy \(dev) \(f.string(from: options.now())))" + (ext.isEmpty ? "" : "." + ext))
    }

    /// "<computer name>" on the Mac; on iOS the binding always carries a device name, so this is a fallback.
    public static var defaultDeviceName: String {
        #if os(macOS)
        return Host.current().localizedName ?? "Onyx"
        #else
        return "Onyx"
        #endif
    }

    func availablePath(_ p: String) -> String {
        let ext = SyncPath.ext(SyncPath.basename(p))
        let base = SyncPath.stripExt(p)
        var candidate = p, n = 1
        let fm = FileManager.default
        while fm.fileExists(atPath: scanner.url(candidate).path) || state.local[candidate] != nil {
            candidate = base + " \(n)" + (ext.isEmpty ? "" : "." + ext); n += 1
        }
        return candidate
    }

    /// Obsidian keeps its Sync core plugin enabled in every synced core-plugins.json; so do we, for its sake.
    static func patchCorePlugins(_ s: String) -> String { TextMerge.shared.patchCorePlugins(s) }
}

public enum SyncEngineError: Error, CustomStringConvertible {
    case noData(String), changedLocally(String)
    public var description: String {
        switch self {
        case .noData(let p): "Failed to download \(p), no data."
        case .changedLocally(let p): "Download of \(p) cancelled because it changed locally. Will try again soon."
        }
    }
}
