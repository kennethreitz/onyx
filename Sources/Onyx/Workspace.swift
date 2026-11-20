import AppKit
import SwiftUI
import Observation
import OnyxCore

enum ViewMode: String { case read, edit }
enum Overlay: Equatable { case none, switcher, palette, graph }
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
    var dailyFolder = "Daily"
    var homePath = "Home.md"

    // Open note
    private(set) var currentPath: String?
    var text: String = "" { didSet { if text != oldValue { textDidChange() } } }
    private(set) var lastSaved: String = ""
    var mode: ViewMode = .read
    private(set) var history: [String] = []
    private(set) var historyIndex = -1
    var recent: [String] = []
    var bookmarks: [String] = []
    var conflict: String? = nil          // disk content that differs from both buffer and last save
    var renderToken = 0                  // bump to make the reader re-render

    // Chrome — quiet by default; focus mode (⌃⌘F) takes it all away.
    var sidebarVisible = UserDefaults.standard.object(forKey: "onyx.sidebarOpen") as? Bool ?? true { didSet { if sidebarVisible != oldValue { chromeLog("sidebarVisible=\(sidebarVisible)") } } }
    var sidebarPinned = UserDefaults.standard.object(forKey: "onyx.sidebarOpen") as? Bool ?? true
    var focusMode = false
    var showHints = !UserDefaults.standard.bool(forKey: "onyx.hintsDismissed")
    var sidebarTab: SidebarTab = .files
    // Split panes. Empty = one pane. The focused pane's note lives in currentPath/text/mode;
    // the others keep their own path, text and mode until focused (swap model).
    var panes: [Pane] = []
    var focusedPane = 0
    var splitAxis: SplitAxis = .vertical
    var paneFrames: [UUID: CGRect] = [:]   // window coords, top-left origin
    var selectedFolder: String? = nil    // folder chosen from the title path, highlighted in the tree
    var revealToken = 0                  // bump to scroll the tree to `selectedFolder`
    var copiedFlash = 0                  // bump to flash "Copied" in the title line
    var inspectorVisible = UserDefaults.standard.bool(forKey: "onyx.inspectorOpen") { didSet { if inspectorVisible != oldValue { chromeLog("inspectorVisible=\(inspectorVisible)") } } }
    var inspectorPinned = UserDefaults.standard.bool(forKey: "onyx.inspectorOpen") { didSet { if inspectorPinned != oldValue { chromeLog("inspectorPinned=\(inspectorPinned)") } } }
    var inspectorTab: InspectorTab = .outline
    var overlay: Overlay = .none
    var searchQuery = ""
    var focusSearch = 0
    var graphAtlas = false
    var rhymesOn = false
    var sidenotes = true
    var externalPulse: Date? = nil
    var lastExternalChange: Date? = nil
    var toast: String? = nil
    var editorJump: Int? = nil           // line to reveal in the editor
    var readerJump: Int? = nil           // heading index to reveal in the reader
    var expanded: Set<String> = []

    private var watcher: FileWatcher?
    private var saveTask: Task<Void, Never>?
    private var reindexTask: Task<Void, Never>?
    private var pendingPaths = Set<String>()
    private var suppressTextChange = false

    var currentNote: NoteRecord? { currentPath.flatMap { snapshot?.notes[$0] } }
    var isDirty: Bool { text != lastSaved }
    var anyChrome: Bool { sidebarVisible || inspectorVisible || overlay != .none }

    // MARK: Opening a vault

    func open(vault url: URL, initialNote: String? = nil) {
        root = url.standardizedFileURL
        loadObsidianSettings()
        recent = UserDefaults.standard.stringArray(forKey: key("recent")) ?? obsidianRecent()
        bookmarks = UserDefaults.standard.stringArray(forKey: key("bookmarks")) ?? obsidianBookmarks()
        isIndexing = true
        let root = self.root!
        let ignore = obsidianIgnore()
        Task.detached(priority: .userInitiated) {
            let t0 = Date()
            let snap = VaultSnapshot.scan(root: root, ignore: ignore)
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            await MainActor.run {
                self.snapshot = snap
                self.indexMillis = ms
                self.isIndexing = false
                if let n = initialNote { self.openNote(n) }
                else if self.currentPath == nil { self.openHome() }
            }
        }
        watcher = FileWatcher(root: root) { [weak self] paths in
            Task { @MainActor in self?.filesChanged(paths) }
        }
    }

    private func key(_ k: String) -> String { "onyx.\(root?.path ?? "").\(k)" }

    private func obsidianJSON(_ name: String) -> Any? {
        guard let root, let d = try? Data(contentsOf: root.appendingPathComponent(".obsidian/\(name)")) else { return nil }
        return try? JSONSerialization.jsonObject(with: d)
    }
    private func loadObsidianSettings() {
        if let d = obsidianJSON("daily-notes.json") as? [String: Any], let f = d["folder"] as? String { dailyFolder = f }
        if let a = obsidianJSON("app.json") as? [String: Any], let m = a["defaultViewMode"] as? String { mode = m == "source" ? .edit : .read }
        if let h = obsidianJSON("plugins/homepage/data.json") as? [String: Any],
           let hp = (h["homepages"] as? [String: Any])?.values.first as? [String: Any], let v = hp["value"] as? String {
            homePath = v.hasSuffix(".md") ? v : v + ".md"
        }
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

    func openLink(_ target: String, from source: String? = nil) {
        guard let snap = snapshot else { return }
        let link = NoteParser.makeLink(inner: target, embed: false, range: NSRange())
        if let p = snap.resolve(link.target, from: source ?? currentPath) {
            if snap.isAttachment(p), let root { NSWorkspace.shared.open(root.appendingPathComponent(p)); return }
            openNote(p, heading: link.heading)
        } else if !link.target.isEmpty {
            createNote(named: link.target, folder: "")   // like Obsidian: clicking an unresolved link creates it
        }
    }

    func openNote(_ path: String, heading: String? = nil, recordHistory: Bool = true) {
        selectedFolder = nil
        guard let snap = snapshot, let note = snap.notes[path] else { return }
        flushSave()
        currentPath = path
        conflict = nil
        suppressTextChange = true
        text = note.content
        lastSaved = note.content
        suppressTextChange = false
        renderToken += 1
        if recordHistory {
            if historyIndex < history.count - 1 { history.removeSubrange((historyIndex + 1)...) }
            history.append(path); historyIndex = history.count - 1
        }
        recent.removeAll { $0 == path }
        recent.insert(path, at: 0)
        if recent.count > 50 { recent.removeLast(recent.count - 50) }
        UserDefaults.standard.set(recent, forKey: key("recent"))
        // reveal in tree
        var parent = (path as NSString).deletingLastPathComponent
        while !parent.isEmpty { expanded.insert(parent); parent = (parent as NSString).deletingLastPathComponent }
        if let heading, let idx = note.summary.headings.firstIndex(where: { $0.text.lowercased() == heading.lowercased() }) {
            readerJump = idx; editorJump = note.summary.headings[idx].line
        }
        if !sidebarPinned { sidebarVisible = false }
        if overlay != .none { overlay = .none }
    }

    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex < history.count - 1 }
    func goBack() { guard canGoBack else { return }; historyIndex -= 1; openNote(history[historyIndex], recordHistory: false) }
    func goForward() { guard canGoForward else { return }; historyIndex += 1; openNote(history[historyIndex], recordHistory: false) }

    // MARK: Daily notes

    func openDaily(offset: Int = 0) {
        guard snapshot != nil else { return }
        if offset != 0, let cur = currentPath, cur.hasPrefix(dailyFolder + "/") {
            // previous / next existing daily note, like daily-notes:goto-prev/next
            let all = snapshot!.notes.keys.filter { $0.hasPrefix(dailyFolder + "/") && DailyNotes.date(fromFileName: ($0 as NSString).lastPathComponent) != nil }.sorted()
            if let i = all.firstIndex(of: cur) {
                let j = i + offset
                if all.indices.contains(j) { openNote(all[j]) }
                return
            }
        }
        let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        let path = DailyNotes.path(for: date, folder: dailyFolder)
        if snapshot?.notes[path] == nil { _ = write(DailyNotes.template(for: date), to: path, create: true) }
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
        let folder = currentPath.map { ($0 as NSString).deletingLastPathComponent } ?? ""
        createNote(named: "Untitled", folder: folder)
    }

    func trashCurrent() {
        guard let p = currentPath, let root else { return }
        let url = root.appendingPathComponent(p)
        NSWorkspace.shared.recycle([url]) { _, _ in }
        snapshot?.refresh(paths: [p])
        currentPath = nil
        goBackOrHome()
    }
    private func goBackOrHome() { if canGoBack { goBack() } else { openHome() } }

    // MARK: Editing & saving

    private func textDidChange() {
        guard !suppressTextChange, currentPath != nil else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    func flushSave() { saveTask?.cancel(); if isDirty { save() } }

    /// Conflict-safe save. If the file changed on disk since we loaded it
    /// (Obsidian Sync, git, another bot) we never overwrite it blindly.
    func save() {
        guard let path = currentPath, let root, isDirty else { return }
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
            let copy = String(path.dropLast(3)) + " (conflict \(Self.stamp())).md"
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
            return true
        } catch {
            toast = "Couldn’t save: \(error.localizedDescription)"
            return false
        }
    }

    /// Toggle the n-th task checkbox (document order, outside code) from reading view.
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

    // MARK: External changes

    private func filesChanged(_ paths: [String]) {
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
        for p in paths where p.lowercased().hasSuffix(".md") {
            let disk = try? String(contentsOf: root.appendingPathComponent(p), encoding: .utf8)
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
            } else if snap.notes[p]?.content != disk { external = true }
        }
        snap.refresh(paths: paths)
        snapshot = snap
        if let cur = currentPath, snap.notes[cur] == nil, !FileManager.default.fileExists(atPath: root.appendingPathComponent(cur).path) {
            toast = "“\((cur as NSString).lastPathComponent)” was moved or deleted elsewhere"
        }
        if external { externalPulse = Date(); lastExternalChange = Date() }
    }

    func reindex() { if let root { let cur = currentPath; open(vault: root, initialNote: cur) } }

    // MARK: Chrome

    func toggleSidebar(_ tab: SidebarTab? = nil) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            if let tab, sidebarVisible, sidebarTab != tab { sidebarTab = tab; return }
            if let tab { sidebarTab = tab }
            sidebarVisible.toggle()
            if !sidebarVisible { sidebarPinned = false }
        }
    }
    /// ⌘I and the footer button: show the inspector docked, or put it away. Remembered across launches.
    func toggleInspector(_ tab: InspectorTab? = nil) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            if let tab, inspectorVisible, inspectorTab != tab { inspectorTab = tab; return }
            if let tab { inspectorTab = tab }
            if inspectorVisible { hideInspector(animated: false) }
            else { if focusMode { toggleFocusMode() }; inspectorVisible = true; inspectorPinned = true; persistInspector() }
        }
    }
    func hideInspector(animated: Bool = true) {
        let body = { self.inspectorVisible = false; self.inspectorPinned = false }
        if animated { withAnimation(.spring(response: 0.3, dampingFraction: 0.9), body) } else { body() }
        persistInspector()
    }
    func persistInspector() { UserDefaults.standard.set(inspectorVisible && inspectorPinned, forKey: "onyx.inspectorOpen") }
    func show(_ o: Overlay) {
        withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) { overlay = overlay == o ? .none : o }
    }
    /// Esc: peel back one floating layer (overlays, then summoned panels).
    func dismissTop() -> Bool {
        let anim = Animation.spring(response: 0.3, dampingFraction: 0.9)
        if overlay != .none { withAnimation(anim) { overlay = .none }; return true }
        if inspectorVisible && !inspectorPinned { hideInspector(); return true }
        if sidebarVisible && !sidebarPinned { withAnimation(anim) { sidebarVisible = false }; return true }
        if inspectorVisible { hideInspector(); return true }      // Esc puts a docked inspector away too
        if focusMode { toggleFocusMode(); return true }
        return false
    }

    /// ⌘K: the docked file sidebar, remembered across launches.
    func toggleDockedSidebar(_ tab: SidebarTab? = nil) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            if let tab, sidebarVisible, sidebarTab != tab { sidebarTab = tab; return }
            if let tab { sidebarTab = tab }
            let open = !(sidebarVisible && sidebarPinned)
            sidebarVisible = open; sidebarPinned = open
            if open { focusMode = false }
        }
        UserDefaults.standard.set(sidebarPinned, forKey: "onyx.sidebarOpen")
    }

    private var preFocus: (Bool, Bool, Bool, Bool)?
    /// ⌃⌘F: pure text. Everything else steps aside; the same keys bring it back.
    func toggleFocusMode() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
            if focusMode {
                focusMode = false
                if let p = preFocus { sidebarVisible = p.0; sidebarPinned = p.1; inspectorVisible = p.2; inspectorPinned = p.3 }
            } else {
                preFocus = (sidebarVisible, sidebarPinned, inspectorVisible, inspectorPinned)
                focusMode = true
                sidebarVisible = false; inspectorVisible = false; overlay = .none
            }
        }
    }

    func dismissHints() { withAnimation(.easeOut(duration: 0.2)) { showHints = false }; UserDefaults.standard.set(true, forKey: "onyx.hintsDismissed") }
    func toggleWorkspaceLayout() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            let on = !(sidebarPinned && inspectorPinned && sidebarVisible && inspectorVisible)
            sidebarPinned = on; inspectorPinned = on; sidebarVisible = on; inspectorVisible = on
            if on { focusMode = false }
        }
        UserDefaults.standard.set(sidebarPinned, forKey: "onyx.sidebarOpen")
        persistInspector()
    }
    func toggleMode() {
        flushSave()
        withAnimation(.easeInOut(duration: 0.18)) { mode = mode == .read ? .edit : .read }
    }
    func toggleBookmark() {
        guard let p = currentPath else { return }
        if bookmarks.contains(p) { bookmarks.removeAll { $0 == p } } else { bookmarks.append(p) }
        UserDefaults.standard.set(bookmarks, forKey: key("bookmarks"))
    }
    func revealInFinder() { if let p = currentPath, let root { NSWorkspace.shared.activateFileViewerSelecting([root.appendingPathComponent(p)]) } }
    func openInObsidian() {
        guard let p = currentPath, let root else { return }
        var c = URLComponents(); c.scheme = "obsidian"; c.host = "open"
        c.queryItems = [URLQueryItem(name: "vault", value: root.lastPathComponent), URLQueryItem(name: "file", value: p)]
        if let u = c.url { NSWorkspace.shared.open(u) }
    }
    /// Title-path click: open the folder's note if it has one (folder-notes convention),
    /// then dock the sidebar on Files, expand down to the folder, select and scroll to it.
    func revealFolder(_ folder: String) {
        let note = folder + "/" + (folder as NSString).lastPathComponent + ".md"
        if snapshot?.notes[note] != nil, currentPath != note { openNote(note) }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
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
}

/// .vertical = side by side (⌘D), .horizontal = stacked (⇧⌘D), as in iTerm and VS Code.
enum SplitAxis { case vertical, horizontal }

extension Workspace {
    var isSplit: Bool { panes.count > 1 }

    private func captureFocused() {
        guard panes.indices.contains(focusedPane) else { return }
        panes[focusedPane].path = currentPath
        panes[focusedPane].text = text
        panes[focusedPane].mode = mode
    }

    /// ⌘D / ⇧⌘D: split the focused pane; the new pane shows the same note and takes focus.
    func split(_ axis: SplitAxis) {
        flushSave()
        if panes.isEmpty { panes = [Pane(id: UUID(), path: currentPath, text: text, mode: mode)]; focusedPane = 0 }
        guard panes.count < 4 else { toast = "Four panes is the limit"; return }
        captureFocused()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            splitAxis = axis
            panes.insert(Pane(id: UUID(), path: currentPath, text: text, mode: mode), at: focusedPane + 1)
            focusedPane += 1
        }
        chromeLog("split \(axis) panes=\(panes.count) focused=\(focusedPane)")
    }

    /// Click or ⌃⇥: hand the live editor state to another pane.
    func focusPane(_ i: Int) {
        guard isSplit, panes.indices.contains(i), i != focusedPane else { return }
        flushSave()
        captureFocused()
        focusedPane = i
        let p = panes[i]
        if let path = p.path, path != currentPath { openNote(path) }
        mode = p.mode
        chromeLog("focusPane \(i) → \(currentPath ?? "-") \(mode)")
    }
    func focusNextPane(_ step: Int = 1) {
        guard isSplit else { return }
        focusPane((focusedPane + step + panes.count) % panes.count)
    }

    /// ⌘W with panes: close the focused one. Returns false when there is nothing to close
    /// (one pane), so ⌘W falls through to closing the window.
    @discardableResult
    func closePane() -> Bool {
        guard isSplit else { return false }
        flushSave()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            panes.remove(at: focusedPane)
            focusedPane = min(focusedPane, panes.count - 1)
        }
        let p = panes[focusedPane]
        if let path = p.path, path != currentPath { openNote(path) }
        mode = p.mode
        if panes.count == 1 { panes = [] ; focusedPane = 0 }
        chromeLog("closePane → panes=\(panes.count) \(currentPath ?? "-")")
        return true
    }

    /// Text an unfocused pane should show: live text if it's the same note as the focused pane.
    func displayText(_ p: Pane) -> String { p.path != nil && p.path == currentPath ? text : p.text }
}
