import SwiftUI
import AppKit
import WebKit
import OnyxCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ n: Notification) {
        // Before windows come up or boot() restores session state: ask any
        // other packaged Onyx to quit and wait for it to finish saving.
        SingleInstanceHandover.takeOverIfNeeded()
    }
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        ScrollSelfTest.scheduleIfRequested()
        TypeSelfTest.scheduleIfRequested()
        KeySelfTest.scheduleIfRequested()
        // ⌃⌘F belongs to focus mode; Enter Full Screen keeps its menu item and the green button.
        for delay in [0.3, 1.0, 3.0] { DispatchQueue.main.asyncAfter(deadline: .now() + delay) { Self.freeControlCommandF() } }
        if ProcessInfo.processInfo.environment["ONYX_DUMP_MENUS"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { Self.dumpMenus() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in Self.freeControlCommandF() }
        UpdateController.shared.start()
    }
    /// Debug: every menu item that has a key equivalent, to audit for double bindings.
    static func dumpMenus() {
        func mods(_ m: NSEvent.ModifierFlags) -> String {
            (m.contains(.control) ? "⌃" : "") + (m.contains(.option) ? "⌥" : "") + (m.contains(.shift) ? "⇧" : "") + (m.contains(.command) ? "⌘" : "")
        }
        func walk(_ m: NSMenu?, _ path: String) {
            for item in m?.items ?? [] {
                let p = path.isEmpty ? item.title : path + " > " + item.title
                if !item.keyEquivalent.isEmpty {
                    let k = item.keyEquivalent == "\r" ? "↩" : item.keyEquivalent == "\u{1b}" ? "Esc" : item.keyEquivalent
                    print("[menu] \(mods(item.keyEquivalentModifierMask))\(k)\t\(p)\t\(item.action.map(NSStringFromSelector) ?? "-")")
                }
                walk(item.submenu, p)
            }
        }
        walk(NSApp.mainMenu, "")
        fflush(stdout)
    }
    static func freeControlCommandF() {
        func walk(_ m: NSMenu?) {
            for item in m?.items ?? [] {
                if item.action == #selector(NSWindow.toggleFullScreen(_:)), item.keyEquivalent.lowercased() == "f" {
                    item.keyEquivalent = "f"; item.keyEquivalentModifierMask = [.command, .control, .shift]
                }
                walk(item.submenu)
            }
        }
        walk(NSApp.mainMenu)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool {
        WindowLifecycle.terminateAfterLastWindowClosed
    }
    func applicationShouldHandleReopen(_ app: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindow.reveal()
        return false
    }
}


struct LaunchOptions {
    var vault: URL?
    var open: String?
    var mode: ViewMode?
    var appearance: String?
    var show: String?
    var windowIDFile: String?
    var size: CGSize?
    var sidebar: Bool?
    /// Test/screenshot hook: open a split after the vault is up. `--split stacked` (or
    /// `horizontal`) stacks; anything else is side by side. `--pane-ratios 0.35,0.65`
    /// sets the sizes (also implies a split). `--split-open` opens that note in the new pane.
    var split: SplitAxis?
    var splitOpen: String?
    var paneRatios: [Double]?

    static func parse() -> LaunchOptions {
        var o = LaunchOptions()
        let a = CommandLine.arguments
        func val(_ k: String) -> String? { a.firstIndex(of: k).flatMap { a.indices.contains($0 + 1) ? a[$0 + 1] : nil } }
        if let v = val("--vault") { o.vault = URL(fileURLWithPath: (v as NSString).expandingTildeInPath) }
        o.open = val("--open")
        o.mode = val("--mode").flatMap(ViewMode.init(rawValue:))
        o.appearance = val("--appearance")
        o.show = val("--show")
        o.windowIDFile = val("--window-id-file")
        if let sb = val("--sidebar") { o.sidebar = sb == "open" }
        if let s = val("--size") { let p = s.split(separator: "x").compactMap { Double($0) }; if p.count == 2 { o.size = CGSize(width: p[0], height: p[1]) } }
        if let s = val("--split") { o.split = (s == "stacked" || s == "horizontal") ? .horizontal : .vertical }
        o.splitOpen = val("--split-open")
        if let r = val("--pane-ratios") {
            let parts = r.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count >= 2 { o.paneRatios = parts; if o.split == nil { o.split = .vertical } }
        }
        return o
    }
}

@main
struct OnyxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var ws = Workspace()
    @State private var shortcutRevision = 0
    @AppStorage("onyx.appearance") private var appearance = "system"
    private let options = LaunchOptions.parse()

    init() {
        Typeset.migrateOpenDyslexicIfNeeded()
        AppResources.registerFonts()
        WindowConfigurator.idFile = options.windowIDFile
        if let ap = options.appearance { UserDefaults.standard.set(ap, forKey: "onyx.appearance") }
        if let sb = LaunchOptions.parse().sidebar { UserDefaults.standard.set(sb, forKey: "onyx.sidebarOpen") }
    }

    static func remember(_ url: URL) { UserDefaults.standard.set(url.path, forKey: "onyx.vault") }

    /// Without --vault: the last vault you opened, else ~/Notes if it exists. A remembered vault
    /// in /tmp (a test or demo copy) doesn't count, so the demo opens only when chosen with
    /// --vault or Open Vault…. ONYX_NO_DEFAULT_VAULT=1 (tests) never falls back to anything.
    static func defaultVault() -> URL? {
        guard ProcessInfo.processInfo.environment["ONYX_NO_DEFAULT_VAULT"] == nil else { return nil }
        let fm = FileManager.default
        if let p = UserDefaults.standard.string(forKey: "onyx.vault"), !p.hasPrefix("/tmp/"), !p.hasPrefix("/private/tmp/"),
           fm.fileExists(atPath: p) { return URL(fileURLWithPath: p) }
        let notes = fm.homeDirectoryForCurrentUser.appendingPathComponent("Notes")
        return fm.fileExists(atPath: notes.path) ? notes : nil
    }

    var body: some Scene {
        Window("Onyx", id: WindowLifecycle.mainWindowIdentifier) {
            RootView(ws: ws, appearance: { appearance = $0; apply($0) })
                .frame(minWidth: 640, minHeight: 420)
                .onAppear(perform: boot)
                .onChange(of: appearance) { apply(appearance) }
                .onReceive(NotificationCenter.default.publisher(for: ShortcutStore.didChange)) { _ in shortcutRevision += 1 }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: options.size?.width ?? 1180, height: options.size?.height ?? 820)
        .commands { let _ = shortcutRevision; MainWindowCommands(); menus }

        Settings {
            SettingsView(ws: ws)
        }
    }

    func apply(_ a: String) { OnyxApp.applyAppearance(a) }
    static func applyAppearance(_ a: String) {
        NSApp.appearance = a == "dark" ? NSAppearance(named: .darkAqua) : (a == "light" ? NSAppearance(named: .aqua) : nil)
    }

    func boot() {
        apply(appearance)
        TypeSelfTest.ws = ws
        // Observers are installed once: closing and reopening the window
        // runs boot() again, but the vault (and Workspace) is already live.
        AppLifecycle.install(ws: ws)
        guard ws.root == nil else { return }
        // --vault never overwrites the remembered vault (so test runs stay isolated).
        guard let url = options.vault ?? OnyxApp.defaultVault() else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        if let m = options.mode { ws.mode = m }
        if let sb = options.sidebar { ws.sidebarVisible = sb; ws.sidebarPinned = true }
        ws.sidenotes = UserDefaults.standard.object(forKey: Prefs.sidenotes) as? Bool ?? true
        if UserDefaults.standard.bool(forKey: Prefs.startFocus) { ws.toggleFocusMode() }
        // --open / --split are test and screenshot hooks: don't restore a saved layout over them.
        ws.open(vault: url, initialNote: options.open, restoreSplits: options.split == nil && options.open == nil)
        if let m = options.mode { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { ws.mode = m } }
        if let s = options.show {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                switch s {
                case "sidebar": ws.toggleSidebar(.files)
                case "search": ws.searchQuery = "tarot"; ws.toggleSidebar(.search)
                case "inspector": ws.toggleInspector(.backlinks)
                case "outline": ws.toggleInspector(.outline)
                case "switcher": ws.show(.switcher)
                case "palette": ws.show(.palette)
                case "graph": ws.graphAtlas = false; ws.show(.graph)
                case "atlas": ws.graphAtlas = true; ws.show(.graph)
                case "workspace": ws.toggleWorkspaceLayout()
                case "daily": ws.openDaily()
                case "synclog", "sync-log":
                    ws.syncLog?.seedPreviewIfEmpty()
                    ws.show(.syncLog)
                case "newfolder", "new-folder":
                    if !ws.sidebarVisible { ws.toggleDockedSidebar(.files) } else { ws.sidebarTab = .files }
                    _ = ws.createFolder(prompt: false)
                default: break
                }
            }
        }
        // Screenshot / test hook: --split implies SessionPersistence is off, so this layout
        // stays in this window only and is never written to defaults.
        // Wait until the vault has opened the first note; otherwise the left pane is born empty.
        if options.split != nil {
            func applySplit(attempt: Int = 0) {
                if (ws.isIndexing || ws.currentPath == nil || ws.text.isEmpty), attempt < 40 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { applySplit(attempt: attempt + 1) }
                    return
                }
                if !ws.isSplit { ws.split(options.split ?? .vertical) }
                if let path = options.splitOpen { ws.openNote(path) }
                if let r = options.paneRatios { ws.setPaneRatios(r) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { applySplit() }
        }
    }

    @CommandsBuilder var menus: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { UpdateController.shared.check(interactive: true) }
        }
        CommandGroup(replacing: .newItem) {
            ShortcutMenus.button("new") { ws.newNote() }
            ShortcutMenus.button("newfolder") { ws.newFolder() }
            ShortcutMenus.button("openvault", needsWindow: false) { openVault() }
            Divider()
            ShortcutMenus.button("switcher") { ws.show(.switcher) }
            ShortcutMenus.button("palette") { ws.show(.palette) }
        }
        CommandGroup(after: .saveItem) {
            ShortcutMenus.button("save") { ws.lintOnSave(); ws.flushSave() }
            Divider()
            // Delete is disabled while a palette is open; ⌘⌫ is also kept off the menu item so the editor and text fields can use it.
            ShortcutMenus.button("rename", disabled: ws.currentPath == nil || ws.overlay != .none) { ws.confirmRenameCurrent() }
            ShortcutMenus.button("move", disabled: ws.currentPath == nil || ws.overlay != .none) { ws.beginMoveCurrent() }
            ShortcutMenus.button("delete", disabled: ws.currentPath == nil || ws.overlay != .none) { ws.confirmTrashCurrent() }
            ShortcutMenus.button("duplicate", disabled: ws.currentPath == nil || ws.isCanvas || ws.isBase || ws.isFile) { ws.duplicateCurrent() }
            Divider()
            ShortcutMenus.button("copypath", disabled: ws.currentPath == nil) { ws.copyFilePath() }
            ShortcutMenus.button("openexternal", disabled: ws.currentPath == nil) { ws.openInDefaultApp() }
        }
        // The command palette takes ⌘P by default (Obsidian's habit), so Print defaults to ⌥⌘P.
        CommandGroup(replacing: .printItem) {
            ShortcutMenus.button("exportpdf", disabled: ws.currentPath == nil) { NotePrinter.run("export", ws: ws) }
            ShortcutMenus.button("exportsel", disabled: !ws.treeSelection.isMulti) { NoteBookPrinter.run(Array(ws.treeSelection.selected), ws: ws) }
            ShortcutMenus.button("exportfolder", disabled: (ws.treeSelection.selected.count == 1 ? ws.treeSelection.selected.first : ws.selectedFolder) == nil) {
                if let f = ws.treeSelection.selected.count == 1 ? ws.treeSelection.selected.first : ws.selectedFolder {
                    NoteBookPrinter.run([f], ws: ws)
                }
            }
            ShortcutMenus.button("print", disabled: ws.currentPath == nil) { NotePrinter.run("print", ws: ws) }
        }
        CommandMenu("Go") {
            ShortcutMenus.button("daily") { ws.openDaily() }
            ShortcutMenus.button("daily-prev") { ws.openDaily(offset: -1) }
            ShortcutMenus.button("daily-next") { ws.openDaily(offset: 1) }
            ShortcutMenus.button("daily-yesterday") { ws.openDaily(days: -1) }
            ShortcutMenus.button("daily-tomorrow") { ws.openDaily(days: 1) }
            Divider()
            ShortcutMenus.button("back", disabled: !ws.canGoBack) { ws.goBack() }
            ShortcutMenus.button("forward", disabled: !ws.canGoForward) { ws.goForward() }
            ShortcutMenus.button("home") { ws.openHome() }
            ShortcutMenus.button("random") { ws.openRandomNote() }
            ShortcutMenus.button("headings", disabled: ws.currentPath == nil) { ws.show(.headings) }
            ShortcutMenus.button("revealtree", disabled: ws.currentPath == nil) { ws.revealInSidebar() }
            Divider()
            ShortcutMenus.button("graph") { ws.toggleGraph(atlas: false) }
            ShortcutMenus.button("atlas") { ws.toggleGraph(atlas: true) }
            ShortcutMenus.button("graphpane", title: ws.graphPaneIndex == nil ? "Graph in a Pane" : "Close Graph Pane") {
                ws.graphPaneIndex == nil ? ws.openGraphPane(atlas: ws.graphAtlas) : ws.closeGraphPane()
            }
        }
        CommandMenu("Pane") {
            ShortcutMenus.button("split") { ws.split(.vertical) }
            ShortcutMenus.button("splitdown") { ws.split(.horizontal) }
            ShortcutMenus.button("newpane") { ws.newNoteInPane() }
            ShortcutMenus.button("closepane", disabled: !ws.isSplit) { ws.closePane() }
            Divider()
            ShortcutMenus.button("nextpane", disabled: !ws.isSplit) { ws.focusNextPane() }
            ShortcutMenus.button("prevpane", disabled: !ws.isSplit) { ws.focusNextPane(-1) }
        }
        CommandGroup(after: .toolbar) {
            ShortcutMenus.button("modetoggle", title: ws.mode == .read ? "Edit Note" : "Read Note") { ws.toggleMode() }
            ShortcutMenus.button("mode", title: ws.mode == .read ? "Edit Note and Save" : "Save and Read") { ws.toggleMode() }
            ShortcutMenus.button("focus", title: ws.focusMode ? "Leave Focus Mode" : "Focus Mode") { ws.toggleFocusMode() }
            Menu("Folding") {
                ForEach(Workspace.foldMenu, id: \.self) { id in
                    ShortcutMenus.button(id, disabled: ws.currentPath == nil || ws.isCanvas || ws.isBase || ws.isFile || ws.overlay != .none) { ws.runFold(id) }
                }
            }
            Divider()
            ShortcutMenus.button("files", title: ws.sidebarVisible ? "Hide Sidebar" : "Show Sidebar") { ws.toggleDockedSidebar(.files) }
            ShortcutMenus.button("search") { ws.sidebarTab = .search; if !ws.sidebarVisible { ws.toggleSidebar() }; ws.focusSearch += 1 }
            ShortcutMenus.button("recent") { ws.toggleSidebar(.recent) }
            ShortcutMenus.button("bookmarks") { ws.toggleSidebar(.bookmarks) }
            ShortcutMenus.button("tags") { ws.toggleSidebar(.tags) }
            ShortcutMenus.button("git") { ws.toggleSidebar(.git) }
            Divider()
            ShortcutMenus.button("inspector") { ws.toggleInspector() }
            ShortcutMenus.button("outline") { ws.toggleInspector(.outline) }
            ShortcutMenus.button("backlinks") { ws.toggleInspector(.backlinks) }
            ShortcutMenus.button("props") { ws.toggleInspector(.properties) }
            ShortcutMenus.button("layout") { ws.toggleWorkspaceLayout() }
            Divider()
            ShortcutMenus.button("sidenotes", title: ws.sidenotes ? "Footnotes at End" : "Footnotes as Sidenotes") { ws.sidenotes.toggle() }
            Menu("Appearance") {
                ShortcutMenus.button("light", title: "Light") { appearance = "light"; apply("light") }
                ShortcutMenus.button("dark", title: "Dark") { appearance = "dark"; apply("dark") }
                ShortcutMenus.button("system", title: "Auto (Match System)") { appearance = "system"; apply("system") }
            }
            ShortcutMenus.button("synclog") { ws.show(.syncLog) }
            Divider()
            ShortcutMenus.button("zoomin") { ws.zoom(1) }
            ShortcutMenus.button("zoomout") { ws.zoom(-1) }
            ShortcutMenus.button("zoomreset") { ws.zoom(0) }
            Divider()
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            ShortcutMenus.button("find") { ws.openFind() }
            ShortcutMenus.button("findreplace") { ws.openFind(replace: true) }
            ShortcutMenus.button("searchsel") { ws.searchSelection() }
            ShortcutMenus.button("spellcheck", title: EditorPrefs.spellcheckOn ? "Turn Spellcheck Off" : "Turn Spellcheck On") { ws.toggleSpellcheck() }
            Button("Find Next (⌘G while finding)") { ws.findStep(1) }.disabled(!ws.finder.visible)
            Button("Find Previous (⇧⌘G while finding)") { ws.findStep(-1) }.disabled(!ws.finder.visible)
            Divider()
            ShortcutMenus.button("merge", disabled: ws.currentPath?.lowercased().hasSuffix(".md") != true || ws.isCanvas || ws.isBase || ws.isFile || ws.overlay != .none) { ws.beginMerge() }
            ShortcutMenus.button("extract", disabled: ws.currentPath?.lowercased().hasSuffix(".md") != true || ws.isCanvas || ws.isBase || ws.isFile || ws.overlay != .none) { ws.beginExtract() }
            ShortcutMenus.button("extractheading", disabled: ws.currentPath?.lowercased().hasSuffix(".md") != true || ws.isCanvas || ws.isBase || ws.isFile || ws.overlay != .none) { ws.beginExtract(heading: true) }
        }
        CommandMenu("Format") {
            ForEach(Array(Workspace.formatMenu.enumerated()), id: \.offset) { _, id in
                if let id {
                    ShortcutMenus.button(id, disabled: ws.currentPath == nil || ws.isCanvas || ws.isBase || ws.isFile || ws.overlay != .none) { ws.runEditCommand(id) }
                } else { Divider() }
            }
        }
        CommandMenu("Note") {
            ShortcutMenus.button("bookmark", title: ws.currentPath.map { ws.bookmarks.contains($0) } == true ? "Remove Bookmark" : "Bookmark") { ws.toggleBookmark() }
            ShortcutMenus.button("copy") { ws.copyWikilink() }
            ShortcutMenus.button("finder") { ws.revealInFinder() }
            ShortcutMenus.button("obsidian") { ws.openInObsidian() }
            Divider()
            ShortcutMenus.button("lint", disabled: ws.currentPath?.lowercased().hasSuffix(".md") != true) { ws.lintCurrentNote() }
            ShortcutMenus.button("lintfolder", disabled: ws.root == nil) { ws.chooseLintFolder() }
            ShortcutMenus.button("readaloud", disabled: ws.currentPath == nil || ws.isCanvas || ws.isBase || ws.isFile) { ws.readAloud() }
            ShortcutMenus.button("readpause", title: ws.speech.state == .paused ? "Resume Reading" : "Pause Reading", disabled: !ws.speech.isActive) { ws.toggleSpeechPause() }
            ShortcutMenus.button("readstop", disabled: !ws.speech.isActive) { ws.stopSpeech() }
            ShortcutMenus.button("record", title: ws.recorder.isRecording ? "Stop Recording" : "Record Audio",
                                 disabled: !ws.recorder.isRecording && (ws.currentPath == nil || ws.isCanvas || ws.isBase || ws.isFile || ws.recorder.isActive)) { ws.toggleRecording() }
            Divider()
            ShortcutMenus.button("reindex") { ws.reindex() }
            ShortcutMenus.button("hints") { withAnimation(Motion.quick) { ws.showHints = true } }
            ShortcutMenus.button("settings", needsWindow: false) { Workspace.openSettings() }
        }
    }
    func openVault() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.prompt = "Open Vault"
        if p.runModal() == .OK, let u = p.url {
            OnyxApp.remember(u)
            ws.open(vault: u)
            MainWindow.revealIfNeeded()
        }
    }
}

/// App-wide observers that must survive the vault window closing and reopening.
@MainActor enum AppLifecycle {
    private static var installed = false

    static func install(ws: Workspace) {
        guard !installed else { return }
        installed = true
        let nc = NotificationCenter.default
        // git: leaving the app commits at once, coming back pulls, quitting commits and pushes
        nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [ws] _ in
            MainActor.assumeIsolated { ws.flushSave(); ws.persistSplitLayout(); ws.git?.commitNow() }
        }
        nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [ws] _ in
            MainActor.assumeIsolated { ws.git?.syncNow(); ws.obsidianSync?.syncNow() }
        }
        // terminate() from a new Onyx (and Quit) lands here: flush unsaved
        // notes and session state before the process exits, so the new copy
        // can restore them. Never skip this for a "just quit" path.
        nc.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [ws] _ in
            MainActor.assumeIsolated { ws.flushSave(); ws.persistSplitLayout(); ws.git?.finishForQuit(); ws.obsidianSync?.stop() }
        }
        nc.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [ws] note in
            guard let w = note.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                guard MainWindow.isVaultWindow(w) else { return }
                if MainWindow.current === w { MainWindow.current = nil }
                ws.prepareForWindowClose()
            }
        }
    }

}

/// Debug (ONYX_KEY_SELFTEST=1): offer every help-sheet shortcut to the window's view hierarchy
/// with the editor, then the reader, as first responder, and report which views claim it
/// before the menu bar gets a chance (i.e. which keys the text view or web view would swallow).
enum KeySelfTest {
    static let keys: [(String, UInt16, String, NSEvent.ModifierFlags)] = [
        ("⌘O", 31, "o", .command), ("⌘P", 35, "p", .command), ("⇧⌘P", 35, "p", [.command, .shift]),
        ("⇧⌘N", 45, "n", [.command, .shift]), ("⌘N", 45, "n", .command),
        ("⌘K", 40, "k", .command), ("⇧⌘F", 3, "f", [.command, .shift]), ("⌘↩", 36, "\r", .command),
        ("⌘E", 14, "e", .command), ("⌘T", 17, "t", .command), ("⌘\\", 42, "\\", .command),
        ("⌘I", 34, "i", .command), ("⌘B", 11, "b", .command), ("⌥⌘I", 34, "i", [.command, .option]), ("⌘G", 5, "g", .command), ("⇧⌘G", 5, "g", [.command, .shift]),
        ("⌘D", 2, "d", .command), ("⇧⌘D", 2, "d", [.command, .shift]), ("⌘W", 13, "w", .command),
        ("⌃⌘F", 3, "f", [.command, .control]), ("Esc", 53, "\u{1b}", []),
    ]
    @MainActor static func scheduleIfRequested() {
        guard ProcessInfo.processInfo.environment["ONYX_KEY_SELFTEST"] != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { run() }
    }
    @MainActor static func run() {
        guard let w = NSApp.windows.first(where: { $0.contentView != nil && !($0 is NSPanel) && $0.isVisible }), let root = w.contentView else { return }
        func find<T: NSView>(_ v: NSView, _ t: T.Type) -> T? { if let x = v as? T { return x }; for s in v.subviews { if let x = find(s, t) { return x } }; return nil }
        for (label, responder) in [("editor", find(root, OnyxTextView.self) as NSView?), ("reader", find(root, WKWebView.self) as NSView?)] {
            guard let r = responder else { print("[keytest] \(label): not on screen"); continue }
            w.makeFirstResponder(r)
            for (name, code, ch, mods) in keys {
                let chars = mods.contains(.shift) ? ch.uppercased() : ch
                guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: mods, timestamp: 0, windowNumber: w.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code) else { continue }
                // Only shortcut-style keys travel the performKeyEquivalent path; Esc goes to keyDown.
                let claimed = mods.contains(.command) ? root.performKeyEquivalent(with: e) : false
                print("[keytest] \(label) \(name): \(claimed ? "CLAIMED by a view" : "free → menu")")
            }
        }
        fflush(stdout)
    }
}
