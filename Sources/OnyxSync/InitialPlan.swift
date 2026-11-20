import Foundation

/// What a first connect would do, computed read-only: scans the local folder, opens a websocket with `version: 0`
/// to receive the remote file list, and disconnects. Nothing is downloaded, uploaded, or written.
public struct InitialPlan: Sendable, Equatable {
    public var localFiles = 0
    public var remoteFiles = 0
    public var identical = 0
    public var toDownload: [String] = []
    public var toUpload: [String] = []
    /// Present on both sides with different content: both are kept (remote as a "Conflicted copy").
    public var keepBoth: [String] = []
    /// Deleted on the server: ignored during the initial merge (local copies stay).
    public var remoteDeletedIgnored = 0
    public var notSynced = 0

    public var isTrivial: Bool { keepBoth.isEmpty && (localFiles == 0 || remoteFiles == 0) }

    public var summary: String {
        var lines = ["\(localFiles) local · \(remoteFiles) remote files", "\(identical) already identical"]
        if !toDownload.isEmpty { lines.append("\(toDownload.count) to download") }
        if !toUpload.isEmpty { lines.append("\(toUpload.count) to upload") }
        if !keepBoth.isEmpty { lines.append("\(keepBoth.count) differ: both versions kept (remote saved as “Conflicted copy”)") }
        if remoteDeletedIgnored > 0 { lines.append("\(remoteDeletedIgnored) deleted remotely: ignored, nothing deleted here") }
        lines.append("Nothing is deleted on either side during this first sync.")
        return lines.joined(separator: "\n")
    }

    public static func compute(root: URL, filter: SyncFilter, crypto: any SyncEncryptionProvider, binding: SyncBinding,
                               token: String, allowLocalHost: Bool = false, userAgent: String? = ObsidianAPI.defaultUserAgent) async throws -> InitialPlan {
        let scanner = LocalScanner(root: root, configDir: filter.configDir)
        let local = try scanner.scan()
        let c = SyncConnection(crypto: crypto, userAgent: userAgent)
        var it = c.events.makeAsyncIterator()
        try await c.connect(url: SyncConnection.url(forHost: binding.host, allowLocal: allowLocalHost), token: token,
                            vaultID: binding.vaultID, version: 0, initial: true, device: binding.deviceName)
        var remote: [String: ServerFile] = [:]
        loop: while let e = await it.next() {
            switch e {
            case .push(let f): remote[f.path] = f
            case .ready: break loop
            case .disconnected(let why): throw SyncConnectionError.server(why)
            }
        }
        await c.disconnect()

        var plan = InitialPlan()
        for (p, f) in remote where !f.folder {
            guard filter.allows(p, folder: false) else { continue }
            if f.deleted { if local[p] != nil { plan.remoteDeletedIgnored += 1 }; continue }
            plan.remoteFiles += 1
            if local[p] == nil || local[p]!.folder { plan.toDownload.append(p) }
        }
        for (p, it) in local where !it.folder {
            guard filter.allows(p, folder: false) else { plan.notSynced += 1; continue }
            plan.localFiles += 1
            guard let r = remote[p], !r.deleted, !r.folder else { plan.toUpload.append(p); continue }
            let h = LocalScanner.sha256((try? Data(contentsOf: scanner.url(p))) ?? Data())
            if h == r.hash { plan.identical += 1 } else { plan.keepBoth.append(p) }
        }
        plan.toDownload.sort(); plan.toUpload.sort(); plan.keepBoth.sort()
        return plan
    }
}
