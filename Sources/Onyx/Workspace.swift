import AppKit
import SwiftUI
import Observation
import OnyxCore

enum ViewMode: String { case read, edit }
enum Overlay: Equatable { case none, switcher, palette, graph, moveTo, syncLog, headings, merge, extract }
enum SidebarTab: String, CaseIterable, Identifiable {
    case files, search, recent, bookmarks, tags, git
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .files: return "folder"
        case .search: return "magnifyingglass"
        case .recent: return "clock"
        case .bookmarks: return "bookmark"
        case .tags: return "number"
        case .git: return "arrow.triangle.branch"
        }
    }
    var title: String { rawValue.capitalized }
}
enum InspectorTab: String, CaseIterable, Identifiable {
    case outline, backlinks, properties
    var id: String { rawValue }
    var symbol: String {
        switch self { case .outline: return "list.bullet.indent"; case .backlinks: return "arrow.uturn.backward"; case .properties: return "tablecells" }
    }
}

/// Everything about one open vault: the index, the open note, panels, saving.
@MainActor @Observable
final class Workspace {
    // Vault
    private(set) var root: URL?
    private(set) var snapshot: VaultSnapshot? { didSet { snapshotGen += 1 } }
    private(set) var snapshotGen = 0
    let graphStore = GraphStore()
    private(set) var isIndexing = false
    private(set) var indexMillis = 0
    /// Obsidian's Daily notes settings, re-read when daily-notes.json changes. `folder` falls back to
    /// "Daily" when the file doesn't name one (Onyx's long-standing default).
    var daily = DailyNotes.Settings(folder: "Daily")
    /// Bumped whenever Onyx writes or notices a change to a watched `.obsidian` config file.
    var obsidianConfigRevision = 0
    var homePath = "Home.md"

    // Open note
    private(set) var currentPath: String?
    var text: String = "" { didSet { if text != oldValue { settle(); textDidChange() } } }
    /// `text` for views that summarize the whole note (word count, outline, properties).
    /// Short notes stay live; long ones catch up when typing pauses, so a keystroke in a
    /// 300 KB clipping doesn't re-parse all of it.
    private(set) var settledText: String = ""
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    static let liveStatsLimit = 20_000
    private(set) var lastSaved: String = ""
    var mode: ViewMode = .read
    let finder = FindModel()
    @ObservationIgnored weak var liveEditor: OnyxTextView?
    @ObservationIgnored weak var liveReader: ReaderView.Coordinator?
    /// Back/forward for the focused pane (each split pane keeps its own; see Pane).
    private(set) var history: [NavEntry] = []
    private(set) var historyIndex = -1
    /// A source line for the live editor/reader to scroll to (going back restores your place).
    private(set) var scrollRequest: ScrollRequest? = nil
    @ObservationIgnored private var navigating = false
    var recent: [String] = []
    var bookmarks: [String] = []
    /// The open note was typed in since it was opened or last linted (lint on save).
    @ObservationIgnored var editedSinceLint = false
    var conflict: String? = nil          // disk content that differs from both buffer and last save
    var renderToken = 0                  // bump to make the reader re-render

    // Chrome — quiet by default; focus mode (⌃⌘F) takes it all away.
    var sidebarVisible = UserDefaults.standard.object(forKey: "onyx.sidebarOpen") as? Bool ?? true { didSet { if sidebarVisible != oldValue { chromeLog("sidebarVisible=\(sidebarVisible)") } } }
    /// The left sidebar is always docked. Older unpinned state is treated as pinned; `onyx.sidebarOpen` now means visibility only.
    var sidebarPinned = true
    var focusMode = false
    var showHints = !UserDefaults.standard.bool(forKey: "onyx.hintsDismissed")
    var sidebarTab: SidebarTab = .files
    // Split panes. Empty = one pane. The focused pane's note lives in currentPath/text/mode;
    // the others keep their own path, text and mode until focused (swap model).
    var panes: [Pane] = []
    var focusedPane = 0
    var splitAxis: SplitAxis = .vertical
    var paneFrames: [UUID: CGRect] = [:]   // window coords, top-left origin
    /// Relative sizes along the split axis, one per pane, summing to 1. Session-only
    /// (not written to defaults). Empty when there is no split.
    var paneRatios: [Double] = []   // persisted per vault with the axis and open notes
    /// The note pane the graph/atlas overlay is sitting on. Nil when there is no split
    /// (the solo page) or when the overlay is closed.
    var graphOverlayPaneID: UUID?
    /// Topmost visible source line (fractional, 0-based, frontmatter included) of the focused
    /// pane and of each unfocused pane. Reported by the editor and reader as they scroll and
    /// read by a freshly created view, so ⌘↩ and splits land on the same spot. Not observed:
    /// scrolling must not re-render SwiftUI.
    /// ⌘O's pre-folded index, rebuilt lazily when the vault snapshot changes.
    @ObservationIgnored private var quickCache: (gen: Int, index: QuickIndex)?
    var quickIndex: QuickIndex {
        if let c = quickCache, c.gen == snapshotGen { return c.index }
        let i = snapshot.map(QuickIndex.init) ?? QuickIndex(entries: [])
        quickCache = (snapshotGen, i)
        return i
    }
    @ObservationIgnored var liveTop: Double = 0
    @ObservationIgnored var paneTop: [UUID: Double] = [:]
    var selectedFolder: String? = nil    // folder chosen from the title path, highlighted in the tree
    var revealToken = 0                  // bump to scroll the tree to `selectedFolder`
    var inspectorVisible = UserDefaults.standard.bool(forKey: "onyx.inspectorOpen") { didSet { if inspectorVisible != oldValue { chromeLog("inspectorVisible=\(inspectorVisible)") } } }
    var inspectorPinned = UserDefaults.standard.bool(forKey: "onyx.inspectorOpen") { didSet { if inspectorPinned != oldValue { chromeLog("inspectorPinned=\(inspectorPinned)") } } }
    var inspectorTab: InspectorTab = .outline
    var overlay: Overlay = .none { didSet { if overlay != oldValue { overlayChanged(from: oldValue) } } }
    var searchQuery = ""
    var focusSearch = 0
    var graphAtlas = false {
        didSet {   // atlas ⇄ focus inside the graph updates its history entry rather than adding one
            if overlay == .graph, history.indices.contains(historyIndex), case .graph = history[historyIndex].place {
                history[historyIndex].place = .graph(atlas: graphAtlas)
            }
        }
    }
    var sidenotes = true
    var externalPulse: Date? = nil
    var lastExternalChange: Date? = nil
    var toast: String? = nil
    let speech = SpeechReader()
    let recorder = AudioRecorder()
    /// Selection or heading section waiting on the extract-to picker.
    var pendingExtract: PendingExtract? = nil
    var editorJump: Int? = nil           // line to reveal in the editor
    var readerJump: Int? = nil           // heading index to reveal in the reader
    var expanded: Set<String> = []

    private var watcher: FileWatcher?
    private var saveTask: Task<Void, Never>?
    private var reindexTask: Task<Void, Never>?
    private var pendingPaths = Set<String>()
    private var suppressTextChange = false

    var currentNote: NoteRecord? { currentPath.flatMap { snapshot?.notes[$0] } }
    /// The open file is an Obsidian canvas (shown by CanvasView, saved as JSON Canvas).
    var isCanvas: Bool { currentPath?.isCanvasPath == true }
    /// The open file is an Obsidian Base (shown by BasesView, read-only YAML).
    var isBase: Bool { currentPath?.isBasePath == true }
    /// The open file is an attachment (image, audio, video, PDF or anything else), shown by FileView.
    var isFile: Bool { currentPath?.opensInFileView == true }
    /// Folder and name for the title path (notes, canvases and bases).
    var titleParts: (folder: String, name: String)? {
        if let n = currentNote { return (n.folder, n.name) }
        guard let p = currentPath, isCanvas || isBase || isFile else { return nil }
        if isFile { return ((p as NSString).deletingLastPathComponent, (p as NSString).lastPathComponent) }   // attachments keep their extension
        return ((p as NSString).deletingLastPathComponent, ((p as NSString).lastPathComponent as NSString).deletingPathExtension)
    }
    /// Title-bar crumbs: the `partOf` ancestry when the note has one, else its folders.
    func titleCrumbs(_ n: (folder: String, name: String)) -> [TitleCrumb] {
        guard let p = currentPath, let snap = snapshot, snap.notes[p] != nil else { return TitlePath.crumbs(folder: n.folder, name: n.name) }
        let a = snap.ancestry(of: p)
        return TitlePath.crumbs(folder: n.folder, name: n.name, ancestry: a.chain, otherParents: a.otherParents)
    }
    var isDirty: Bool { text != lastSaved }
    var anyChrome: Bool { sidebarVisible || inspectorVisible || overlay != .none }

    // MARK: Opening a vault

    /// Continuous git when the vault is a repository (see GitSync); nil otherwise.
    var git: GitSync?
    /// Obsidian Sync, only for folders the user connected in Settings ▸ Sync (see VaultSync); nil otherwise.
    var obsidianSync: VaultSync?
    /// Recent git and Obsidian Sync activity for this vault, persisted in Application Support.
    var syncLog: SyncLogStore?

    func open(vault url: URL, initialNote: String? = nil, restoreSplits: Bool = true) {
        let next = url.standardizedFileURL
        if root != nil, root != next {
            persistSplitLayout()
            speech.stop()
            currentPath = nil
            text = ""; lastSaved = ""
            history = []; historyIndex = -1
        }
        panes = []; focusedPane = 0; paneRatios = []; paneFrames = [:]; paneTop = [:]
        root = next
        git?.stop()
        git = GitSync.detect(root!)
        syncLog = SyncLogStore(vaultRoot: root!)
        if ProcessInfo.processInfo.environment["ONYX_SYNC_LOG_DEMO"] == "1" { syncLog?.seedPreviewIfEmpty() }
        git?.beforeCommit = { [weak self] in self?.flushSave() }
        git?.onLog = { [weak self] event, detail in self?.syncLog?.append(source: .git, event: event, detail: detail) }
        git?.start()
        obsidianSync?.stop()
        obsidianSync = VaultSync.resume(for: root!, onLog: { [weak self] event, detail in
            self?.syncLog?.append(source: .obsidian, event: event, detail: detail)
        })
        loadObsidianSettings()
        recent = UserDefaults.standard.stringArray(forKey: key("recent")) ?? obsidianRecent()
        loadTreeOrder()
        bookmarks = UserDefaults.standard.stringArray(forKey: key("bookmarks")) ?? obsidianBookmarks()
        isIndexing = true
        let root = self.root!
        let ignore = obsidianIgnore()
        let restoreSplits = restoreSplits
        Task.detached(priority: .userInitiated) {
            let t0 = Date()
            let snap = VaultSnapshot.scan(root: root, ignore: ignore)
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            await MainActor.run {
                self.snapshot = snap
                self.indexMillis = ms
                self.isIndexing = false
                if let n = initialNote { self.openNote(n) }
                else if self.daily.autorun {   // Daily notes "Open daily note on startup"
                    if restoreSplits { _ = self.restoreSplitLayout() }
                    self.openDaily()
                }
                else if restoreSplits && self.restoreSplitLayout() { }
                else if self.currentPath == nil {
                    self.openHome()
                    // like Obsidian's Homepage "Graph view": the atlas is the first thing you see
                    if self.atlasOnStartup && ProcessInfo.processInfo.environment["ONYX_NO_STARTUP_GRAPH"] == nil {
                        self.graphAtlas = true; self.show(.graph)
                    }
                }
            }
        }
        watcher = FileWatcher(root: root) { [weak self] paths in
            Task { @MainActor in self?.filesChanged(paths) }
        }
    }

    private func key(_ k: String) -> String { "onyx.\(root?.path ?? "").\(k)" }

    func obsidianJSON(_ name: String) -> Any? {
        guard let root, let d = try? Data(contentsOf: root.appendingPathComponent(".obsidian/\(name)")) else { return nil }
        return try? JSONSerialization.jsonObject(with: d)
    }
    /// Obsidian Homepage plugin set to open the graph on startup (Kenneth's ~/Notes).
    private(set) var obsidianHomeIsGraph = false
    /// Open the atlas as the home view at launch. Per vault; defaults to the Homepage plugin's choice.
    var atlasOnStartup: Bool {
        get { UserDefaults.standard.object(forKey: key("atlasOnStartup")) as? Bool ?? obsidianHomeIsGraph }
        set { UserDefaults.standard.set(newValue, forKey: key("atlasOnStartup")) }
    }
    private func loadObsidianSettings() {
        loadDailySettings()
        if let a = obsidianJSON("app.json") as? [String: Any], let m = a["defaultViewMode"] as? String { mode = m == "source" ? .edit : .read }
        if let h = obsidianJSON("plugins/homepage/data.json") as? [String: Any],
           let hp = (h["homepages"] as? [String: Any])?.values.first as? [String: Any], let v = hp["value"] as? String {
            homePath = v.hasSuffix(".md") ? v : v + ".md"
            obsidianHomeIsGraph = (hp["kind"] as? String) == "Graph view" && (hp["openOnStartup"] as? Bool ?? false)
        }
    }
    private func loadDailySettings() {
        let json = obsidianJSON("daily-notes.json") as? [String: Any]
        var d = DailyNotes.Settings(json: json)
        if json?["folder"] == nil { d.folder = "Daily" }
        daily = d
    }
    var templateSettings: TemplateSettings { TemplateSettings(json: obsidianJSON("templates.json") as? [String: Any]) }

    /// Write `changes` into `.obsidian/<file>` (keeping every other key as it is), then re-read.
    @discardableResult
    func setObsidianConfig(_ file: String, _ changes: [String: Any?]) -> Bool {
        guard let root else { return false }
        let url = root.appendingPathComponent(".obsidian/\(file)")
        let ignoreBefore = obsidianIgnore()
        do {
            guard try ObsidianConfig.update(url, changes: changes) else { return true }
        } catch {
            toast = "Couldn’t save .obsidian/\(file): it isn’t valid JSON, so Onyx left it alone."
            return false
        }
        obsidianConfigChanged([file])
        if file == "app.json", obsidianIgnore() != ignoreBefore { reindex() }
        git?.edited()
        obsidianSync?.edited()
        return true
    }

    /// Obsidian (or Sync) changed a config file under `.obsidian`: pick up the new values.
    func obsidianConfigChanged(_ files: [String]) {
        if files.contains("daily-notes.json") { loadDailySettings() }
        obsidianConfigRevision += 1
    }

    /// Folder a new note goes in, honoring app.json's "Default location for new notes". With no
    /// setting, `contextual` (Onyx's own choice) is used.
    func newNoteFolder(contextual: String) -> String {
        let a = obsidianJSON("app.json") as? [String: Any]
        return NewNoteLocation.folder(location: a?["newFileLocation"] as? String,
                                      folderPath: a?["newFileFolderPath"] as? String, contextual: contextual)
    }

    /// The text of a new daily note: the daily-notes.json template when set and present, filled in
    /// like Obsidian does, else Onyx's built-in shape.
    func dailyNoteText(for date: Date, path: String) -> String {
        if let t = daily.templatePath, let root,
           let body = (snapshot?.notes[t]?.content) ?? (try? String(contentsOf: root.appendingPathComponent(t), encoding: .utf8)) {
            let title = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            return DailyNotes.expand(template: body, date: date, title: title, dateFormat: daily.format,
                                     timeFormat: templateSettings.timeFormat)
        }
        return DailyNotes.template(for: date)
    }

    /// For files written outside `write` (recordings): let the index, git and sync know.
    func fileAdded(_ rel: String) {
        snapshot?.refresh(paths: [rel])
        git?.edited()
        obsidianSync?.edited()
    }
    func noteUpdatedOnDisk(_ path: String, content: String) { snapshot?.update(path: path, content: content) }
    /// Obsidian's "Default location for new attachments" (`attachmentFolderPath` in app.json).
    func obsidianAttachmentFolderSetting() -> String? {
        (obsidianJSON("app.json") as? [String: Any])?["attachmentFolderPath"] as? String
    }
    private func obsidianIgnore() -> [String] {
        ((obsidianJSON("app.json") as? [String: Any])?["userIgnoreFilters"] as? [String]) ?? []
    }
    private func obsidianBookmarks() -> [String] {
        guard let b = obsidianJSON("bookmarks.json") as? [String: Any], let items = b["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { $0["type"] as? String == "file" ? $0["path"] as? String : nil }
    }
    private func obsidianRecent() -> [String] {
        guard let r = obsidianJSON("plugins/recent-files-obsidian/data.json") as? [String: Any], let f = r["recentFiles"] as? [[String: Any]] else { return [] }
        return f.compactMap { $0["path"] as? String }
    }

    // MARK: Navigation

    func openHome() {
        if snapshot?.notes[homePath] != nil { openNote(homePath) }
        else if let first = snapshot?.sortedNotePaths.first { openNote(first) }
    }

    func openRandomNote() {
        guard let snap = snapshot else { return }
        guard let path = RandomNote.pick(from: snap.sortedNotePaths, excluding: currentPath) else { return }
        openNote(path)
    }

    func openLink(_ target: String, from source: String? = nil) {
        guard let snap = snapshot else { return }
        let link = NoteParser.makeLink(inner: target, embed: false, range: NSRange())
        if let p = snap.resolve(link.target, from: source ?? currentPath) {
            openNote(p, heading: link.heading)
        } else if !link.target.isEmpty {
            createNote(named: link.target, folder: newNoteFolder(contextual: ""))   // like Obsidian: clicking an unresolved link creates it
        }
    }

    func openNote(_ path: String, heading: String? = nil, recordHistory: Bool = true, revealInTree: Bool = true) {
        selectedFolder = nil
        guard let snap = snapshot else { return }
        let content: String
        if let note = snap.notes[path] { content = note.content }
        else if path.isCanvasPath, snap.canvases[path] != nil, let root {   // an Obsidian canvas
            content = (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
        } else if path.isBasePath, snap.bases[path] != nil, let root {
            content = snap.bases[path] ?? (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
        } else if path.opensInFileView, let root, snap.attachments[path] != nil || FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path) {
            content = ""   // an attachment: FileView reads the file itself; the text buffer stays empty and is never saved
        } else { return }
        if currentPath != path { lintOnSave() }
        flushSave()
        if let c = currentPath, c != path { git?.commitNow() }   // switching notes commits at once
        if !selectionIncludes(path) { treeSelection.clear() }   // opened from elsewhere
        if recordHistory { pushHistory(.note(path)) }
        let alreadyOpen = currentPath == path
        if !alreadyOpen {
            liveTop = 0
            speech.stop()
            editedSinceLint = false
        }
        currentPath = path
        conflict = nil
        suppressTextChange = true
        text = content
        lastSaved = content
        suppressTextChange = false
        renderToken += 1
        recent.removeAll { $0 == path }
        recent.insert(path, at: 0)
        if recent.count > 50 { recent.removeLast(recent.count - 50) }
        UserDefaults.standard.set(recent, forKey: key("recent"))
        // reveal in tree — but not when the note is already open, and not when a
        // folder-row click just toggled expansion: both would undo a user collapse.
        if TreeReveal.shouldExpandAncestors(alreadyOpen: alreadyOpen, reveal: revealInTree) {
            for parent in TreeReveal.ancestors(of: path) { expanded.insert(parent) }
        }
        if let heading, let note = snap.notes[path], let idx = note.summary.headings.firstIndex(where: { $0.text.lowercased() == heading.lowercased() }) {
            readerJump = idx; editorJump = note.summary.headings[idx].line
        }
        if overlay != .none { navigating = true; overlay = .none; navigating = false }
        if isSplit { persistSplitLayout() }
    }

    // MARK: [[ suggestions (editor)

    /// Rows for the editor's `[[` popup: notes through the ⌘O matcher (aliases, recency,
    /// folders), or after `#` the target note's headings.
    func linkSuggestions(_ part: LinkCompletion.Part, _ q: String) -> [LinkSuggestion] {
        guard let snap = snapshot else { return [] }
        switch part {
        case .note:
            let hits = quickIndex.search(q, recent: recent, limit: 16).filter { !$0.entry.path.isCanvasPath }.prefix(12)
            return hits.enumerated().map { i, h in
                let path = h.entry.path
                let name = h.entry.name.text
                let unique = (snap.namesIndex[name.lowercased()]?.count ?? 1) <= 1
                var insert = LinkCompletion.linkText(path: path, name: name, nameIsUnique: unique)
                var title = name, hitsOut = h.nameHits
                if let a = h.alias { insert += "|" + a; title = "\(name) · \(a)"; hitsOut = [] }
                let folder = (path as NSString).deletingLastPathComponent
                return LinkSuggestion(id: i, title: title, detail: folder, titleHits: hitsOut, insert: insert, exact: h.exact)
            }
        case .heading(let note):
            guard let path = note.isEmpty ? currentPath : snap.resolve(note, from: currentPath),
                  let n = snap.notes[path] else { return [] }
            let toks = QuickMatch.tokens(q)
            let fq = QuickMatch.fold(q.trimmingCharacters(in: .whitespaces))
            var rows: [(Int, LinkSuggestion)] = []
            for (i, h) in n.summary.headings.enumerated() {
                let key = MatchKey(h.text)
                var score = 0, hits: [Int] = [], ok = true
                for t in toks {
                    guard let m = QuickMatch.match(t, in: key) else { ok = false; break }
                    score += m.score; hits += m.positions
                }
                guard ok else { continue }
                let pad = String(repeating: "  ", count: max(0, h.level - 1))
                rows.append((toks.isEmpty ? -i : score, LinkSuggestion(id: i, title: h.text, detail: pad + String(repeating: "#", count: h.level), titleHits: hits, insert: h.text, exact: !fq.isEmpty && QuickMatch.fold(h.text) == fq)))
            }
            return rows.sorted { $0.0 > $1.0 }.prefix(12).enumerated().map { i, r in var s = r.1; s = LinkSuggestion(id: i, title: s.title, detail: s.detail, titleHits: s.titleHits, insert: s.insert, exact: s.exact); return s }
        case .block, .alias:
            return []
        }
    }

    /// `key::` completion (FieldCompletion): known keys after `word:`, notes after a link-valued `key:: `.
    @ObservationIgnored private var fieldCache: (gen: Int, keys: [(key: String, count: Int)], linkKinds: Set<String>)?
    func fieldSuggestions(_ part: FieldCompletion.Part, _ q: String) -> [LinkSuggestion] {
        guard let snap = snapshot else { return [] }
        if fieldCache?.gen != snapshotGen { fieldCache = (snapshotGen, snap.fieldKeys(), snap.linkValuedKinds()) }
        guard let cache = fieldCache else { return [] }
        switch part {
        case .key:
            return FieldCompletion.keySuggestions(q, keys: cache.keys).enumerated().map { i, k in
                let n = cache.keys.first { $0.key == k.key }?.count ?? 0
                return LinkSuggestion(id: i, title: k.key + "::", detail: n == 1 ? "1 use" : "\(n) uses", titleHits: Array(0..<min(q.count, k.key.count)), insert: FieldCompletion.keyInsert(k.key), exact: k.exact)
            }
        case .value(let key):
            guard cache.linkKinds.contains(InlineField.kind(key)) else { return [] }
            return linkSuggestions(.note, q).filter { s in
                guard let p = currentPath else { return true }
                return s.insert != ((p as NSString).lastPathComponent as NSString).deletingPathExtension
            }.enumerated().map { i, s in
                var s = s; s = LinkSuggestion(id: i, title: s.title, detail: s.detail, titleHits: s.titleHits, insert: "[[" + s.insert + "]]", exact: s.exact); return s
            }
        }
    }

    // MARK: Back / forward (⌘[ ⌘], mouse buttons, swipe)

    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex < history.count - 1 }
    func goBack() { go(-1) }
    func goForward() { go(1) }

    /// Remember where we are in the current entry before leaving it.
    private func saveHistoryPlace() {
        guard history.indices.contains(historyIndex), case .note(let p) = history[historyIndex].place, p == currentPath else { return }
        history[historyIndex].top = liveTop
        history[historyIndex].mode = mode
    }

    private func pushHistory(_ place: NavEntry.Place) {
        saveHistoryPlace()
        if history.indices.contains(historyIndex), history[historyIndex].place == place { return }
        if historyIndex < history.count - 1 { history.removeSubrange((historyIndex + 1)...) }
        history.append(NavEntry(place: place, mode: mode))
        historyIndex = history.count - 1
        if history.count > 200 { history.removeFirst(history.count - 200); historyIndex = history.count - 1 }
    }

    private func go(_ step: Int) {
        let j = historyIndex + step
        guard history.indices.contains(j) else { return }
        // a note that's gone (trashed, renamed elsewhere) is skipped
        if case .note(let p) = history[j].place, snapshot?.notes[p] == nil, snapshot?.canvases[p] == nil, snapshot?.bases[p] == nil, snapshot?.attachments[p] == nil {
            history.remove(at: j)
            if step < 0 { historyIndex = j } // current entry slid down into j
            return go(step)
        }
        saveHistoryPlace()
        historyIndex = j
        let e = history[j]
        navigating = true
        defer { navigating = false }
        switch e.place {
        case .note(let p):
            if overlay != .none { withAnimation(Motion.overlay) { overlay = .none } }
            if p != currentPath { openNote(p, recordHistory: false) }
            if let m = e.mode, m != mode { mode = m }
            liveTop = e.top
            scrollRequest = ScrollRequest(line: e.top, id: (scrollRequest?.id ?? 0) + 1)
        case .graph(let atlas):
            graphAtlas = atlas
            if overlay != .graph { withAnimation(Motion.overlay) { overlay = .graph } }
        }
        chromeLog("history \(step < 0 ? "back" : "forward") → \(historyIndex)/\(history.count) \(e.place) top=\(String(format: "%.1f", e.top))")
    }

    /// Opening the graph is a place you can go back to; closing it (Esc, ⌘G) steps back to
    /// the note and leaves the graph one ⌘] away.
    private func overlayChanged(from old: Overlay) {
        // Pane pinning always tracks the overlay, including history navigation
        // (`navigating` only suppresses the history side-effects below).
        if overlay == .graph {
            if graphOverlayPaneID == nil || (isSplit && !panes.contains(where: { $0.id == graphOverlayPaneID })) {
                graphOverlayPaneID = isSplit && panes.indices.contains(focusedPane) ? panes[focusedPane].id : nil
            }
        } else if old == .graph {
            graphOverlayPaneID = nil
            if !navigating { restoreNoteFocus() }
        }
        guard !navigating else { return }
        if overlay == .graph, old != .graph {
            pushHistory(.graph(atlas: graphAtlas))
        } else if old == .graph, overlay != .graph,
                  history.indices.contains(historyIndex), case .graph = history[historyIndex].place, historyIndex > 0 {
            historyIndex -= 1
        }
    }

    /// After the graph overlay closes, give the keyboard back to the note underneath.
    private func restoreNoteFocus() {
        guard mode == .edit else { return }
        Task { @MainActor in
            guard let w = MainWindow.current, let root = w.contentView else { return }
            var stack: [NSView] = [root]
            var found: OnyxTextView?
            while let v = stack.popLast() {
                if let tv = v as? OnyxTextView, tv.isEditable { found = tv; break }
                stack.append(contentsOf: v.subviews)
            }
            if let tv = found { w.makeFirstResponder(tv) }
        }
    }

    /// Open a note at a source line (a backlink's context): the live view scrolls there once it has rendered.
    func openNote(_ path: String, line: Int) {
        openNote(path)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, self.currentPath == path else { return }
            self.scrollRequest = ScrollRequest(line: Double(max(0, line - 1)), id: (self.scrollRequest?.id ?? 0) + 1)
        }
    }

    // MARK: Daily notes

    func openDaily(offset: Int = 0) {
        guard snapshot != nil else { return }
        if offset != 0, let cur = currentPath, DailyNotes.date(ofPath: cur, settings: daily) != nil {
            // previous / next existing daily note, like daily-notes:goto-prev/next
            let all = snapshot!.notes.keys.compactMap { p in DailyNotes.date(ofPath: p, settings: daily).map { (p, $0) } }
                .sorted { $0.1 < $1.1 }.map(\.0)
            if let i = all.firstIndex(of: cur) {
                let j = i + offset
                if all.indices.contains(j) { openNote(all[j]) }
                return
            }
        }
        let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        let path = DailyNotes.path(for: date, settings: daily)
        if snapshot?.notes[path] == nil { _ = write(dailyNoteText(for: date, path: path), to: path, create: true) }
        openNote(path)
        mode = .edit
    }

    // MARK: Creating

    @discardableResult
    func createNote(named rawName: String, folder: String) -> String? {
        var name = rawName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { name = "Untitled" }
        name = name.replacingOccurrences(of: ":", with: "-")
        var path = name.contains("/") ? name : (folder.isEmpty ? name : folder + "/" + name)
        if !path.lowercased().hasSuffix(".md") { path += ".md" }
        var n = 1
        let base = String(path.dropLast(3))
        while snapshot?.notes[path] != nil || FileManager.default.fileExists(atPath: root?.appendingPathComponent(path).path ?? "") {
            n += 1; path = "\(base) \(n).md"
        }
        let title = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        guard write("# \(title)\n\n", to: path, create: true) else { return nil }
        openNote(path)
        mode = .edit
        return path
    }

    func newNote() {
        let folder = newNoteFolder(contextual: NoteNaming.folderForNewNote(
            selected: treeSelection.selected,
            folders: snapshot?.folders ?? [],
            selectedFolder: selectedFolder,
            currentPath: currentPath))
        createNote(named: "Untitled", folder: folder)
    }

    /// Folder a New Folder / New Note Here command should use: an explicit path, else the
    /// single selected folder (or the parent of a selected file), else the title-path folder,
    /// else the folder of the open note, else the vault root.
    func folderForNewItem(explicit: String? = nil) -> String {
        if let e = explicit { return e }
        if treeSelection.selected.count == 1, let p = treeSelection.selected.first {
            if snapshot?.folders.contains(p) == true { return p }
            return (p as NSString).deletingLastPathComponent
        }
        if let f = selectedFolder { return f }
        return currentPath.map { ($0 as NSString).deletingLastPathComponent } ?? ""
    }

    /// Create an empty folder, refresh the tree, reveal it, and offer a name
    /// (inline in the file tree, or the name prompt if the sidebar is hidden).
    @discardableResult
    func createFolder(named rawName: String? = nil, in explicit: String? = nil, prompt: Bool = true) -> String? {
        guard let root else { return nil }
        let folder = folderForNewItem(explicit: explicit)
        let fm = FileManager.default
        var taken = Set((snapshot?.folders ?? []).filter { ($0 as NSString).deletingLastPathComponent == folder }.map { ($0 as NSString).lastPathComponent })
        let parentURL = folder.isEmpty ? root : root.appendingPathComponent(folder)
        if let kids = try? fm.contentsOfDirectory(atPath: parentURL.path) { taken.formUnion(kids) }
        let name = FolderCreate.uniqueName(base: rawName ?? FolderCreate.defaultName, existing: taken)
        let rel = FolderCreate.path(name: name, in: folder)
        let url = root.appendingPathComponent(rel).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/"), !rel.contains("..") else { return nil }
        do { try fm.createDirectory(at: url, withIntermediateDirectories: true) }
        catch { toast = "Couldn’t create folder: \(error.localizedDescription)"; return nil }
        snapshot?.refresh(paths: [rel])
        git?.edited()
        obsidianSync?.edited()
        vaultMutated("Add \(name)", paths: [rel])
        revealFolder(rel)
        treeSelection.click(rel)
        let quiet = ProcessInfo.processInfo.environment["ONYX_SHOT_QUIET"] == "1"
        if prompt, !quiet { DispatchQueue.main.async { self.confirmRename(rel) } }
        return rel
    }

    func newFolder(in explicit: String? = nil) { _ = createFolder(in: explicit) }

    // MARK: Sidebar selection (Finder-style)

    /// Rows selected in the file tree. Click selects one (and opens it); ⇧-click spans from the
    /// anchor over visible rows; ⌘-click toggles one without changing the open note.
    var treeSelection = TreeSelection()
    /// The tree was the last thing clicked, so ⌘⌫, Return (rename), and Esc act on its selection.
    @ObservationIgnored var treeFocused = false
    /// The file-tree row currently being renamed in place, if any.
    var renamingPath: String? = nil
    var renameDraft = ""
    var renameError: String? = nil
    /// Paths being ⌘-dragged in the file tree. Empty when no tree-move drag is in flight.
    var draggingPaths: [String] = []
    /// Folder a tree-move drop would land in (`""` = vault root). Nil when not hovering a valid row.
    var dropTarget: String? = nil
    var dropForbidden = false
    @ObservationIgnored private var dropExpandTask: Task<Void, Never>?


    /// True if this path is selected, or it's the folder note of a selected folder
    /// (`Projects/Projects.md` when `Projects` is selected).
    func selectionIncludes(_ path: String) -> Bool {
        if treeSelection.contains(path) { return true }
        guard path.lowercased().hasSuffix(".md") else { return false }
        let parent = (path as NSString).deletingLastPathComponent
        guard !parent.isEmpty else { return false }
        let stem = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        return (parent as NSString).lastPathComponent == stem && treeSelection.contains(parent)
    }

    func visibleTreePaths() -> [String] { snapshot?.tree.visiblePaths(expanded: expanded, children: treeChildren) ?? [] }

    /// Sidebar order: a vault-wide default plus per-folder overrides, saved per vault.
    var treeOrder = TreeOrder() { didSet { saveTreeOrder() } }
    @ObservationIgnored private var treeDatesCache: (gen: Int, dates: TreeDates)?
    func treeChildren(_ node: FileNode) -> [FileNode] {
        let kids = node.children ?? []
        let s = treeOrder.sort(for: node.path)
        if s == .standard { return kids }   // the snapshot is already in natural order with folders first
        guard let snap = snapshot else { return kids }
        if treeDatesCache?.gen != snapshotGen { treeDatesCache = (snapshotGen, TreeDates(snap)) }
        return treeDatesCache!.dates.ordered(kids, by: s)
    }
    func setSort(_ s: TreeSort, folder: String? = nil) {
        if let f = folder { treeOrder.overrides[f] = s == treeOrder.base ? nil : s } else { treeOrder.base = s }
    }
    func clearSortOverride(_ folder: String) { treeOrder.overrides[folder] = nil }
    func loadTreeOrder() {
        let d = UserDefaults.standard.data(forKey: key("treeSort"))
        let o = d.flatMap { try? JSONDecoder().decode(TreeOrder.self, from: $0) } ?? TreeOrder()
        if o != treeOrder { treeOrder = o }
    }
    private func saveTreeOrder() {
        guard root != nil else { return }
        UserDefaults.standard.set(try? JSONEncoder().encode(treeOrder), forKey: key("treeSort"))
    }

    /// One code path for real clicks and the test harness. `open` runs only for a plain click.
    func treeClick(_ path: String, modifiers: NSEvent.ModifierFlags, open: () -> Void) {
        treeFocused = true
        if modifiers.contains(.command) { treeSelection.toggle(path); return }
        if modifiers.contains(.shift) { treeSelection.extend(to: path, visible: visibleTreePaths()); return }
        treeSelection.click(path)
        open()
    }
    /// Esc: drop a multi-selection back to just the open note. True if it did anything.
    func clearTreeSelection() -> Bool {
        guard treeSelection.isMulti else { return false }
        treeSelection.clear()
        if let c = currentPath { treeSelection.click(c) }
        return true
    }
    /// What a menu or ⌘⌫ acts on: the selection when `path` is part of a multi-selection, else just `path`.
    func targets(for path: String) -> [String] {
        treeSelection.isMulti && treeSelection.contains(path) ? TreeSelection.roots(treeSelection.selected) : [path]
    }

    // MARK: Deleting

    /// Ask, then move a note, file or folder to the Trash.
    func confirmTrash(_ path: String) {
        guard let root else { return }
        let isDir = (try? root.appendingPathComponent(path).resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let last = (path as NSString).lastPathComponent
        let name = path.lowercased().hasSuffix(".md") ? (last as NSString).deletingPathExtension : last
        let a = NSAlert()
        a.messageText = "Move “\(name)” to the Trash?"
        if isDir {
            let n = snapshot?.notes.keys.filter { $0.hasPrefix(path + "/") }.count ?? 0
            a.informativeText = "The folder and the \(n) note\(n == 1 ? "" : "s") in it. You can restore it from the Trash in Finder."
        } else {
            a.informativeText = "You can restore it from the Trash in Finder."
        }
        a.addButton(withTitle: "Move to Trash"); a.addButton(withTitle: "Cancel")
        a.buttons.first?.hasDestructiveAction = true
        if a.runModal() == .alertFirstButtonReturn { trash(path) }
    }
    /// For the test harness: "a, [b], c" with the current entry bracketed.
    var debugHistory: String {
        history.enumerated().map { i, e in
            let s: String
            switch e.place { case .note(let p): s = ((p as NSString).lastPathComponent as NSString).deletingPathExtension; case .graph: s = "graph" }
            return i == historyIndex ? "[\(s)]" : s
        }.joined(separator: ", ")
    }
    func confirmTrashCurrent() { if let p = currentPath { confirmTrash(p) } }

    /// One confirm for several items, then one Trash call and one commit.
    func confirmTrash(_ paths: [String]) {
        let roots = TreeSelection.roots(paths)
        guard roots.count > 1 else { if let p = roots.first { confirmTrash(p) }; return }
        let a = NSAlert()
        a.messageText = "Move \(roots.count) items to the Trash?"
        let names = roots.map { p -> String in let l = (p as NSString).lastPathComponent; return l.lowercased().hasSuffix(".md") ? String(l.dropLast(3)) : l + "/" }
        var info = names.prefix(8).map { "• " + $0 }.joined(separator: "\n")
        if names.count > 8 { info += "\n… and \(names.count - 8) more" }
        let inside = snapshot?.notes.keys.filter { k in roots.contains { k.hasPrefix($0 + "/") } }.count ?? 0
        if inside > 0 { info += "\n\nIncluding \(inside) note\(inside == 1 ? "" : "s") inside the selected folders." }
        a.informativeText = info + "\n\nYou can restore them from the Trash in Finder."
        a.addButton(withTitle: "Move to Trash"); a.addButton(withTitle: "Cancel")
        a.buttons.first?.hasDestructiveAction = true
        if a.runModal() == .alertFirstButtonReturn { trash(roots) }
    }

    /// Move to the Trash (recoverable). Every pane showing it moves on (back in its history,
    /// else Home) and it drops out of every history and the recent list.
    func trash(_ path: String) { trash([path]) }

    /// Several paths in one go: one Trash call, one history/pane cleanup, one commit.
    func trash(_ paths: [String], afterward: (() -> Void)? = nil) {
        guard let root else { return }
        let roots = TreeSelection.roots(paths)
        guard !roots.isEmpty else { return }
        let gone: (String) -> Bool = { p in roots.contains { p == $0 || p.hasPrefix($0 + "/") } }
        if let c = currentPath, gone(c) { flushSave() }   // the Trash gets the latest words
        let affected = Array(Set((snapshot?.notes.keys.filter(gone) ?? []) + roots)).sorted()
        NSWorkspace.shared.recycle(roots.map { root.appendingPathComponent($0) }) { [weak self] trashed, err in
            DispatchQueue.main.async {
                guard let self else { return }
                if let err, trashed.isEmpty { self.toast = "Couldn’t move to Trash: \(err.localizedDescription)"; return }
                self.afterTrash(affected, gone: gone, name: TreeSelection.describe(roots), afterward: afterward)
            }
        }
    }

    private func afterTrash(_ affected: [String], gone: (String) -> Bool, name: String, afterward: (() -> Void)? = nil) {
        treeSelection.prune { !gone($0) }
        snapshot?.refresh(paths: affected)
        recent.removeAll(where: gone)
        UserDefaults.standard.set(recent, forKey: key("recent"))
        func purge(_ h: inout [NavEntry], _ idx: inout Int) {
            var out: [NavEntry] = [], newIdx = idx
            for (i, e) in h.enumerated() {
                if case .note(let p) = e.place, gone(p) { if i <= idx { newIdx -= 1 }; continue }
                if let l = out.last, l.place == e.place { if i <= idx { newIdx -= 1 }; continue }   // A, ✕, A → A
                out.append(e)
            }
            h = out
            idx = out.isEmpty ? -1 : min(max(newIdx, 0), out.count - 1)
        }
        // unfocused panes
        if isSplit {
            for i in panes.indices.reversed() where i != focusedPane {
                var h = panes[i].history, hi = panes[i].historyIndex
                purge(&h, &hi)
                panes[i].history = h; panes[i].historyIndex = hi
                guard let p = panes[i].path, gone(p) else { continue }
                if panes[i].history.indices.contains(panes[i].historyIndex), case .note(let np) = panes[i].history[panes[i].historyIndex].place,
                   let n = snapshot?.notes[np] {
                    panes[i].path = np; panes[i].text = n.content
                } else {
                    panes.remove(at: i)
                    if i < focusedPane { focusedPane -= 1 }
                }
            }
            if panes.count <= 1 { panes = []; focusedPane = 0 }
        }
        // the focused pane
        purge(&history, &historyIndex)
        if let c = currentPath, gone(c) {
            speech.stop()
            currentPath = nil
            suppressTextChange = true; text = ""; lastSaved = ""; suppressTextChange = false
            if afterward == nil {
                if history.indices.contains(historyIndex), case .note = history[historyIndex].place { go(0) } else { openHome() }
            }
        }
        if let afterward { afterward(); return }
        let shown = name.hasSuffix(".md") ? String(name.dropLast(3)) : name
        toast = "Moved “\(shown)” to the Trash"
        vaultMutated("Delete \(shown)", paths: affected)
    }

    // MARK: Rename & move

    /// What "Move to…" is moving (a note, file or folder path).
    var moveSources: [String] = []
    var moveSource: String? { moveSources.first }
    func beginMove(_ path: String) { beginMove([path]) }
    func beginMove(_ paths: [String]) {
        moveSources = TreeSelection.roots(paths)
        guard !moveSources.isEmpty else { return }
        withAnimation(Motion.overlay) { overlay = .moveTo }
    }
    func beginMoveCurrent() { if let p = currentPath { beginMove(p) } }

    /// Folders for the Move to… picker ("" = vault root), minus where it already is and,
    /// for a folder, itself and everything under it.
    func moveDestinations(for path: String) -> [String] { moveDestinations(for: [path]) }
    func moveDestinations(for paths: [String]) -> [String] {
        let parents = Set(paths.map { ($0 as NSString).deletingLastPathComponent })
        let all = [""] + (snapshot?.folders.sorted() ?? [])
        return all.filter { f in
            !(parents.count == 1 && parents.contains(f))
                && !paths.contains { f == $0 || f.hasPrefix($0 + "/") }
                && !(f as NSString).lastPathComponent.hasPrefix(".")
        }
    }

    /// Move several items to one folder: each keeps its links and panes; one commit.
    func move(_ paths: [String], toFolder folder: String) {
        let roots = TreeSelection.roots(paths)
        guard roots.count > 1 else { if let p = roots.first { move(p, toFolder: folder) }; return }
        batchDepth += 1
        batchLinkDecision = nil
        defer { batchLinkDecision = nil }
        var moved: [String] = [], changed: [String] = []
        for p in roots where (p as NSString).deletingLastPathComponent != folder {
            let name = (p as NSString).lastPathComponent
            let dest = folder.isEmpty ? name : folder + "/" + name
            if relocate(p, to: dest, reason: "") { moved.append(p); changed += [p, dest] }
        }
        batchDepth -= 1
        treeSelection.clear()
        guard !moved.isEmpty else { return }
        let reason = "Move \(TreeSelection.describe(moved)) → \(folder.isEmpty ? "/" : folder)"
        toast = reason
        vaultMutated(reason, paths: changed)
    }
    /// >0 while a batch runs: structural changes are reported once, at the end.
    @ObservationIgnored private var batchDepth = 0
    /// The answer to "Update links?" for the rest of a multi-item move, so it's asked once.
    @ObservationIgnored private var batchLinkDecision: Bool? = nil

    /// Obsidian's "Automatically update internal links" (`alwaysUpdateLinks` in app.json):
    /// on, links follow silently; off or unset, ask first, like Obsidian does.
    func shouldUpdateLinks(_ plan: LinkUpdater.Plan, from: String, to dest: String) -> Bool {
        if promotingUntitled { return true }
        if (obsidianJSON("app.json") as? [String: Any])?["alwaysUpdateLinks"] as? Bool == true { return true }
        if let d = batchLinkDecision { return d }
        switch ProcessInfo.processInfo.environment["ONYX_UPDATE_LINKS"] {   // scripted runs can't answer a dialog
        case "update"?: return true
        case "skip"?: return false
        default: break
        }
        let n = plan.linkCount, m = plan.edits.count
        let a = NSAlert()
        a.messageText = "Update \(n) link\(n == 1 ? "" : "s") in \(m) file\(m == 1 ? "" : "s")?"
        let name = (from as NSString).lastPathComponent, newName = (dest as NSString).lastPathComponent
        a.informativeText = name == newName
            ? "“\(name)” is moving to \((dest as NSString).deletingLastPathComponent.isEmpty ? "the vault root" : (dest as NSString).deletingLastPathComponent)."
            : "“\(name)” is being renamed to “\(newName)”."
        a.addButton(withTitle: "Update")
        a.addButton(withTitle: "Don’t Update")
        a.addButton(withTitle: "Always Update")
        let r = a.runModal()
        let answer: Bool
        switch r {
        case .alertFirstButtonReturn: answer = true
        case .alertThirdButtonReturn:
            answer = true
            setObsidianConfig("app.json", ["alwaysUpdateLinks": true])
        default: answer = false
        }
        if batchDepth > 0 { batchLinkDecision = answer }
        return answer
    }

    func move(_ path: String, toFolder folder: String) {
        let name = (path as NSString).lastPathComponent
        let dest = folder.isEmpty ? name : folder + "/" + name
        let shown = name.lowercased().hasSuffix(".md") ? String(name.dropLast(3)) : name
        relocate(path, to: dest, reason: "Move \(shown) → \(folder.isEmpty ? "/" : folder)")
    }

    func confirmRename(_ path: String) {
        if sidebarVisible { startInlineRename(path) } else { promptRename(path) }
    }
    func confirmRenameCurrent() { if let p = currentPath { confirmRename(p) } }

    /// Finder-style in-row rename when the sidebar is showing.
    func startInlineRename(_ path: String) {
        if renamingPath != nil, renamingPath != path { cancelInlineRename() }
        if sidebarTab != .files { sidebarTab = .files }
        var parent = (path as NSString).deletingLastPathComponent
        while !parent.isEmpty { expanded.insert(parent); parent = (parent as NSString).deletingLastPathComponent }
        treeSelection.click(path)
        treeFocused = true
        renameDraft = InlineRename.fieldValue(path: path)
        renameError = nil
        renamingPath = path
        revealToken += 1
    }

    func commitInlineRename() {
        guard let path = renamingPath, let root else { return }
        let taken = { (dest: String) in
            FileManager.default.fileExists(atPath: root.appendingPathComponent(dest).path)
        }
        switch InlineRename.evaluate(path: path, typed: renameDraft, occupied: taken) {
        case .cancel:
            cancelInlineRename()
        case .invalid(let message), .collision(let message):
            renameError = message
        case .commit(let dest, let from, let to):
            cancelInlineRename()
            relocate(path, to: dest, reason: "Rename \(from) → \(to)")
        }
    }

    func cancelInlineRename() {
        renamingPath = nil
        renameDraft = ""
        renameError = nil
    }

    /// If `path` is part of a multi-selection, drag the selection’s roots; otherwise just `path`.
    func pathsForTreeDrag(from path: String) -> [String] {
        if treeSelection.contains(path), treeSelection.isMulti {
            return TreeSelection.roots(treeSelection.selected)
        }
        return [path]
    }

    func beginTreeDrag(_ paths: [String]) {
        draggingPaths = TreeSelection.roots(paths)
        dropTarget = nil
        dropForbidden = false
        TreeClickCatcher.Catcher.moving = true
    }

    @discardableResult
    func treeDragHover(on path: String, isFolder: Bool) -> Bool {
        guard !draggingPaths.isEmpty else { return false }
        let dest = TreeMove.destination(droppingOn: path, targetIsFolder: isFolder)
        switch treeMoveVerdict(toFolder: dest) {
        case .refuse, .collision:
            dropForbidden = true
            setDropTarget(dest, expand: false)
            return false
        case .none, .move:
            dropForbidden = false
            setDropTarget(dest, expand: true)
            return true
        }
    }

    func performTreeDrop(on path: String, isFolder: Bool) {
        let dest = TreeMove.destination(droppingOn: path, targetIsFolder: isFolder)
        switch treeMoveVerdict(toFolder: dest) {
        case .none:
            break
        case .refuse(let message), .collision(let message):
            toast = message
        case .move(let sources):
            move(sources, toFolder: dest)
        }
        endTreeDrag()
    }

    func endTreeDrag() {
        dropExpandTask?.cancel()
        dropExpandTask = nil
        draggingPaths = []
        dropTarget = nil
        dropForbidden = false
        TreeClickCatcher.Catcher.moving = false
    }

    private func treeMoveVerdict(toFolder dest: String) -> TreeMove.Verdict {
        TreeMove.verdict(sources: draggingPaths, toFolder: dest, occupied: { pathOccupied($0) })
    }

    private func pathOccupied(_ dest: String) -> Bool {
        if let root {
            return FileManager.default.fileExists(atPath: root.appendingPathComponent(dest).path)
        }
        return snapshot?.notes[dest] != nil
            || snapshot?.folders.contains(dest) == true
            || snapshot?.attachments[dest] != nil
    }

    private func setDropTarget(_ folder: String?, expand: Bool) {
        let changed = dropTarget != folder
        dropTarget = folder
        guard expand, changed, let f = folder, !f.isEmpty, !expanded.contains(f) else { return }
        dropExpandTask?.cancel()
        dropExpandTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled, dropTarget == f else { return }
            _ = withAnimation(Motion.quick) { expanded.insert(f) }
        }
    }

    /// Used when the sidebar is hidden, so there's no row to edit in place.
    func promptRename(_ path: String) {
        guard let root else { return }
        let isDir = (try? root.appendingPathComponent(path).resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let a = NSAlert()
        a.messageText = isDir ? "Rename folder" : "Rename"
        a.informativeText = "Links to it across the vault are updated."
        let field = NSTextField(string: InlineRename.fieldValue(path: path))
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        a.accessoryView = field
        a.addButton(withTitle: "Rename"); a.addButton(withTitle: "Cancel")
        a.window.initialFirstResponder = field
        guard a.runModal() == .alertFirstButtonReturn else { return }
        switch InlineRename.evaluate(path: path, typed: field.stringValue, occupied: {
            FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path)
        }) {
        case .cancel:
            return
        case .invalid(let message), .collision(let message):
            toast = message
        case .commit(let dest, let from, let to):
            relocate(path, to: dest, reason: "Rename \(from) → \(to)")
        }
    }

    /// Move or rename a note, file or folder. `LinkUpdater` works out every link that has to follow
    /// (wikilinks, embeds, Markdown links, frontmatter, canvas cards); with `alwaysUpdateLinks` off
    /// the user is asked first. The note stays open in its panes and history. One commit, right
    /// away, via `vaultMutated`.
    @discardableResult
    func relocate(_ from: String, to dest: String, reason: String) -> Bool {
        guard let root, snapshot != nil else { return false }
        let fm = FileManager.default
        let src = root.appendingPathComponent(from), dst = root.appendingPathComponent(dest).standardizedFileURL
        guard dst.path.hasPrefix(root.path + "/"), !dest.contains("..") else { return false }
        if fm.fileExists(atPath: dst.path), from.lowercased() != dest.lowercased() {
            toast = "“\((dest as NSString).lastPathComponent)” already exists there"; return false
        }
        flushSave()
        guard var snap = snapshot else { return false }   // after the save, so the open note's latest text is what's rewritten
        // every link edit the move needs, worked out from the vault as it is now
        let format = Attachments.Settings(appJSON: obsidianJSON("app.json") as? [String: Any] ?? [:]).linkFormat
        let plan = LinkUpdater.plan(snap, from: from, to: dest, linkFormat: format) { c in
            try? String(contentsOf: root.appendingPathComponent(c), encoding: .utf8)
        }
        let map = plan.noteMoves
        var edited: [String] = []
        let update = plan.isEmpty ? true : shouldUpdateLinks(plan, from: from, to: dest)
        if update {
            for e in plan.edits {
                if e.path == currentPath, e.path.isCanvasPath, isDirty { continue }   // never write under unsaved canvas edits
                guard write(e.text, to: e.path, create: false) else { continue }
                snap.update(path: e.path, content: e.text); edited.append(e.path)
                if e.path == currentPath { suppressTextChange = true; self.text = e.text; lastSaved = e.text; suppressTextChange = false; renderToken += 1 }
                for i in panes.indices where i != focusedPane && panes[i].path == e.path { panes[i].text = e.text }   // other split panes stay in sync
            }
        }
        do {
            try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            if from.lowercased() == dest.lowercased() {   // case-only rename on a case-insensitive disk
                let tmp = src.deletingLastPathComponent().appendingPathComponent(".onyx-rename-\(UUID().uuidString)")
                try fm.moveItem(at: src, to: tmp); try fm.moveItem(at: tmp, to: dst)
            } else {
                try fm.moveItem(at: src, to: dst)
            }
        } catch {
            toast = "Couldn’t move: \(error.localizedDescription)"
            snapshot = snap
            return false
        }
        snap.refresh(paths: Array(plan.fileMoves.keys) + Array(plan.fileMoves.values) + [from, dest] + edited)
        snapshot = snap
        // keep it open everywhere
        func remap(_ p: String) -> String { plan.fileMoves[p] ?? p }   // an open attachment viewer follows too
        func remapHistory(_ h: [NavEntry]) -> [NavEntry] {
            h.map { e in var e = e; if case .note(let p) = e.place { e.place = .note(remap(p)) }; return e }
        }
        if let c = currentPath { currentPath = remap(c) }
        history = remapHistory(history)
        for i in panes.indices {
            panes[i].history = remapHistory(panes[i].history)
            if let p = panes[i].path { panes[i].path = remap(p) }
        }
        recent = recent.map(remap); UserDefaults.standard.set(recent, forKey: key("recent"))
        if treeOrder.overrides.keys.contains(where: { $0 == from || $0.hasPrefix(from + "/") }) {   // per-folder sort follows the folder
            var o = treeOrder.overrides
            for (k, v) in treeOrder.overrides where k == from || k.hasPrefix(from + "/") { o[k] = nil; o[dest + String(k.dropFirst(from.count))] = v }
            treeOrder.overrides = o
        }
        bookmarks = bookmarks.map(remap); UserDefaults.standard.set(bookmarks, forKey: key("bookmarks"))
        foldStore?.remapPaths(map)   // folds follow the note
        var parent = (dest as NSString).deletingLastPathComponent
        while !parent.isEmpty { expanded.insert(parent); parent = (parent as NSString).deletingLastPathComponent }
        if !update { toast = "\(reason) · links not updated" }
        else if edited.isEmpty { toast = reason } else { toast = "\(reason) · updated links in \(edited.count) note\(edited.count == 1 ? "" : "s")" }
        vaultMutated(reason, paths: [from, dest] + edited)
        return true
    }

    /// Structural changes (delete, rename, move) land here so git can commit them right away.
    func vaultMutated(_ message: String, paths: [String]) {
        guard batchDepth == 0 else { return }
        chromeLog("vault: \(message) \(paths.count) path(s)")
        git?.commitNow(reason: message)
        obsidianSync?.edited()
    }

    // MARK: Editing & saving

    private func settle() {
        settleTask?.cancel()
        if suppressTextChange || currentPath == nil || text.utf16.count < Self.liveStatsLimit { settledText = text; return }
        settleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self, !Task.isCancelled else { return }
            self.settledText = self.text
        }
    }

    private func textDidChange() {
        guard !suppressTextChange, currentPath != nil else { return }
        editedSinceLint = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    /// True while an Untitled note is being renamed from its title, so `relocate`'s
    /// own `flushSave()` doesn't recurse back into promotion.
    private var promotingUntitled = false

    func flushSave() {
        saveTask?.cancel()
        if isDirty { save() }
        if !promotingUntitled { promoteUntitledIfNeeded() }
    }

    /// After an explicit save (⌘S, leaving the note, Save and Read), rename a still-Untitled
    /// note from its first heading so it lands in the sidebar under a real name. Autosave
    /// writes the bytes but leaves the placeholder name alone while the title is still being typed.
    func promoteUntitledIfNeeded() {
        guard let path = currentPath, NoteNaming.isUntitled(path) else { return }
        guard let title = NoteNaming.title(fromContent: text) else { return }
        let folder = (path as NSString).deletingLastPathComponent
        let dest = NoteNaming.dest(folder: folder, title: title) { candidate in
            if candidate == path { return false }
            if snapshot?.notes[candidate] != nil { return true }
            return FileManager.default.fileExists(atPath: root?.appendingPathComponent(candidate).path ?? "")
        }
        guard dest != path else { return }
        promotingUntitled = true
        defer { promotingUntitled = false }
        relocate(path, to: dest, reason: "Rename Untitled → \(((dest as NSString).lastPathComponent as NSString).deletingPathExtension)")
    }

    /// Conflict-safe save. If the file changed on disk since we loaded it
    /// (Obsidian Sync, git, another bot) we never overwrite it blindly.
    func save() {
        guard let path = currentPath, let root, isDirty, !path.opensInFileView else { return }   // never write text over an attachment
        let url = root.appendingPathComponent(path)
        if let disk = try? String(contentsOf: url, encoding: .utf8), disk != lastSaved, disk != text {
            conflict = disk
            return
        }
        if write(text, to: path, create: false) {
            lastSaved = text
            snapshot?.update(path: path, content: text)
        }
    }

    func resolveConflict(keepMine: Bool) {
        guard let disk = conflict, let path = currentPath else { return }
        if keepMine {
            // Keep both: their version becomes a sibling copy, ours wins the path.
            let ext = (path as NSString).pathExtension
            let copy = (path as NSString).deletingPathExtension + " (conflict \(Self.stamp())).\(ext.isEmpty ? "md" : ext)"
            _ = write(disk, to: copy, create: true)
            lastSaved = disk   // allow overwrite
            conflict = nil
            save()
            toast = "Their version saved as “\((copy as NSString).lastPathComponent)”"
        } else {
            suppressTextChange = true
            text = disk; lastSaved = disk
            suppressTextChange = false
            conflict = nil
            snapshot?.update(path: path, content: disk)
            renderToken += 1
        }
    }

    static func stamp() -> String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HHmm"; return f.string(from: Date()) }

    /// The only place Onyx writes files. Refuses anything outside the vault.
    @discardableResult
    func write(_ content: String, to rel: String, create: Bool) -> Bool {
        guard let root else { return false }
        let url = root.appendingPathComponent(rel).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/"), !rel.contains("..") else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if create && FileManager.default.fileExists(atPath: url.path) { return false }
            try Data(content.utf8).write(to: url, options: .atomic)
            if create { snapshot?.refresh(paths: [rel]) }
            git?.edited()
            obsidianSync?.edited()
            return true
        } catch {
            toast = "Couldn’t save: \(error.localizedDescription)"
            return false
        }
    }

    /// Toggle the n-th task checkbox (document order, outside code) from reading view.
    /// A Kanban board edit from the reader; the file is spliced (see KanbanDoc), then saved.
    @discardableResult
    func kanbanEdit(_ b: [String: Any]) -> Bool {
        var d = KanbanDoc(text)
        let lane = b["lane"] as? Int ?? -1, card = b["card"] as? Int ?? -1
        let ok: Bool
        switch b["op"] as? String {
        case "toggle": ok = d.toggle(lane: lane, card: card)
        case "move": ok = d.move(lane: lane, card: card, toLane: b["toLane"] as? Int ?? -1, index: b["index"] as? Int ?? 0)
        case "add": ok = d.add(lane: lane, text: b["text"] as? String ?? "")
        case "edit": ok = d.edit(lane: lane, card: card, text: b["text"] as? String ?? "")
        case "archive": ok = d.archive(lane: lane, card: card)
        case "collapse": ok = d.setCollapsed(lane: lane, b["on"] as? Bool ?? true)
        case "collapseOthers": ok = d.setCollapsed(d.lanes.indices.map { $0 != lane })
        case "expandAll": ok = d.setCollapsed(d.lanes.map { _ in false })
        default: ok = false
        }
        if ok { text = d.text; flushSave() } else { renderToken += 1 }   // a no-op still redraws (drops an open editor)
        return ok
    }

    /// Drag-to-resize from the reader: set (or, with nil, remove) the `|width` on one embed occurrence
    /// (see ImageSize.edit). Goes through the editor's text system when it holds this note, so ⌘Z undoes it.
    func resizeEmbed(line: Int, lines: Int, kind: String, target: String, occurrence: Int, width: Int?) {
        guard !isCanvas, !isBase, !isFile,
              let e = ImageSize.edit(in: text, line: line, lines: lines, kind: kind, target: target, occurrence: occurrence, width: width) else { renderToken += 1; return }
        let new = (text as NSString).replacingCharacters(in: e.range, with: e.replacement)
        guard new != text else { return }
        if let tv = liveEditor, tv.string == text, tv.isEditable, tv.shouldChangeText(in: e.range, replacementString: e.replacement) {
            tv.breakUndoCoalescing()
            tv.replaceCharacters(in: e.range, with: e.replacement)
            tv.didChangeText()
            tv.undoManager?.setActionName(width == nil ? "Reset Image Size" : "Resize Image")
            tv.breakUndoCoalescing()
        }
        text = new
        flushSave()
    }

    func toggleTask(index: Int) {
        let lines = text.components(separatedBy: "\n")
        var out = lines
        var n = 0
        var inFence = false
        let fm = Frontmatter.parse(text)
        for (i, line) in lines.enumerated() where i >= fm.lineCount {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") || t.hasPrefix("~~~") { inFence.toggle(); continue }
            if inFence { continue }
            if let r = line.range(of: #"^\s*([-*+]|\d+[.)])\s+\[( |x|X)\]"#, options: .regularExpression) {
                if n == index {
                    let seg = String(line[r])
                    let flipped = seg.hasSuffix("[ ]") ? String(seg.dropLast(3)) + "[x]" : String(seg.dropLast(3)) + "[ ]"
                    out[i] = flipped + line[r.upperBound...]
                    break
                }
                n += 1
            }
        }
        text = out.joined(separator: "\n")
        flushSave()
    }

    /// Toggle a task in any vault note, including files that aren't open. Uses the same
    /// write path as other edits so git and Obsidian Sync see the change.
    func toggleDataviewTask(path: String, index: Int) {
        if path == currentPath {
            toggleTask(index: index)
            return
        }
        guard let root else { return }
        let url = root.appendingPathComponent(path)
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? snapshot?.notes[path]?.content
        guard let text, let next = Dataview.toggleTask(in: text, index: index) else { return }
        if write(next, to: path, create: false) {
            snapshot?.refresh(paths: [path])
            renderToken += 1
        }
    }


    // MARK: External changes

    private func filesChanged(_ paths: [String]) {
        let config = paths.filter { $0.hasPrefix(".obsidian/") }
        if !config.isEmpty { obsidianConfigChanged(config.map { ($0 as NSString).lastPathComponent }) }
        let paths = paths.filter { !$0.hasPrefix(".obsidian/") }
        if paths.isEmpty { return }
        pendingPaths.formUnion(paths)
        reindexTask?.cancel()
        reindexTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard let self, !Task.isCancelled else { return }
            let batch = Array(self.pendingPaths); self.pendingPaths.removeAll()
            self.applyExternal(batch)
        }
    }

    private func applyExternal(_ paths: [String]) {
        guard var snap = snapshot, let root else { return }
        var external = false
        // Our own saves come back as FSEvents too. A note whose bytes on disk are what the
        // index already holds needs no re-read, and a batch of only those needs no new snapshot.
        var stale: [String] = []
        for p in paths where p.lowercased().hasSuffix(".md") || p.isCanvasPath || p.isBasePath {
            let disk = try? String(contentsOf: root.appendingPathComponent(p), encoding: .utf8)
            let md = p.lowercased().hasSuffix(".md")
            if !md || disk == nil || snap.notes[p]?.content != disk { stale.append(p) }
            if p == currentPath {
                if let disk, disk != lastSaved {
                    external = true
                    if !isDirty {
                        suppressTextChange = true
                        text = disk; lastSaved = disk
                        suppressTextChange = false
                        renderToken += 1
                    } else if disk != text { conflict = disk }
                }
            } else if !p.isCanvasPath, !p.isBasePath, snap.notes[p]?.content != disk { external = true }
        }
        let others = paths.filter { !($0.lowercased().hasSuffix(".md") || $0.isCanvasPath || $0.isBasePath) }
        if !stale.isEmpty || !others.isEmpty {
            snap.refresh(paths: stale + others)
            snapshot = snap
        }
        if let cur = currentPath, snap.notes[cur] == nil, snap.canvases[cur] == nil, snap.bases[cur] == nil, snap.attachments[cur] == nil, !FileManager.default.fileExists(atPath: root.appendingPathComponent(cur).path) {
            toast = "“\((cur as NSString).lastPathComponent)” was moved or deleted elsewhere"
        }
        if external { externalPulse = Date(); lastExternalChange = Date(); git?.edited() }
        obsidianSync?.edited()
    }

    func reindex() { if let root { let cur = currentPath; open(vault: root, initialNote: cur) } }

    // MARK: Chrome

    func toggleSidebar(_ tab: SidebarTab? = nil) {
        withAnimation(Motion.layout) {
            if let tab, sidebarVisible, sidebarTab != tab { sidebarTab = tab; return }
            if let tab { sidebarTab = tab }
            sidebarVisible.toggle()
            sidebarPinned = true
            if sidebarVisible { focusMode = false }
        }
        UserDefaults.standard.set(sidebarVisible, forKey: "onyx.sidebarOpen")
    }
    /// ⌥⌘I and the footer button: show the inspector docked, or put it away. Remembered across launches.
    func toggleInspector(_ tab: InspectorTab? = nil) {
        withAnimation(Motion.layout) {
            if let tab, inspectorVisible, inspectorTab != tab { inspectorTab = tab; return }
            if let tab { inspectorTab = tab }
            if inspectorVisible { hideInspector(animated: false) }
            else { if focusMode { toggleFocusMode() }; inspectorVisible = true; inspectorPinned = true; persistInspector() }
        }
    }
    func hideInspector(animated: Bool = true) {
        let body = { self.inspectorVisible = false; self.inspectorPinned = false }
        if animated { withAnimation(Motion.layout, body) } else { body() }
        persistInspector()
    }
    func persistInspector() { UserDefaults.standard.set(inspectorVisible && inspectorPinned, forKey: "onyx.inspectorOpen") }
    func show(_ o: Overlay) {
        withAnimation(Motion.overlay) { overlay = overlay == o ? .none : o }
    }

    /// Open the graph overlay, or close it if that same graph is already showing.
    /// A focus-graph request (⌘G, the title-bar button) closes any open graph overlay
    /// and returns to the note. An atlas request (⇧⌘G, shift-click) switches to the
    /// atlas if the focus graph is showing, and closes the overlay if the atlas already is.
    func toggleGraph(atlas: Bool) {
        if overlay == .graph, !atlas || graphAtlas {
            show(.none)
            return
        }
        graphAtlas = atlas
        if overlay != .graph { show(.graph) }
    }

    /// Apply Esc according to `EscPrecedence`. Returns true if the event should be swallowed.
    @discardableResult
    func handleEscape(eventWindow: NSWindow?) -> Bool {
        let action = EscPrecedence.action(escapeSituation(eventWindow: eventWindow))
        switch action {
        case .passToSheet, .passToIME, .dismissSuggestions, .none:
            return false
        case .closeFind:
            closeFind()
            return true
        case .dismissOverlay, .dismissUnpinnedInspector, .dismissUnpinnedSidebar, .dismissInspector, .leaveFocusMode:
            return dismissTop()
        case .cancelInlineRename:
            cancelInlineRename()
            return true
        case .clearTreeSelection:
            return clearTreeSelection()
        case .collapseSelection:
            let tv = (MainWindow.current?.firstResponder as? OnyxTextView) ?? liveEditor
            tv?.collapseSelectionOrCursors()
            return true
        case .returnToReading:
            returnToReading()
            return true
        }
    }

    func escapeSituation(eventWindow: NSWindow?) -> EscSituation {
        let tv = MainWindow.current?.firstResponder as? OnyxTextView
        let anyTV = (NSApp.keyWindow?.firstResponder as? NSTextView)
            ?? (eventWindow?.firstResponder as? NSTextView)
        let ranges = tv?.selectedRanges.map { $0.rangeValue } ?? []
        return EscSituation(
            sheetOrAlert: escapeIsBlockedBySheet(eventWindow),
            hasMarkedText: anyTV?.hasMarkedText() == true,
            suggestionsVisible: tv?.suggestionsVisible == true,
            renaming: renamingPath != nil,
            findVisible: finder.visible,
            overlayOpen: overlay != .none,
            treeSelectionConsumes: sidebarVisible && treeSelection.isMulti,
            unpinnedInspector: inspectorVisible && !inspectorPinned,
            unpinnedSidebar: sidebarVisible && !sidebarPinned,
            inspectorVisible: inspectorVisible,
            focusMode: focusMode,
            editorFocused: tv != nil,
            hasSelectionOrMultiCursor: ranges.count > 1 || ranges.contains(where: { $0.length > 0 }),
            modeIsEdit: mode == .edit,
            escReturnsToReading: Prefs.escReturnsToReading
        )
    }

    /// A confirm, Settings, or other window that's not the main Onyx window owns Esc.
    private func escapeIsBlockedBySheet(_ eventWindow: NSWindow?) -> Bool {
        if NSApp.modalWindow != nil { return true }
        if let w = NSApp.keyWindow, w !== MainWindow.current { return true }
        if let w = eventWindow, w !== MainWindow.current { return true }
        if MainWindow.current?.attachedSheet != nil { return true }
        return false
    }

    /// Esc: peel back one floating layer (overlays, then summoned panels).
    func dismissTop() -> Bool {
        let anim = Motion.layout
        if overlay != .none { withAnimation(anim) { overlay = .none }; return true }
        if inspectorVisible && !inspectorPinned { hideInspector(); return true }
        if sidebarVisible && !sidebarPinned { withAnimation(anim) { sidebarVisible = false }; return true }
        if inspectorVisible { hideInspector(); return true }      // Esc puts a docked inspector away too
        if focusMode { toggleFocusMode(); return true }
        return false
    }

    /// ⌘K: show or hide the file sidebar, remembered across launches. Always docked.
    func toggleDockedSidebar(_ tab: SidebarTab? = nil) {
        withAnimation(Motion.layout) {
            if let tab, sidebarVisible, sidebarTab != tab { sidebarTab = tab; return }
            if let tab { sidebarTab = tab }
            sidebarVisible.toggle()
            sidebarPinned = true
            if sidebarVisible { focusMode = false }
        }
        UserDefaults.standard.set(sidebarVisible, forKey: "onyx.sidebarOpen")
    }

    private var preFocus: (Bool, Bool, Bool, Bool)?
    /// ⌃⌘F: pure text. Everything else steps aside; the same keys bring it back.
    func toggleFocusMode() {
        withAnimation(Motion.layout) {
            if focusMode {
                focusMode = false
                if let p = preFocus { sidebarVisible = p.0; sidebarPinned = true; inspectorVisible = p.2; inspectorPinned = p.3 }
            } else {
                preFocus = (sidebarVisible, true, inspectorVisible, inspectorPinned)
                focusMode = true
                sidebarVisible = false; inspectorVisible = false; overlay = .none
            }
        }
    }

    func dismissHints() { withAnimation(.easeOut(duration: 0.2)) { showHints = false }; UserDefaults.standard.set(true, forKey: "onyx.hintsDismissed") }
    func toggleWorkspaceLayout() {
        withAnimation(Motion.layout) {
            let on = !(sidebarVisible && inspectorPinned && inspectorVisible)
            sidebarVisible = on
            sidebarPinned = true
            inspectorPinned = on
            inspectorVisible = on
            if on { focusMode = false }
        }
        UserDefaults.standard.set(sidebarVisible, forKey: "onyx.sidebarOpen")
        persistInspector()
    }
    func toggleMode() {
        if mode == .edit { lintOnSave() }
        flushSave()
        withAnimation(Motion.fade) { mode = mode == .read ? .edit : .read }
    }
    /// Esc (when nothing else is open): save and show the reader. Never the other way.
    func returnToReading() {
        guard mode == .edit else { return }
        lintOnSave()
        flushSave()
        withAnimation(Motion.fade) { mode = .read }
    }
    func toggleBookmark() {
        guard let p = currentPath else { return }
        if bookmarks.contains(p) { bookmarks.removeAll { $0 == p } } else { bookmarks.append(p) }
        UserDefaults.standard.set(bookmarks, forKey: key("bookmarks"))
    }

    // MARK: Read aloud

    /// Speaks the current selection, or the whole note if there isn't one.
    func readAloud() {
        guard currentPath != nil, !isCanvas, !isBase, !isFile else {
            toast = "Nothing to read"
            return
        }
        if let sel = selectedEditorText() {
            startSpeaking(sel)
            return
        }
        if mode == .read, let reader = liveReader {
            reader.selectedText { [weak self] raw in
                Task { @MainActor in
                    guard let self else { return }
                    let sel = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !sel.isEmpty { self.startSpeaking(sel) }
                    else { self.speakCurrentNote() }
                }
            }
            return
        }
        speakCurrentNote()
    }

    /// Closing the vault window (not quitting): save, stop playback, keep Sync and git running.
    func prepareForWindowClose() {
        let plan = WindowLifecycle.closePlan(kind: .vault, isQuit: false)
        if plan.flushUnsavedNotes { flushSave() }
        if plan.persistSplitLayout { persistSplitLayout() }
        if plan.stopSpeech { speech.stop() }
        if plan.finishRecording, recorder.isRecording { stopRecording() }
        if plan.stopAudioPlayback {
            NotificationCenter.default.post(name: WindowLifecycle.stopPlaybackNotification, object: nil)
        }
    }

    func toggleSpeechPause() { if speech.isActive { speech.togglePause() } }

    func stopSpeech() { speech.stop() }

    private func selectedEditorText() -> String? {
        let tv = (MainWindow.current?.firstResponder as? OnyxTextView) ?? liveEditor
        guard let tv else { return nil }
        let r = tv.selectedRange()
        guard r.length > 0, r.location != NSNotFound else { return nil }
        let ns = tv.string as NSString
        guard NSMaxRange(r) <= ns.length else { return nil }
        let sel = ns.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
        return sel.isEmpty ? nil : sel
    }

    private func speakCurrentNote() {
        startSpeaking(text)
    }

    private func startSpeaking(_ markdown: String) {
        let prose = SpeechText.clean(markdown)
        if prose.isEmpty {
            toast = "Nothing to read"
            return
        }
        speech.speak(prose)
    }

    func revealInFinder() { if let p = currentPath { revealInFinder(p) } }
    func revealInFinder(_ p: String) { if let root { NSWorkspace.shared.activateFileViewerSelecting([root.appendingPathComponent(p)]) } }
    func openInObsidian() { if let p = currentPath { openInObsidian(p) } }
    func openInObsidian(_ p: String) {
        guard let root else { return }
        var c = URLComponents(); c.scheme = "obsidian"; c.host = "open"
        c.queryItems = [URLQueryItem(name: "vault", value: root.lastPathComponent), URLQueryItem(name: "file", value: p)]
        if let u = c.url { NSWorkspace.shared.open(u) }
    }
    /// Title-path click: open the folder's note if it has one (folder-notes convention),
    /// then dock the sidebar on Files, expand down to the folder, select and scroll to it.
    func revealFolder(_ folder: String) {
        let note = folder + "/" + (folder as NSString).lastPathComponent + ".md"
        if snapshot?.notes[note] != nil, currentPath != note { openNote(note) }
        withAnimation(Motion.layout) {
            focusMode = false
            sidebarTab = .files
            if !sidebarVisible || !sidebarPinned {
                sidebarVisible = true; sidebarPinned = true
                UserDefaults.standard.set(true, forKey: "onyx.sidebarOpen")
            }
            var p = folder
            while !p.isEmpty { expanded.insert(p); p = (p as NSString).deletingLastPathComponent }
            selectedFolder = folder
        }
        revealToken += 1
    }

    func copyWikilink() {
        guard let n = currentNote else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString("[[\(n.name)]]", forType: .string)
        toast = "Copied [[\(n.name)]]"
    }
}


func chromeLog(_ s: String) {
    guard ProcessInfo.processInfo.environment["ONYX_DEBUG"] != nil else { return }
    let st = Thread.callStackSymbols.dropFirst(2).prefix(6).map { l in l.split(separator: " ", omittingEmptySubsequences: true).dropFirst(3).first.map(String.init) ?? l }
    FileHandle.standardError.write("[chrome] \(s)  ← \(st.joined(separator: " ← "))\n".data(using: .utf8)!)
}


struct Pane: Identifiable, Equatable {
    let id: UUID
    var path: String?
    var text: String
    var mode: ViewMode
    var history: [NavEntry] = []
    var historyIndex = -1
    /// A docked graph: lives beside notes and stays open; never takes the editor's focus.
    var isGraph = false
}

/// One stop in back/forward: a note (with where you were in it and how you were viewing it)
/// or the graph.
struct NavEntry: Equatable {
    enum Place: Equatable { case note(String), graph(atlas: Bool) }
    var place: Place
    var top: Double = 0
    var mode: ViewMode? = nil
}

struct ScrollRequest: Equatable { var line: Double; var id: Int }

/// .vertical = side by side (⌘D), .horizontal = stacked (⇧⌘D), as in iTerm and VS Code.
enum SplitAxis { case vertical, horizontal }

extension Workspace {
    var isSplit: Bool { panes.count > 1 }

    private func captureFocused() {
        guard panes.indices.contains(focusedPane) else { return }
        panes[focusedPane].path = currentPath
        panes[focusedPane].text = text
        panes[focusedPane].mode = mode
        saveHistoryPlace()
        panes[focusedPane].history = history
        panes[focusedPane].historyIndex = historyIndex
        paneTop[panes[focusedPane].id] = liveTop
    }

    /// Scroll report from a view; `pane` is nil for the focused (live) pane.
    func reportTop(_ pane: UUID?, _ line: Double) {
        if let pane { paneTop[pane] = line } else { liveTop = line }
        if ProcessInfo.processInfo.environment["ONYX_DEBUG"] != nil {
            FileHandle.standardError.write("[top] \(pane.map { String($0.uuidString.prefix(4)) } ?? "live") \(String(format: "%.2f", line)) \(mode)\n".data(using: .utf8)!)
        }
    }
    /// Where a newly created view should open.
    func initialTop(_ pane: UUID?) -> Double { pane.map { paneTop[$0] ?? 0 } ?? liveTop }

    /// ⌘D / ⇧⌘D: split the focused pane; the new pane shows the same note and takes focus.
    func split(_ axis: SplitAxis) {
        flushSave()
        if panes.isEmpty { panes = [Pane(id: UUID(), path: currentPath, text: text, mode: mode, history: history, historyIndex: historyIndex)]; focusedPane = 0 }
        guard panes.count < 4 else { toast = "Four panes is the limit"; return }
        captureFocused()
        withAnimation(Motion.layout) {
            splitAxis = axis
            // like duplicating a browser tab, the new pane starts with the same history
            let fresh = Pane(id: UUID(), path: currentPath, text: text, mode: mode, history: history, historyIndex: historyIndex)
            paneTop[fresh.id] = liveTop   // the new pane opens where the source pane is
            paneRatios = PaneRatios.splitting(paneRatios.isEmpty ? [1] : paneRatios, at: focusedPane)
            panes.insert(fresh, at: focusedPane + 1)
            focusedPane += 1
            // A graph that was over the solo page stays on the source pane, not the new one.
            if overlay == .graph, graphOverlayPaneID == nil || !panes.contains(where: { $0.id == graphOverlayPaneID }) {
                graphOverlayPaneID = panes[focusedPane - 1].id
            }
        }
        chromeLog("split \(axis) panes=\(panes.count) focused=\(focusedPane)")
        persistSplitLayout()
    }

    /// Click or ⌃⇥: hand the live editor state to another pane.
    func focusPane(_ i: Int) {
        guard isSplit, panes.indices.contains(i), i != focusedPane, !panes[i].isGraph else { return }
        flushSave()
        captureFocused()
        focusedPane = i
        let p = panes[i]
        if let path = p.path, path != currentPath { openNote(path, recordHistory: false) }
        history = p.history; historyIndex = p.historyIndex
        liveTop = paneTop[p.id] ?? 0
        mode = p.mode
        chromeLog("focusPane \(i) → \(currentPath ?? "-") \(mode)")
        persistSplitLayout()
    }
    func focusNextPane(_ step: Int = 1) {
        guard isSplit else { return }
        var j = focusedPane
        for _ in panes.indices {
            j = (j + step + panes.count) % panes.count
            if !panes[j].isGraph { break }
        }
        focusPane(j)
    }

    var graphPaneIndex: Int? { panes.firstIndex(where: \.isGraph) }
    /// The graph as a pane beside the notes (focus graph follows the note you're on).
    func openGraphPane(atlas: Bool) {
        graphAtlas = atlas
        if overlay == .graph { withAnimation(Motion.overlay) { overlay = .none } }
        guard graphPaneIndex == nil else { return }
        flushSave()
        if panes.isEmpty { panes = [Pane(id: UUID(), path: currentPath, text: text, mode: mode, history: history, historyIndex: historyIndex)]; focusedPane = 0 }
        guard panes.count < 4 else { toast = "Four panes is the limit"; return }
        captureFocused()
        withAnimation(Motion.layout) {
            if panes.count == 1 { splitAxis = .vertical }
            paneRatios = PaneRatios.splitting(paneRatios.isEmpty ? [1] : paneRatios, at: panes.count - 1)
            panes.append(Pane(id: UUID(), path: nil, text: "", mode: mode, isGraph: true))
        }
        persistSplitLayout()
    }
    func closeGraphPane() {
        guard let g = graphPaneIndex else { return }
        captureFocused()
        withAnimation(Motion.layout) {
            paneRatios = PaneRatios.removing(paneRatios, at: g)
            panes.remove(at: g)
            if focusedPane > g { focusedPane -= 1 }
            focusedPane = min(focusedPane, max(0, panes.count - 1))
            if panes.count <= 1 { panes = []; focusedPane = 0; paneRatios = [] }
        }
        persistSplitLayout()
    }

    /// ⌘W with panes: close the focused one. Returns false when there is nothing to close
    /// (one pane), so ⌘W falls through to closing the window.
    @discardableResult
    func closePane() -> Bool {
        guard isSplit else { return false }
        // ⌘W with one note beside a docked graph closes the graph, never the last note
        if panes.filter({ !$0.isGraph }).count == 1, graphPaneIndex != nil { closeGraphPane(); return true }
        flushSave()
        withAnimation(Motion.layout) {
            paneRatios = PaneRatios.removing(paneRatios, at: focusedPane)
            panes.remove(at: focusedPane)
            focusedPane = min(focusedPane, panes.count - 1)
            if panes[focusedPane].isGraph, let n = panes.indices.filter({ !panes[$0].isGraph }).min(by: { abs($0 - focusedPane) < abs($1 - focusedPane) }) { focusedPane = n }
            if overlay == .graph, let id = graphOverlayPaneID, !panes.contains(where: { $0.id == id }) {
                overlay = .none
            }
        }
        let p = panes[focusedPane]
        if let path = p.path, path != currentPath { openNote(path, recordHistory: false) }
        history = p.history; historyIndex = p.historyIndex
        liveTop = paneTop[p.id] ?? liveTop
        mode = p.mode
        if panes.count <= 1 { panes = []; focusedPane = 0; paneRatios = [] }
        chromeLog("closePane → panes=\(panes.count) \(currentPath ?? "-")")
        persistSplitLayout()
        return true
    }

    /// Text an unfocused pane should show: live text if it's the same note as the focused pane.
    func displayText(_ p: Pane) -> String { p.path != nil && p.path == currentPath ? text : p.text }

    /// Point sizes along the split axis for the current ratios.
    func paneSizes(along total: CGFloat) -> [CGFloat] {
        PaneRatios.sizes(paneRatios, count: panes.count, total: Double(total)).map { CGFloat($0) }
    }

    func setPaneRatios(_ ratios: [Double]) {
        guard panes.count > 1 else { return }
        paneRatios = PaneRatios.normalized(ratios, count: panes.count)
        persistSplitLayout()
    }

    func equalizePanes() {
        guard panes.count > 1 else { return }
        withAnimation(Motion.layout) {
            paneRatios = PaneRatios.equal(panes.count)
        }
        persistSplitLayout()
    }

    /// Drag the divider between pane `divider` and the next. `from` is the ratio snapshot
    /// at mouse-down so each translation is applied from a stable start.
    func resizePanes(from start: [Double], divider: Int, delta: CGFloat, total: CGFloat) {
        guard panes.count > 1 else { return }
        paneRatios = PaneRatios.dragging(start, divider: divider, delta: Double(delta), total: Double(total))
    }

    /// Write this vault's split (axis, ratios, open notes) to defaults, or clear it when there's one pane.
    /// No-op under screenshot/test hooks and for /tmp vaults, which share the installed app's defaults.
    func persistSplitLayout() {
        guard let path = root?.path, SessionPersistence.isEnabled(vaultPath: path) else { return }
        if !isSplit {
            UserDefaults.standard.removeObject(forKey: key("splitLayout"))
            return
        }
        captureFocused()
        let layout = SplitLayout(
            axis: splitAxis == .horizontal ? .horizontal : .vertical,
            ratios: paneRatios,
            panes: panes.map { SplitLayout.Pane(path: $0.path, isGraph: $0.isGraph) },
            focused: focusedPane
        )
        UserDefaults.standard.set(layout.encoded(), forKey: key("splitLayout"))
    }

    /// Reopen the last split for this vault. Returns false when nothing was saved or nothing still exists.
    @discardableResult
    func restoreSplitLayout() -> Bool {
        guard SessionPersistence.isEnabled(vaultPath: root?.path),
              let data = UserDefaults.standard.data(forKey: key("splitLayout")),
              let raw = SplitLayout.decode(data) else { return false }
        let exists: (String) -> Bool = { p in
            self.snapshot?.notes[p] != nil || self.snapshot?.canvases[p] != nil || self.snapshot?.bases[p] != nil
        }
        let axis: SplitAxis = raw.axis == .horizontal ? .horizontal : .vertical
        guard let layout = raw.sanitized(existing: exists, total: splitAxisTotal(axis)) else { return false }
        if layout.panes.count < 2 {
            if let path = layout.panes.first(where: { !$0.isGraph })?.path { openNote(path); return true }
            return false
        }
        splitAxis = axis
        paneRatios = layout.ratios
        panes = layout.panes.map { pane in
            Pane(id: UUID(), path: pane.path, text: contentForPane(pane.path), mode: .read, isGraph: pane.isGraph)
        }
        focusedPane = layout.focused
        if panes.indices.contains(focusedPane), panes[focusedPane].isGraph {
            focusedPane = panes.indices.first(where: { !panes[$0].isGraph }) ?? 0
        }
        let p = panes[focusedPane]
        history = p.history
        historyIndex = p.historyIndex
        guard let path = p.path else { return false }
        openNote(path, recordHistory: true)
        return isSplit
    }

    /// Content-area length along the split axis, minus docked sidebar/inspector for a side-by-side split.
    func splitAxisTotal(_ axis: SplitAxis) -> Double {
        let win = MainWindow.current
        let size = win?.contentView?.bounds.size ?? win?.frame.size ?? CGSize(width: 1180, height: 820)
        if axis == .horizontal { return max(Double(size.height) - 58, PaneRatios.minPane) }
        var width = Double(size.width)
        if sidebarPinned && sidebarVisible {
            let w = UserDefaults.standard.object(forKey: "onyx.sidebarWidth") as? Double ?? 270
            width -= min(max(w, 140), 560)
        }
        if inspectorPinned && inspectorVisible {
            let w = UserDefaults.standard.object(forKey: "onyx.inspectorWidth") as? Double ?? 300
            width -= min(max(w, 150), 600)
        }
        return max(width, PaneRatios.minPane)
    }

    private func contentForPane(_ path: String?) -> String {
        guard let path else { return "" }
        if let n = snapshot?.notes[path] { return n.content }
        if path.isBasePath, let b = snapshot?.bases[path] { return b }
        if let root { return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? "" }
        return ""
    }
}
