import Foundation
import OnyxCore
import OnyxSync

/// The open vault on iOS: a security-scoped folder bookmark, a `VaultSnapshot`, and search.
@MainActor
final class MobileVault: ObservableObject {
    static let bookmarkKey = "onyx.ios.vaultBookmark"
    /// The open sync-only vault's remote id (instead of a folder bookmark); see MobileSync.swift.
    static let managedKey = "onyx.ios.managedVault"

    /// Set while a sync-only vault (a copy in Application Support/Onyx/Vaults) is open.
    @Published var managed: ManagedVault?
    @Published var syncStatus: SyncStatus?
    var syncEngine: SyncEngine?
    var pendingSyncRescan = false
    var lastSyncRescan = Date.distantPast

    @Published var root: URL?
    @Published var snapshot: VaultSnapshot? { didSet { snapshotGeneration += 1 } }
    @Published var selectedPath: String?
    @Published var query = ""
    @Published var error: String?
    @Published var isScanning = false
    /// An `onyx://` link that arrived before the vault finished opening.
    var pendingURI: URL?

    private var isAccessing = false

    var notes: [NoteRecord] {
        guard let snap = snapshot else { return [] }
        return snap.sortedNotePaths.compactMap { snap.notes[$0] }
    }

    var visibleNotes: [NoteRecord] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var list: [NoteRecord]
        if !q.isEmpty, let snap = snapshot {
            list = snap.search(q).compactMap { snap.notes[$0.path] }
        } else {
            list = notes
        }
        if let folder = folderFilter {
            if folder.isEmpty {
                list = list.filter { ($0.path as NSString).deletingLastPathComponent.isEmpty }
            } else {
                list = list.filter { $0.path == folder || $0.path.hasPrefix(folder + "/") }
            }
        }
        return list
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
        if let id = UserDefaults.standard.string(forKey: Self.managedKey) {
            if let v = SyncVaultLibrary.default.vault(remoteID: id) { openManaged(v); return }
            UserDefaults.standard.removeObject(forKey: Self.managedKey)
        }
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
        stopSync()
        managed = nil
        UserDefaults.standard.removeObject(forKey: Self.managedKey)
        stopAccess()
        let access = url.startAccessingSecurityScopedResource()
        isAccessing = access
        root = url
        error = nil
        do { try storeBookmark(url) } catch {
            self.error = "Could not remember this folder: \(error.localizedDescription)"
        }
        loadTreeExpanded()
        scan()
        if selectedPath == nil, let today = dailyPath, snapshot?.notes[today] != nil {
            selectedPath = today
        } else if selectedPath == nil {
            selectedPath = snapshot?.sortedNotePaths.first
        }
        if let p = selectedPath { revealInTree(p) }
        applyPendingURI()
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
        loadBookmarks()
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
        stopSync()
        managed = nil
        UserDefaults.standard.removeObject(forKey: Self.managedKey)
        stopAccess()
        root = nil
        snapshot = nil
        selectedPath = nil
        query = ""
        folderFilter = nil
        persistTreeExpanded = false
        treeExpanded = []
        fileTreePrompt = nil
        persistTreeExpanded = true
        prefersDetail = false
        showCommandPalette = false
        bookmarkStore = BookmarkStore()
        bookmarksLocked = false
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
    }

    private func storeBookmark(_ url: URL) throws {
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
    }

    func stopAccessForManaged() { stopAccess() }

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

    @Published var libraryTab: LibraryTab = .notes
    @Published var jumpLine: Int? = nil
    @Published var jumpToken = 0
    @Published var folderFilter: String? = nil
    @Published var bookmarkStore = BookmarkStore()
    @Published var bookmarksLocked = false
    @Published var showReadingSettings = false
    @Published var showHistory = false
    @Published var showBacklinks = false
    @Published var showCommandPalette = false
    /// When true, a compact NavigationSplitView (iPhone) shows the note, not the sidebar.
    @Published var prefersDetail = false
    @Published var typesetRevision = 0
    // Tags tab (TagsScreen.swift)
    @Published var tagSelected: String?
    @Published var tagFilter = ""
    @Published var tagSort: TagTree.Sort = TagTree.Sort(rawValue: UserDefaults.standard.string(forKey: "onyx.ios.tags.sort") ?? "") ?? .name {
        didSet { UserDefaults.standard.set(tagSort.rawValue, forKey: "onyx.ios.tags.sort") }
    }
    @Published var tagExact = UserDefaults.standard.bool(forKey: "onyx.ios.tags.exact") {
        didSet { UserDefaults.standard.set(tagExact, forKey: "onyx.ios.tags.exact") }
    }
    @Published var tagExpanded: Set<String> = Set(UserDefaults.standard.stringArray(forKey: MobileVault.tagExpandedKey) ?? []) {
        didSet { UserDefaults.standard.set(tagExpanded.sorted(), forKey: MobileVault.tagExpandedKey) }
    }
    var tagCache: (gen: Int, sort: TagTree.Sort, tree: TagTree)?
    /// Bumped whenever `snapshot` is replaced, so derived caches know.
    var snapshotGeneration = 0

    // Files tree
    @Published var treeExpanded: Set<String> = [] {
        didSet { if treeExpanded != oldValue { saveTreeExpanded() } }
    }
    @Published var treeOrder = TreeOrder()
    @Published var treeRevealToken = 0
    @Published var fileTreePrompt: FileTreePrompt?
    @Published var fileTreeDraft = ""
    var persistTreeExpanded = true
    var treeDatesCache: (gen: Int, dates: TreeDates)?
    var pendingRelocate: (from: String, dest: String, reason: String)?
}

extension MobileVault {
    // MARK: - Writing

    /// The open vault folder is security-scoped, so notes and `.obsidian` files inside it can be written.
    var canWrite: Bool { root != nil }

    /// Current body of a note from the snapshot (the iOS app has no unsaved editor buffers yet).
    func noteText(for path: String) -> String? {
        snapshot?.notes[path]?.content
    }

    /// The only place the iOS app writes a vault file. Refuses paths outside the folder.
    /// Uses `NSFileCoordinator` and an atomic write, then updates the snapshot.
    @discardableResult
    func writeNote(_ content: String, to rel: String, create: Bool = false) -> Bool {
        guard let url = vaultURL(for: rel) else { return false }
        var ok = false
        var coordError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { url in
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if create && FileManager.default.fileExists(atPath: url.path) { return }
                try Data(content.utf8).write(to: url, options: .atomic)
                ok = true
            } catch {
                self.error = "Couldn’t save: \(error.localizedDescription)"
            }
        }
        if let coordError {
            error = coordError.localizedDescription
            return false
        }
        if ok {
            if var snap = snapshot {
                snap.update(path: rel, content: content)
                snapshot = snap
            } else {
                scan()
            }
            syncEdited()
        }
        return ok
    }

    func vaultURL(for rel: String) -> URL? {
        guard let root else { return nil }
        let base = root.standardizedFileURL
        let url = root.appendingPathComponent(rel).standardizedFileURL
        guard (url.path.hasPrefix(base.path + "/") || url.path == base.path), !rel.contains("..") else { return nil }
        return url
    }

    func openNote(_ path: String, line: Int? = nil, revealInTree: Bool = true) {
        let already = selectedPath == path
        selectedPath = path
        jumpLine = line
        jumpToken += 1
        prefersDetail = true
        if TreeReveal.shouldExpandAncestors(alreadyOpen: already, reveal: revealInTree) {
            self.revealInTree(path)
        }
        if libraryTab == .find || libraryTab == .bookmarks { libraryTab = .notes }   // the Tags tab stays put, so back returns to the tag
    }

    // MARK: - Navigation extras

    enum LibraryTab: String, CaseIterable, Identifiable {
        case notes, bookmarks, tags, outline, find
        var id: String { rawValue }
        var title: String {
            switch self {
            case .notes: "Files"
            case .bookmarks: "Bookmarks"
            case .tags: "Tags"
            case .outline: "Outline"
            case .find: "Find"
            }
        }
        var symbol: String {
            switch self {
            case .notes: "folder"
            case .bookmarks: "bookmark"
            case .tags: "number"
            case .outline: "list.bullet.indent"
            case .find: "magnifyingglass"
            }
        }
    }

    // MARK: - Bookmarks

    func loadBookmarks() {
        guard let root else {
            bookmarkStore = BookmarkStore()
            bookmarksLocked = false
            return
        }
        let url = root.appendingPathComponent(".obsidian/bookmarks.json")
        let data = try? Data(contentsOf: url)
        guard let parsed = BookmarkStore.parse(data: data) else {
            error = "Couldn’t read .obsidian/bookmarks.json: it isn’t valid JSON, so Onyx left it alone."
            bookmarksLocked = true
            return
        }
        bookmarksLocked = false
        bookmarkStore = parsed
    }

    func persistBookmarks() {
        guard let root, !bookmarksLocked else { return }
        let url = root.appendingPathComponent(".obsidian/bookmarks.json")
        var coordError: NSError?
        var failed: String?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { url in
            do {
                _ = try ObsidianConfig.update(url, changes: ["items": bookmarkStore.itemsJSON])
            } catch {
                failed = "Couldn’t save .obsidian/bookmarks.json: \(error.localizedDescription)"
            }
        }
        if let coordError { error = coordError.localizedDescription }
        else if let failed { error = failed }
    }

    private func bookmarkNow() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    func isBookmarked(_ path: String, isFolder: Bool = false, subpath: String? = nil) -> Bool {
        isFolder ? bookmarkStore.containsFolder(path: path) : bookmarkStore.containsFile(path: path, subpath: subpath)
    }

    @discardableResult
    func toggleBookmark(_ path: String, isFolder: Bool = false, subpath: String? = nil) -> Bool {
        guard canWrite, !bookmarksLocked else { return isBookmarked(path, isFolder: isFolder, subpath: subpath) }
        let now = bookmarkNow()
        let on: Bool
        if isFolder {
            on = bookmarkStore.toggleFolder(path: path, now: now)
        } else {
            on = bookmarkStore.toggleFile(path: path, subpath: subpath, now: now)
        }
        persistBookmarks()
        return on
    }

    func removeBookmark(id: UUID) {
        guard canWrite, !bookmarksLocked else { return }
        _ = bookmarkStore.remove(id: id)
        persistBookmarks()
    }

    func openBookmark(_ item: BookmarkItem) {
        switch item.type {
        case "file":
            guard let path = item.path else { return }
            var line: Int? = nil
            if let text = noteText(for: path), let sub = item.subpath {
                let headings = NoteParser.parseHeadings(text)
                line = BookmarkSubpath.line(subpath: sub, text: text, headings: headings)
            }
            openNote(path, line: line)
        case "folder":
            folderFilter = nil
            query = ""
            libraryTab = .notes
            if let path = item.path { revealInTree(path, includingSelf: true) }
        case "search":
            query = item.query ?? ""
            folderFilter = nil
            libraryTab = .notes
        case "url":
            if let s = item.url, let u = URL(string: s) {
                NotificationCenter.default.post(name: .onyxOpenURL, object: u)
            }
        default:
            error = "“\(item.displayTitle)” is a \(item.type) bookmark, which the iOS app can’t open yet."
        }
    }

    // MARK: - Mentions and replace

    func linkMention(_ mention: UnlinkedMention, title: String) -> Bool {
        guard canWrite, let body = noteText(for: mention.source),
              let next = UnlinkedMentions.link(body, range: mention.range, title: title) else { return false }
        return writeNote(next, to: mention.source)
    }

    func linkAllMentions(of path: String, mentions: [UnlinkedMention]) -> (files: Int, count: Int) {
        let title = snapshot?.notes[path]?.name ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let groups = Dictionary(grouping: mentions, by: \.source)
        var files = 0, count = 0
        for (src, items) in groups {
            guard let body = noteText(for: src) else { continue }
            let (next, n) = UnlinkedMentions.linkAll(body, mentions: items, title: title)
            guard n > 0, next != body else { continue }
            if writeNote(next, to: src) { files += 1; count += n }
        }
        return (files, count)
    }

    @discardableResult
    func applyVaultReplace(query: String, replacement: String, options: FindReplace.Options, selected: [FindReplace.Match]) -> (files: Int, replacements: Int) {
        var texts: [String: String] = [:]
        for path in Set(selected.map(\.path)) {
            if let body = noteText(for: path) { texts[path] = body }
        }
        let plan = FindReplace.plan(matches: selected, texts: texts)
        guard !plan.edits.isEmpty else { return (0, 0) }
        var done: [FindReplace.FileEdit] = []
        for step in plan.edits {
            if writeNote(step.after, to: step.path) {
                done.append(step)
            } else {
                for prev in done.reversed() { _ = writeNote(prev.before, to: prev.path) }
                error = "Replace failed; changes were reverted"
                return (0, 0)
            }
        }
        return (done.count, done.reduce(0) { $0 + $1.count })
    }
}
