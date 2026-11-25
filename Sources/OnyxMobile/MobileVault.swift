import Foundation
import OnyxCore

/// The open vault on iOS: a security-scoped folder bookmark, a `VaultSnapshot`, and search.
@MainActor
final class MobileVault: ObservableObject {
    static let bookmarkKey = "onyx.ios.vaultBookmark"

    @Published var root: URL?
    @Published var snapshot: VaultSnapshot?
    @Published var selectedPath: String?
    @Published var query = ""
    @Published var error: String?
    @Published var isScanning = false

    private var isAccessing = false

    var notes: [NoteRecord] {
        guard let snap = snapshot else { return [] }
        return snap.sortedNotePaths.compactMap { snap.notes[$0] }
    }

    var visibleNotes: [NoteRecord] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, let snap = snapshot else { return notes }
        return snap.search(q).compactMap { snap.notes[$0.path] }
    }

    var selectedNote: NoteRecord? {
        guard let p = selectedPath else { return nil }
        return snapshot?.notes[p]
    }

    var dailyPath: String? {
        guard let root else { return nil }
        let settings = Self.dailySettings(in: root)
        return DailyNotes.path(for: Date(), settings: settings)
    }

    var dailyExists: Bool {
        guard let p = dailyPath else { return false }
        return snapshot?.notes[p] != nil
    }

    func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            if stale { try storeBookmark(url) }
            open(url)
        } catch {
            self.error = "Could not reopen the vault: \(error.localizedDescription)"
            UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        }
    }

    func open(_ url: URL) {
        stopAccess()
        let access = url.startAccessingSecurityScopedResource()
        isAccessing = access
        root = url
        error = nil
        do { try storeBookmark(url) } catch {
            self.error = "Could not remember this folder: \(error.localizedDescription)"
        }
        scan()
        if selectedPath == nil, let today = dailyPath, snapshot?.notes[today] != nil {
            selectedPath = today
        } else if selectedPath == nil {
            selectedPath = snapshot?.sortedNotePaths.first
        }
    }

    func scan() {
        guard let root else { return }
        isScanning = true
        defer { isScanning = false }
        var snap: VaultSnapshot?
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        coordinator.coordinate(readingItemAt: root, options: [.withoutChanges], error: &coordError) { url in
            snap = VaultSnapshot.scan(root: url)
        }
        if let coordError {
            error = coordError.localizedDescription
            return
        }
        snapshot = snap
        if let p = selectedPath, snap?.notes[p] == nil { selectedPath = snap?.sortedNotePaths.first }
    }

    func openDaily() {
        guard let p = dailyPath else { return }
        if snapshot?.notes[p] != nil {
            selectedPath = p
        } else if let root {
            error = "Today’s daily note (\(p)) is not in this vault yet. Editing lands in a later milestone."
            // Still try to select if the file exists unindexed.
            let url = root.appendingPathComponent(p)
            if FileManager.default.fileExists(atPath: url.path) {
                scan()
                selectedPath = p
            }
        }
    }

    func forgetVault() {
        stopAccess()
        root = nil
        snapshot = nil
        selectedPath = nil
        query = ""
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
    }

    private func storeBookmark(_ url: URL) throws {
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
    }

    private func stopAccess() {
        if isAccessing { root?.stopAccessingSecurityScopedResource() }
        isAccessing = false
    }

    static func dailySettings(in root: URL) -> DailyNotes.Settings {
        let file = root.appendingPathComponent(".obsidian/daily-notes.json")
        let json = (try? Data(contentsOf: file)).flatMap { ObsidianConfig.parse($0) }
        var settings = DailyNotes.Settings(json: json)
        if settings.folder.isEmpty { settings.folder = "Daily" }
        return settings
    }
}
