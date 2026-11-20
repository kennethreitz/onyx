import SwiftUI
import AppKit
import OnyxCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // ⌃⌘F belongs to focus mode; Enter Full Screen keeps its menu item and the green button.
        for delay in [0.3, 1.0, 3.0] { DispatchQueue.main.asyncAfter(deadline: .now() + delay) { Self.freeControlCommandF() } }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in Self.freeControlCommandF() }
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
        guard ws.root == nil else { return }
        // --vault never overwrites the remembered vault (so test runs stay isolated).
        let url = options.vault ?? UserDefaults.standard.string(forKey: "onyx.vault").map { URL(fileURLWithPath: $0) }
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
        if let m = options.mode { ws.mode = m }
        if let sb = options.sidebar { ws.sidebarVisible = sb; ws.sidebarPinned = sb }
        ws.sidenotes = UserDefaults.standard.object(forKey: Prefs.sidenotes) as? Bool ?? true
        if UserDefaults.standard.bool(forKey: Prefs.startFocus) { ws.toggleFocusMode() }
        ws.open(vault: url, initialNote: options.open)
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
                case "graph": ws.graphLocal = false; ws.show(.graph)
                case "local-graph": ws.graphLocal = true; ws.show(.graph)
                case "workspace": ws.toggleWorkspaceLayout()
                case "daily": ws.openDaily()
                default: break
                }
            }
        }
    }

    @CommandsBuilder var menus: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Note") { ws.newNote() }.keyboardShortcut("n")
            Button("Open Vault…") { openVault() }.keyboardShortcut("o", modifiers: [.command, .shift])
            Divider()
            Button("Quick Switcher…") { ws.show(.switcher) }.keyboardShortcut("o")
            Button("Command Palette…") { ws.show(.palette) }.keyboardShortcut("p")
        }
        CommandGroup(after: .saveItem) {
            Button("Save") { ws.flushSave() }.keyboardShortcut("s")
            Button("Move Note to Trash") { confirmTrash() }
        }
        CommandMenu("Go") {
            Button("Today’s Daily Note") { ws.openDaily() }.keyboardShortcut("t")
            Button("Today’s Daily Note ") { ws.openDaily() }.keyboardShortcut("\\")
            Button("Today’s Daily Note  ") { ws.openDaily() }.keyboardShortcut("d")
            Button("Previous Daily Note / Back") { if ws.currentPath?.hasPrefix(ws.dailyFolder + "/") == true { ws.openDaily(offset: -1) } else { ws.goBack() } }.keyboardShortcut("[")
            Button("Next Daily Note / Forward") { if ws.currentPath?.hasPrefix(ws.dailyFolder + "/") == true { ws.openDaily(offset: 1) } else { ws.goForward() } }.keyboardShortcut("]")
            Divider()
            Button("Back") { ws.goBack() }.keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Button("Forward") { ws.goForward() }.keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Button("Homepage") { ws.openHome() }.keyboardShortcut("h", modifiers: [.command, .shift])
            Divider()
            Button("Graph") { ws.graphLocal = false; ws.show(.graph) }.keyboardShortcut("g")
            Button("Local Graph") { ws.graphLocal = true; ws.show(.graph) }.keyboardShortcut("g", modifiers: [.command, .shift])
        }
        CommandGroup(after: .toolbar) {
            Button(ws.mode == .read ? "Edit Note" : "Read Note") { ws.toggleMode() }.keyboardShortcut("e")
            Button(ws.mode == .read ? "Edit Note and Save" : "Save and Read") { ws.toggleMode() }.keyboardShortcut(.return, modifiers: .command)
            Button(ws.focusMode ? "Leave Focus Mode" : "Focus Mode") { ws.toggleFocusMode() }.keyboardShortcut("f", modifiers: [.command, .control])
            Divider()
            Button("Files") { ws.toggleDockedSidebar(.files) }.keyboardShortcut("k")
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
            Button(ws.rhymesOn ? "Hide Rhymes" : "Show Rhymes") { ws.rhymesOn.toggle(); if ws.rhymesOn { ws.mode = .edit } }.keyboardShortcut("r", modifiers: [.command, .option])
            Button(ws.sidenotes ? "Footnotes at End" : "Footnotes as Sidenotes") { ws.sidenotes.toggle() }
            Menu("Appearance") {
                Button("Light") { appearance = "light"; apply("light") }
                Button("Dark") { appearance = "dark"; apply("dark") }
                Button("Auto (Match System)") { appearance = "system"; apply("system") }
            }
            Divider()
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

    func confirmTrash() {
        guard let n = ws.currentNote else { return }
        let a = NSAlert()
        a.messageText = "Move “\(n.name)” to the Trash?"
        a.informativeText = "You can restore it from the Trash in Finder."
        a.addButton(withTitle: "Move to Trash"); a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn { ws.trashCurrent() }
    }
}
