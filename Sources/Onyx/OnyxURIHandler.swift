import AppKit
import OnyxCore

/// Handles `onyx://` (and in-note `obsidian://`) links in the existing window.
/// Parsing lives in OnyxCore; this resolves vaults, waits for a cold launch, and
/// runs the action once the snapshot is ready. `onyx://clip` is forwarded to the clipper.
@MainActor final class OnyxURIHandler {
    static let shared = OnyxURIHandler()
    weak var ws: Workspace?
    private var pending: URL?
    private var waits = 0
    static let recentVaultsKey = "onyx.recentVaults"

    /// An `onyx://` URL from the system (`open`, Shortcuts, a bookmark) or a click inside a note.
    func receive(_ url: URL) {
        guard let action = OnyxURI.parse(url) else { return }
        if case .clip = action {
            WebClipper.shared.receive(url)
            return
        }
        pending = url
        MainWindow.reveal()
        apply()
    }

    /// Called from `OnyxApp.boot()`. If a pending URL names a vault we can open, do that
    /// instead of the last-session default and return true so boot does not open twice.
    @discardableResult
    func consumeAtBoot(defaultVault: URL?) -> Bool {
        guard let url = pending, let action = OnyxURI.parse(url), action != .clip else { return false }
        let current = defaultVault.map { KnownVault(url: $0) }
        let known = Self.knownVaults(current: current)
        guard let target = Self.vault(for: action, known: known, current: current) else { return false }
        openVault(target.url) { self.apply() }
        return true
    }

    func apply() {
        guard let url = pending, let action = OnyxURI.parse(url), action != .clip else { return }
        guard let ws else {
            scheduleRetry()
            return
        }
        let current = ws.root.map { KnownVault(url: $0) }
        let known = Self.knownVaults(current: current)
        if let target = Self.vault(for: action, known: known, current: current) {
            waits = 0
            let same = ws.root.map { $0.standardizedFileURL == target.url.standardizedFileURL } ?? false
            if !same || ws.snapshot == nil || ws.isIndexing {
                openVault(target.url) { [weak self] in
                    guard let self else { return }
                    self.pending = nil
                    self.perform(action, on: ws)
                }
                return
            }
            pending = nil
            perform(action, on: ws)
            return
        }
        if ws.root == nil || ws.snapshot == nil {
            scheduleRetry()
            return
        }
        pending = nil
        ws.toast = "Couldn’t find that vault"
    }

    private func scheduleRetry() {
        waits += 1
        guard waits < 60 else { waits = 0; return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.apply() }
    }

    private func openVault(_ url: URL, then: @escaping () -> Void) {
        guard let ws else { return }
        let same = ws.root?.standardizedFileURL == url.standardizedFileURL
        if same, ws.snapshot != nil, !ws.isIndexing { then(); return }
        if !same || ws.root == nil {
            OnyxApp.remember(url)
            ws.open(vault: url, initialNote: nil, restoreSplits: false)
        }
        waitForIndex(attempt: 0, then: then)
    }

    private func waitForIndex(attempt: Int, then: @escaping () -> Void) {
        guard let ws else { return }
        if !ws.isIndexing, ws.snapshot != nil { then(); return }
        guard attempt < 80 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.waitForIndex(attempt: attempt + 1, then: then) }
    }

    // MARK: Actions

    private func perform(_ action: OnyxURI, on ws: Workspace) {
        switch action {
        case .clip:
            break
        case .open(let o):
            open(o, on: ws)
        case .search(let s):
            ws.searchVault(s.query)
        case .new(let n):
            applyNew(n, daily: false, on: ws)
        case .daily(let n):
            applyNew(n, daily: true, on: ws)
        }
    }

    private func open(_ o: OnyxURI.Open, on ws: Workspace) {
        var file = o.file
        var heading = o.heading
        var block = o.block
        if let p = o.path {
            let known = Self.knownVaults(current: ws.root.map { KnownVault(url: $0) })
            guard let hit = OnyxURIVaults.containing(p, among: known) else {
                ws.toast = "Couldn’t find that file"
                return
            }
            let parts = OnyxURI.splitAnchor(hit.1)
            file = parts.file.isEmpty ? nil : parts.file
            if heading == nil { heading = parts.heading }
            if block == nil { block = parts.block }
        }
        guard let file, !file.isEmpty else { return }
        guard let rel = OnyxURI.normalizeRelative(file) else {
            ws.toast = "That path is outside the vault"
            return
        }
        if rel.isEmpty { return }
        guard let path = Self.resolveFile(rel, in: ws) else {
            ws.toast = "Couldn’t find \(rel)"
            return
        }
        openFile(path, heading: heading, block: block, on: ws)
    }

    private func applyNew(_ n: OnyxURI.New, daily: Bool, on ws: Workspace) {
        guard let root = ws.root, let snap = ws.snapshot else { return }
        var flags = n
        if flags.clipboard, let clip = NSPasteboard.general.string(forType: .string), flags.content == nil {
            flags.content = clip
        }
        let incoming = flags.content ?? ""

        var rel: String?
        if let p = n.path {
            let known = Self.knownVaults(current: KnownVault(url: root))
            guard let hit = OnyxURIVaults.containing(p, among: known) else {
                ws.toast = "Couldn’t find that file"
                return
            }
            let parts = OnyxURI.splitAnchor(hit.1)
            rel = parts.file
            if flags.fileHeading == nil { flags.fileHeading = parts.heading }
            if flags.fileBlock == nil { flags.fileBlock = parts.block }
        }
        if rel == nil, let f = n.file {
            guard let norm = OnyxURI.normalizeRelative(f) else {
                ws.toast = "That path is outside the vault"
                return
            }
            rel = norm.isEmpty ? nil : OnyxURI.markdownPath(for: norm)
        }
        if rel == nil, let name = n.name, !daily {
            let folder = ws.newNoteFolder(contextual: "")
            let raw = folder.isEmpty ? name : folder + "/" + name
            guard let norm = OnyxURI.normalizeRelative(raw) else {
                ws.toast = "That path is outside the vault"
                return
            }
            rel = OnyxURI.markdownPath(for: norm)
        }
        if daily, rel == nil {
            rel = DailyNotes.path(for: Date(), settings: ws.daily)
        }
        guard var path = rel, !path.isEmpty else {
            ws.toast = "Couldn’t decide where to put that note"
            return
        }
        if let resolved = Self.resolveFile(path, in: ws) { path = resolved }
        else { path = OnyxURI.markdownPath(for: path) }

        let url = root.appendingPathComponent(path)
        let onDisk = snap.notes[path] != nil || FileManager.default.fileExists(atPath: url.path)
        var existing: String? = nil
        var incomingOrTemplate = incoming
        if onDisk {
            existing = snap.notes[path]?.content
                ?? (try? String(contentsOf: url, encoding: .utf8))
                ?? ""
        } else if daily {
            let template = ws.dailyNoteText(for: Date(), path: path)
            if flags.append || flags.prepend {
                existing = template
            } else if incoming.isEmpty {
                incomingOrTemplate = template
            }
        }

        let next = OnyxURIContent.apply(existing: existing, incoming: incomingOrTemplate, flags: flags)
        let needsWrite = existing != next
        if needsWrite {
            if ws.currentPath == path { ws.flushSave() }
            var ok = ws.write(next, to: path, create: !onDisk && existing == nil)
            if !ok, !onDisk {
                // write() refuses create when the file appeared; try an update.
                ok = ws.write(next, to: path, create: false)
            }
            if !ok, ws.snapshot?.notes[path] == nil, !FileManager.default.fileExists(atPath: url.path) {
                ws.toast = "Couldn’t save that note"
                return
            }
        }

        if !flags.silent {
            openFile(path, heading: flags.heading ?? flags.fileHeading, block: flags.fileBlock, on: ws)
            if daily, ws.mode != .edit, incoming.isEmpty { ws.mode = .edit }
        }
    }

    private func openFile(_ path: String, heading: String?, block: String?, on ws: Workspace) {
        if let block, !block.isEmpty, let note = ws.snapshot?.notes[path],
           let line = BookmarkSubpath.line(subpath: "#^" + block, text: note.content, headings: note.summary.headings) {
            ws.openNote(path, line: line + 1)
            return
        }
        if let heading, heading.hasPrefix("^"), let note = ws.snapshot?.notes[path],
           let line = BookmarkSubpath.line(subpath: "#" + heading, text: note.content, headings: note.summary.headings) {
            ws.openNote(path, line: line + 1)
            return
        }
        ws.openNote(path, heading: heading)
    }

    // MARK: Resolution

    static func resolveFile(_ file: String, in ws: Workspace) -> String? {
        guard let snap = ws.snapshot else { return nil }
        if snap.notes[file] != nil || snap.attachments[file] != nil
            || snap.canvases[file] != nil || snap.bases[file] != nil { return file }
        let md = OnyxURI.markdownPath(for: file)
        if md != file, snap.notes[md] != nil { return md }
        if let p = snap.resolve(file) { return p }
        if md != file, let p = snap.resolve(md) { return p }
        return nil
    }

    static func vault(for action: OnyxURI, known: [KnownVault], current: KnownVault?) -> KnownVault? {
        switch action {
        case .clip:
            return current
        case .open(let o):
            if let p = o.path { return OnyxURIVaults.containing(p, among: known)?.0 }
            return OnyxURIVaults.resolve(o.vault, among: known, current: current)
        case .search(let s):
            return OnyxURIVaults.resolve(s.vault, among: known, current: current)
        case .new(let n), .daily(let n):
            if let p = n.path { return OnyxURIVaults.containing(p, among: known)?.0 }
            return OnyxURIVaults.resolve(n.vault, among: known, current: current)
        }
    }

    static func knownVaults(current: KnownVault?) -> [KnownVault] {
        var out: [KnownVault] = []
        var seen = Set<String>()
        func add(_ v: KnownVault) {
            let p = v.url.standardizedFileURL.path
            guard !seen.contains(p.lowercased()) else { return }
            guard FileManager.default.fileExists(atPath: p) else { return }
            seen.insert(p.lowercased())
            out.append(v)
        }
        if let current { add(current) }
        for p in UserDefaults.standard.stringArray(forKey: recentVaultsKey) ?? [] {
            add(KnownVault(url: URL(fileURLWithPath: p)))
        }
        if let p = UserDefaults.standard.string(forKey: "onyx.vault") {
            add(KnownVault(url: URL(fileURLWithPath: p)))
        }
        let lib = SyncVaultLibrary.default
        for v in lib.load() {
            add(KnownVault(name: v.name, url: lib.url(for: v), id: v.id))
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        if let data = try? Data(contentsOf: support.appendingPathComponent("obsidian/obsidian.json")) {
            for v in OnyxURIVaults.parseObsidianAppJSON(data) { add(v) }
        }
        return out
    }
}
