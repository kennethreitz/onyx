import CryptoKit
import Foundation
import Observation

/// Where a sync-log event came from.
public enum SyncLogSource: String, Equatable, Sendable, CaseIterable {
    case git
    case obsidian
    public var label: String {
        switch self {
        case .git: return "Git"
        case .obsidian: return "Obsidian Sync"
        }
    }
}

/// The kind of activity recorded in the sync log.
public enum SyncLogEvent: String, Equatable, Sendable, CaseIterable {
    case pull, push, commit, downloaded, uploaded, conflict, error, connected, disconnected
    public var label: String {
        switch self {
        case .pull: return "Pull"
        case .push: return "Push"
        case .commit: return "Commit"
        case .downloaded: return "Downloaded"
        case .uploaded: return "Uploaded"
        case .conflict: return "Conflict"
        case .error: return "Error"
        case .connected: return "Connected"
        case .disconnected: return "Disconnected"
        }
    }
    public var isAlert: Bool { self == .error || self == .conflict }
}

public struct SyncLogEntry: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var source: SyncLogSource
    public var event: SyncLogEvent
    public var detail: String
    public init(id: UUID = UUID(), date: Date, source: SyncLogSource, event: SyncLogEvent, detail: String) {
        self.id = id; self.date = date; self.source = source; self.event = event
        self.detail = detail.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
    }
    public var isAlert: Bool { event.isAlert }
}

/// In-memory ring buffer of recent sync activity, also persisted as a plain-text log
/// under Application Support (one file per vault) so it survives relaunch.
@Observable
@MainActor
public final class SyncLogStore {
    nonisolated public static let defaultCapacity = 500
    public let fileURL: URL
    public let capacity: Int
    public private(set) var entries: [SyncLogEntry] = []
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let fileManager: FileManager
    nonisolated private static func stamp() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }

    nonisolated public static func supportDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Onyx/Logs", isDirectory: true)
    }
    /// Stable short id for a vault folder, matching the scheme used for Sync state files.
    nonisolated public static func vaultID(for root: URL) -> String {
        let path = root.standardizedFileURL.resolvingSymlinksInPath().path
        return Array(SHA256.hash(data: Data(path.utf8))).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
    nonisolated public static func fileURL(forVault root: URL, fileManager: FileManager = .default) -> URL {
        supportDirectory(fileManager: fileManager).appendingPathComponent(vaultID(for: root) + ".log")
    }

    public convenience init(vaultRoot: URL, capacity: Int = SyncLogStore.defaultCapacity,
                            fileManager: FileManager = .default, now: @escaping @Sendable () -> Date = { Date() }) {
        self.init(fileURL: SyncLogStore.fileURL(forVault: vaultRoot, fileManager: fileManager),
                  capacity: capacity, fileManager: fileManager, now: now)
    }
    public init(fileURL: URL, capacity: Int = SyncLogStore.defaultCapacity,
                fileManager: FileManager = .default, now: @escaping @Sendable () -> Date = { Date() }) {
        self.fileURL = fileURL; self.capacity = max(1, capacity)
        self.fileManager = fileManager; self.now = now
        entries = Self.load(from: fileURL, capacity: self.capacity, fileManager: fileManager)
    }

    public func append(source: SyncLogSource, event: SyncLogEvent, detail: String, date: Date? = nil) {
        let e = SyncLogEntry(date: date ?? now(), source: source, event: event, detail: detail)
        entries.append(e)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
            rewrite()
        } else {
            appendLine(e)
        }
    }

    /// Plain-text form of the current buffer, for the clipboard and the file itself.
    public func renderedText() -> String {
        entries.map(Self.line).joined(separator: "\n") + (entries.isEmpty ? "" : "\n")
    }

    /// A handful of sample rows so screenshot / `--show synclog` runs have something to show.
    public func seedPreviewIfEmpty() {
        guard entries.isEmpty else { return }
        let t = now()
        let samples: [(TimeInterval, SyncLogSource, SyncLogEvent, String)] = [
            (-18 * 60, .git, .commit, "Edit Home"),
            (-17 * 60, .git, .push, "Pushed 1 commit"),
            (-16 * 60, .obsidian, .connected, ""),
            (-12 * 60, .obsidian, .downloaded, "Writing/Essays/On Style.md"),
            (-9 * 60, .git, .pull, "Received 2 commits"),
            (-6 * 60, .obsidian, .uploaded, "Daily/2026-11-20.md"),
            (-3 * 60, .obsidian, .conflict, "Kept both versions of Knowledge/Mercury.md"),
            (-1 * 60, .git, .error, "Couldn’t reach the remote; retrying"),
        ]
        for (ago, source, event, detail) in samples {
            append(source: source, event: event, detail: detail, date: t.addingTimeInterval(ago))
        }
    }

    /// Classify a `SyncEngine.note` message; returns nil for routine chatter we don't keep.
    nonisolated public static func fromObsidian(message: String, path: String?) -> (event: SyncLogEvent, detail: String)? {
        func withPath(_ prefix: String) -> String {
            if let path, !path.isEmpty { return prefix.isEmpty ? path : "\(prefix): \(path)" }
            return prefix
        }
        if message == "Connected" { return (.connected, path ?? "") }
        if message.hasPrefix("Connect failed") {
            let rest = message.dropFirst("Connect failed".count).trimmingCharacters(in: .whitespaces)
            return (.error, rest.isEmpty ? "Connect failed" : rest)
        }
        if message.hasPrefix("Disconnected") {
            let rest = message.dropFirst("Disconnected".count).trimmingCharacters(in: .whitespaces)
            return (.disconnected, rest)
        }
        if message == "Downloading file" { return (.downloaded, path ?? "") }
        if message == "Upload complete" { return (.uploaded, path ?? "") }
        if message == "Renaming conflicted file"
            || message.hasPrefix("Kept remote version")
            || message == "Merging conflicted file"
            || message == "Conflicted copy stored" {
            return (.conflict, withPath(message))
        }
        if message == "Merge failed" { return (.error, withPath("Merge failed")) }
        if message.hasPrefix("Error ") {
            let rest = String(message.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            return (.error, withPath(rest))
        }
        if message == "Deleting" { return (.pull, withPath("Deleted")) }
        if message == "Deleting remote" { return (.push, withPath("Deleted")) }
        if message == "File too large to sync" { return (.error, withPath("Too large to sync")) }
        if message == "Rejected server change" { return (.conflict, withPath(message)) }
        return nil
    }

    nonisolated public static func parseLine(_ raw: String) -> SyncLogEntry? {
        let parts = raw.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3, let date = stamp().date(from: parts[0]),
              let source = SyncLogSource(rawValue: parts[1]),
              let event = SyncLogEvent(rawValue: parts[2]) else { return nil }
        return SyncLogEntry(date: date, source: source, event: event, detail: parts.count > 3 ? parts[3] : "")
    }
    nonisolated public static func line(_ e: SyncLogEntry) -> String {
        "\(stamp().string(from: e.date))\t\(e.source.rawValue)\t\(e.event.rawValue)\t\(e.detail)"
    }

    private func appendLine(_ e: SyncLogEntry) {
        let dir = fileURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = Data((Self.line(e) + "\n").utf8)
        if fileManager.fileExists(atPath: fileURL.path) {
            if let h = try? FileHandle(forWritingTo: fileURL) {
                defer { try? h.close() }
                _ = try? h.seekToEnd(); _ = try? h.write(contentsOf: data)
            }
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
    private func rewrite() {
        let dir = fileURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        try? renderedText().write(to: fileURL, atomically: true, encoding: .utf8)
    }
    private static func load(from url: URL, capacity: Int, fileManager: FileManager) -> [SyncLogEntry] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let parsed = text.split(whereSeparator: \.isNewline).compactMap { parseLine(String($0)) }
        return parsed.count > capacity ? Array(parsed.suffix(capacity)) : parsed
    }
}
