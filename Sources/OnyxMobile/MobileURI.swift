import Foundation
import UIKit
import OnyxCore
import OnyxSync

extension MobileVault {
    /// An `onyx://` (or in-note `obsidian://`) link. Queued until a vault is open.
    func handleURL(_ url: URL) {
        guard let action = OnyxURI.parse(url), action != .clip else { return }
        if snapshot == nil {
            pendingURI = url
            if root == nil { restore() }
            if snapshot == nil { tryOpenVault(for: action) }
            if snapshot == nil { return }
            // open() / openManaged() already ran the action via applyPendingURI.
            guard pendingURI != nil else { return }
            pendingURI = nil
        }
        perform(action)
    }

    func applyPendingURI() {
        guard let url = pendingURI else { return }
        pendingURI = nil
        handleURL(url)
    }

    private func tryOpenVault(for action: OnyxURI) {
        let current = root.map { KnownVault(name: managed?.name, url: $0, id: managed?.id) }
        let known = knownVaults(current: current)
        guard let target = OnyxURIHandlerVault.vault(for: action, known: known, current: current) else { return }
        let lib = SyncVaultLibrary.default
        if let managed = lib.vault(at: target.url) ?? target.id.flatMap({ lib.vault(remoteID: $0) }) {
            openManaged(managed)
            return
        }
        // A previously bookmarked folder we can still reach, or a path we already have access to.
        if FileManager.default.fileExists(atPath: target.url.path) {
            open(target.url)
        }
    }

    private func knownVaults(current: KnownVault?) -> [KnownVault] {
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
        let lib = SyncVaultLibrary.default
        for v in lib.load() { add(KnownVault(name: v.name, url: lib.url(for: v), id: v.id)) }
        return out
    }

    private func perform(_ action: OnyxURI) {
        switch action {
        case .clip:
            break
        case .open(let o):
            open(o)
        case .search(let s):
            query = s.query ?? ""
            libraryTab = .find
        case .new(let n):
            applyNew(n, daily: false)
        case .daily(let n):
            applyNew(n, daily: true)
        }
    }

    private func open(_ o: OnyxURI.Open) {
        var file = o.file
        var heading = o.heading
        var block = o.block
        if let p = o.path {
            let current = root.map { KnownVault(name: managed?.name, url: $0, id: managed?.id) }
            guard let hit = OnyxURIVaults.containing(p, among: knownVaults(current: current)) else {
                error = "Couldn’t find that file"
                return
            }
            let parts = OnyxURI.splitAnchor(hit.1)
            file = parts.file.isEmpty ? nil : parts.file
            if heading == nil { heading = parts.heading }
            if block == nil { block = parts.block }
        }
        guard let file, !file.isEmpty else { return }
        guard let rel = OnyxURI.normalizeRelative(file) else {
            error = "That path is outside the vault"
            return
        }
        if rel.isEmpty { return }
        guard let path = resolveFile(rel) else {
            error = "Couldn’t find \(rel)"
            return
        }
        openResolved(path, heading: heading, block: block)
    }

    private func applyNew(_ n: OnyxURI.New, daily: Bool) {
        guard let root, let snap = snapshot else { return }
        var flags = n
        if flags.clipboard, let clip = UIPasteboard.general.string, flags.content == nil {
            flags.content = clip
        }
        let incoming = flags.content ?? ""

        var rel: String?
        if let p = n.path {
            let current = KnownVault(name: managed?.name, url: root, id: managed?.id)
            guard let hit = OnyxURIVaults.containing(p, among: knownVaults(current: current)) else {
                error = "Couldn’t find that file"
                return
            }
            let parts = OnyxURI.splitAnchor(hit.1)
            rel = parts.file
            if flags.fileHeading == nil { flags.fileHeading = parts.heading }
            if flags.fileBlock == nil { flags.fileBlock = parts.block }
        }
        if rel == nil, let f = n.file {
            guard let norm = OnyxURI.normalizeRelative(f) else {
                error = "That path is outside the vault"
                return
            }
            rel = norm.isEmpty ? nil : OnyxURI.markdownPath(for: norm)
        }
        if rel == nil, let name = n.name, !daily {
            guard let norm = OnyxURI.normalizeRelative(name) else {
                error = "That path is outside the vault"
                return
            }
            rel = OnyxURI.markdownPath(for: norm)
        }
        if daily, rel == nil {
            rel = dailyPath
        }
        guard var path = rel, !path.isEmpty else {
            error = "Couldn’t decide where to put that note"
            return
        }
        if let resolved = resolveFile(path) { path = resolved }
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
            let template = DailyNotes.template(for: Date())
            if flags.append || flags.prepend {
                existing = template
            } else if incoming.isEmpty {
                incomingOrTemplate = template
            }
        }

        let next = OnyxURIContent.apply(existing: existing, incoming: incomingOrTemplate, flags: flags)
        if existing != next {
            let created = !onDisk && existing == nil
            var ok = writeNote(next, to: path, create: created)
            if !ok, created { ok = writeNote(next, to: path, create: false) }
            if !ok, snapshot?.notes[path] == nil, !FileManager.default.fileExists(atPath: url.path) {
                error = "Couldn’t save that note"
                return
            }
        }
        if !flags.silent {
            openResolved(path, heading: flags.heading ?? flags.fileHeading, block: flags.fileBlock)
        }
    }

    private func openResolved(_ path: String, heading: String?, block: String?) {
        if let note = snapshot?.notes[path] {
            if let block, !block.isEmpty,
               let line = BookmarkSubpath.line(subpath: "#^" + block, text: note.content, headings: note.summary.headings) {
                openNote(path, line: line)
                return
            }
            if let heading, !heading.isEmpty,
               let line = BookmarkSubpath.line(subpath: "#" + heading, text: note.content, headings: note.summary.headings) {
                openNote(path, line: line)
                return
            }
        }
        openNote(path)
    }

    private func resolveFile(_ file: String) -> String? {
        guard let snap = snapshot else { return nil }
        if snap.notes[file] != nil || snap.attachments[file] != nil
            || snap.canvases[file] != nil || snap.bases[file] != nil { return file }
        let md = OnyxURI.markdownPath(for: file)
        if md != file, snap.notes[md] != nil { return md }
        if let p = snap.resolve(file) { return p }
        if md != file, let p = snap.resolve(md) { return p }
        return nil
    }
}

/// Vault resolution for the iOS handler; same rules as the Mac `OnyxURIHandler`.
private enum OnyxURIHandlerVault {
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
}
