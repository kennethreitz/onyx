import Foundation
import CoreServices
import OnyxCore

/// FSEvents on the vault root, file-level, coalesced. Works for Obsidian
/// Sync, git, iCloud and other bots writing into the same folder.
final class FileWatcher {
    private var stream: FSEventStreamRef?
    private let root: URL
    private let handler: ([String]) -> Void

    init(root: URL, handler: @escaping ([String]) -> Void) {
        self.root = root.standardizedFileURL
        self.handler = handler
        start()
    }
    deinit { stop() }

    private func start() {
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let cb: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let me = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            let arr = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            me.deliver(Array(arr.prefix(count)))
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes)
        stream = FSEventStreamCreate(nil, cb, &ctx, [root.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.15, flags)
        if let stream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue(label: "onyx.fsEvents"))
            FSEventStreamStart(stream)
        }
    }

    func stop() {
        if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
        stream = nil
    }

    private func deliver(_ paths: [String]) {
        // FSEvents reports /private/tmp for /tmp; normalise both forms.
        let roots = [root.path, root.resolvingSymlinksInPath().path, "/private" + root.path]
        var rels = Set<String>()
        for p in paths {
            guard let r = roots.first(where: { p == $0 || p.hasPrefix($0 + "/") }) else { continue }
            var rel = String(p.dropFirst(r.count))
            if rel.hasPrefix("/") { rel.removeFirst() }
            if rel.isEmpty { continue }
            // Hidden paths are skipped, except the Obsidian config files Onyx reads (Settings ▸ Files & Links, Daily Notes).
            if rel.hasPrefix(".obsidian/"), !rel.dropFirst(10).contains("/"), ObsidianConfig.watchedFiles.contains(String(rel.dropFirst(10))) {
                rels.insert(rel); continue
            }
            if rel.split(separator: "/").contains(where: { $0.hasPrefix(".") }) { continue }
            rels.insert(rel)
        }
        if !rels.isEmpty { handler(Array(rels)) }
    }
}
