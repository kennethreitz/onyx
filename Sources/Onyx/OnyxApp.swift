import SwiftUI
import AppKit
import WebKit
import OnyxCore

final class AppDelegate: NSObject, NSApplicationDelegate {
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
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
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
    @AppStorage("onyx.appearance") private var appearance = "system"
    private let options = LaunchOptions.parse()

    init() {
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
        WindowGroup("Onyx") {
            RootView(ws: ws, appearance: { appearance = $0; apply($0) })
                .frame(minWidth: 640, minHeight: 420)
                .onAppear(perform: boot)
                .onChange(of: appearance) { apply(appearance) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: options.size?.width ?? 1180, height: options.size?.height ?? 820)
        .commands { menus }

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
        // git: leaving the app commits at once, coming back pulls, quitting commits and pushes
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [ws] _ in
            MainActor.assumeIsolated { ws.flushSave(); ws.persistSplitLayout(); ws.git?.commitNow() }
        }
        nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [ws] _ in
            MainActor.assumeIsolated { ws.git?.syncNow(); ws.obsidianSync?.syncNow() }
        }
        nc.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [ws] _ in
            MainActor.assumeIsolated { ws.flushSave(); ws.persistSplitLayout(); ws.git?.finishForQuit(); ws.obsidianSync?.stop() }
        }
        guard ws.root == nil else { return }
        // --vault never overwrites the remembered vault (so test runs stay isolated).
        guard let url = options.vault ?? OnyxApp.defaultVault() else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        if let m = options.mode { ws.mode = m }
        if let sb = options.sidebar { ws.sidebarVisible = sb; ws.sidebarPinned = sb }
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
            Button("New Note") { ws.newNote() }.keyboardShortcut("n")
            Button("Open Vault…") { openVault() }.keyboardShortcut("o", modifiers: [.command, .shift])
            Divider()
            Button("Quick Switcher…") { ws.show(.switcher) }.keyboardShortcut("o")
            Button("Command Palette…  (also ⇧⌘P)") { ws.show(.palette) }.keyboardShortcut("p")
        }
        CommandGroup(after: .saveItem) {
            Button("Save") { ws.flushSave() }.keyboardShortcut("s")
            Divider()
            // ⌘⌫ (disabled while a palette is open, so text fields there keep it)
            Button("Rename Note…") { ws.confirmRenameCurrent() }.disabled(ws.currentPath == nil || ws.overlay != .none)
            Button("Move Note to…") { ws.beginMoveCurrent() }.keyboardShortcut("m", modifiers: [.command, .shift]).disabled(ws.currentPath == nil || ws.overlay != .none)
            Button("Delete Note…") { ws.confirmTrashCurrent() }.keyboardShortcut(.delete).disabled(ws.currentPath == nil || ws.overlay != .none)
        }
        // ⌘P is the command palette here (Obsidian's habit), so Print takes ⌥⌘P.
        CommandGroup(replacing: .printItem) {
            Button("Export as PDF…") { NotePrinter.run("export", ws: ws) }.keyboardShortcut("e", modifiers: [.command, .shift]).disabled(ws.currentPath == nil)
            Button("Print…") { NotePrinter.run("print", ws: ws) }.keyboardShortcut("p", modifiers: [.command, .option]).disabled(ws.currentPath == nil)
        }
        CommandMenu("Go") {
            Button("Today’s Daily Note") { ws.openDaily() }.keyboardShortcut("t")
            Button("Today’s Daily Note ") { ws.openDaily() }.keyboardShortcut("\\")
            Button("Previous Daily Note") { ws.openDaily(offset: -1) }.keyboardShortcut("[", modifiers: [.command, .option])
            Button("Next Daily Note") { ws.openDaily(offset: 1) }.keyboardShortcut("]", modifiers: [.command, .option])
            Divider()
            Button("Back") { ws.goBack() }.keyboardShortcut("[").disabled(!ws.canGoBack)
            Button("Forward") { ws.goForward() }.keyboardShortcut("]").disabled(!ws.canGoForward)
            Button("Homepage") { ws.openHome() }.keyboardShortcut("h", modifiers: [.command, .shift])
            Divider()
            Button("Focus Graph") { ws.graphAtlas = false; ws.overlay == .graph ? ws.show(.none) : ws.show(.graph) }.keyboardShortcut("g")
            Button("Atlas") { ws.graphAtlas = true; if ws.overlay != .graph { ws.show(.graph) } }.keyboardShortcut("g", modifiers: [.command, .shift])
            Button(ws.graphPaneIndex == nil ? "Graph in a Pane" : "Close Graph Pane") { ws.graphPaneIndex == nil ? ws.openGraphPane(atlas: ws.graphAtlas) : ws.closeGraphPane() }
                .keyboardShortcut("g", modifiers: [.command, .option])
        }
        CommandMenu("Pane") {
            Button("Split Side by Side") { ws.split(.vertical) }.keyboardShortcut("d")
            Button("Split Stacked") { ws.split(.horizontal) }.keyboardShortcut("d", modifiers: [.command, .shift])
            Button("Close Pane  (⌘W)") { ws.closePane() }.disabled(!ws.isSplit)
            Divider()
            Button("Next Pane") { ws.focusNextPane() }.keyboardShortcut(.tab, modifiers: .control).disabled(!ws.isSplit)
            Button("Previous Pane") { ws.focusNextPane(-1) }.keyboardShortcut(.tab, modifiers: [.control, .shift]).disabled(!ws.isSplit)
        }
        CommandGroup(after: .toolbar) {
            Button(ws.mode == .read ? "Edit Note" : "Read Note") { ws.toggleMode() }.keyboardShortcut("e")
            Button(ws.mode == .read ? "Edit Note and Save" : "Save and Read") { ws.toggleMode() }.keyboardShortcut(.return, modifiers: .command)
            Button(ws.focusMode ? "Leave Focus Mode" : "Focus Mode") { ws.toggleFocusMode() }.keyboardShortcut("f", modifiers: [.command, .control])
            Divider()
            Button(ws.sidebarVisible && ws.sidebarPinned ? "Hide Sidebar" : "Show Sidebar") { ws.toggleDockedSidebar(.files) }.keyboardShortcut("k")
            Button("Search Vault") { ws.sidebarTab = .search; if !ws.sidebarVisible { ws.toggleSidebar() }; ws.focusSearch += 1 }.keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Recent Files") { ws.toggleSidebar(.recent) }.keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Bookmarks") { ws.toggleSidebar(.bookmarks) }.keyboardShortcut("b", modifiers: [.command, .shift])
            Button("Tags") { ws.toggleSidebar(.tags) }.keyboardShortcut("t", modifiers: [.command, .shift])
            Button("Source Control") { ws.toggleSidebar(.git) }.keyboardShortcut("y", modifiers: [.command, .shift])
            Divider()
            Button("Inspector") { ws.toggleInspector() }.keyboardShortcut("i")
            Button("Outline") { ws.toggleInspector(.outline) }.keyboardShortcut("1", modifiers: [.command, .option])
            Button("Backlinks") { ws.toggleInspector(.backlinks) }.keyboardShortcut("2", modifiers: [.command, .option])
            Button("Properties") { ws.toggleInspector(.properties) }.keyboardShortcut("3", modifiers: [.command, .option])
            Button("Three-Pane Workspace") { ws.toggleWorkspaceLayout() }.keyboardShortcut("0", modifiers: [.command, .option])
            Divider()
            Button(ws.sidenotes ? "Footnotes at End" : "Footnotes as Sidenotes") { ws.sidenotes.toggle() }
            Menu("Appearance") {
                Button("Light") { appearance = "light"; apply("light") }
                Button("Dark") { appearance = "dark"; apply("dark") }
                Button("Auto (Match System)") { appearance = "system"; apply("system") }
            }
            Divider()
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Find in Note…") { ws.openFind() }.keyboardShortcut("f")
            Button("Find and Replace…") { ws.openFind(replace: true) }.keyboardShortcut("f", modifiers: [.command, .option])
            Button("Find Next (⌘G while finding)") { ws.findStep(1) }.disabled(!ws.finder.visible)
            Button("Find Previous (⇧⌘G while finding)") { ws.findStep(-1) }.disabled(!ws.finder.visible)
        }
        CommandMenu("Note") {
            Button(ws.currentPath.map { ws.bookmarks.contains($0) } == true ? "Remove Bookmark" : "Bookmark") { ws.toggleBookmark() }.keyboardShortcut("d", modifiers: [.command, .option])
            Button("Copy Wikilink") { ws.copyWikilink() }.keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Reveal in Finder") { ws.revealInFinder() }.keyboardShortcut("r", modifiers: [.command, .option, .shift])
            Button("Open in Obsidian") { ws.openInObsidian() }
            Divider()
            Button("Rebuild Index") { ws.reindex() }
            Button("Show Shortcut Hints") { withAnimation { ws.showHints = true } }
        }
    }

    func openVault() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.prompt = "Open Vault"
        if p.runModal() == .OK, let u = p.url { OnyxApp.remember(u); ws.open(vault: u) }
    }

}

/// Debug (ONYX_KEY_SELFTEST=1): offer every help-sheet shortcut to the window's view hierarchy
/// with the editor, then the reader, as first responder, and report which views claim it
/// before the menu bar gets a chance (i.e. which keys the text view or web view would swallow).
enum KeySelfTest {
    static let keys: [(String, UInt16, String, NSEvent.ModifierFlags)] = [
        ("⌘O", 31, "o", .command), ("⌘P", 35, "p", .command), ("⇧⌘P", 35, "p", [.command, .shift]),
        ("⌘K", 40, "k", .command), ("⇧⌘F", 3, "f", [.command, .shift]), ("⌘↩", 36, "\r", .command),
        ("⌘E", 14, "e", .command), ("⌘T", 17, "t", .command), ("⌘\\", 42, "\\", .command),
        ("⌘I", 34, "i", .command), ("⌘G", 5, "g", .command), ("⇧⌘G", 5, "g", [.command, .shift]),
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
