import SwiftUI
import AppKit
import OnyxCore

/// Calm by default: the typeset page, a quiet title line, a footer that dims
/// itself, and a docked file list you can put away. Everything else is
/// summoned (⌘O ⌘P ⌘K ⌘I ⌘G); ⌃⌘F is pure text.
struct RootView: View {
    @State private var copied = false
    @Bindable var ws: Workspace
    var appearance: (String) -> Void
    @AppStorage(Prefs.readerSize) private var readerSize = 19.0
    @AppStorage(Prefs.editorSize) private var editorSize = 14.0
    @AppStorage(Prefs.measure) private var measure = 41.0
    @State private var rightEdgeHover = false
    @State private var hoverSummonedInspector = false
    @State private var footerHover = false
    @State private var showLights = false
    @State private var keyMonitor: Any?
    @State private var moveMonitor: Any?
    @State private var clickMonitor: Any?
    @State private var navMonitor: Any?

    // Drag the inner edge to resize; double-click it to reset. Persisted per panel.
    static let sidebarDefault = 270.0, sidebarRange = 140.0...560.0
    static let inspectorDefault = 300.0, inspectorRange = 150.0...600.0
    @AppStorage("onyx.sidebarWidth") private var sidebarW = RootView.sidebarDefault
    @AppStorage("onyx.inspectorWidth") private var inspectorW = RootView.inspectorDefault
    @State private var resizing = false
    var sidebarWidth: CGFloat { CGFloat(min(max(sidebarW, Self.sidebarRange.lowerBound), Self.sidebarRange.upperBound)) }
    var inspectorWidth: CGFloat { CGFloat(min(max(inspectorW, Self.inspectorRange.lowerBound), Self.inspectorRange.upperBound)) }
    var leftInset: CGFloat { ws.sidebarVisible ? sidebarWidth : 0 }
    var rightInset: CGFloat { ws.inspectorPinned && ws.inspectorVisible ? inspectorWidth : 0 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.paper.ignoresSafeArea()
            SettingsOpener()
            if ws.root == nil {
                WelcomeView(ws: ws)
            } else {
                page
                    .padding(.leading, leftInset)
                    .padding(.trailing, rightInset)
                if ws.finder.visible && ws.currentPath != nil {
                    FindBar(ws: ws)
                        .padding(.top, 36).padding(.trailing, rightInset + 18)
                        .frame(maxWidth: .infinity, alignment: .topTrailing)
                        .transition(.opacity)
                }
                if !ws.focusMode {
                    titleLine.padding(.leading, leftInset).padding(.trailing, rightInset)
                    footer.padding(.leading, leftInset).padding(.trailing, rightInset)
                } else {
                    toastLayer
                }
                panels
                if ws.showHints && !ws.focusMode && ws.overlay == .none { hints.padding(.trailing, rightInset) }
                overlays
            }
        }
        .ignoresSafeArea()
        .onChange(of: ws.currentPath) { if ws.finder.visible { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { ws.runFind(reveal: false) } } }
        .onChange(of: ws.mode) {
            if ws.finder.visible {
                if ws.mode == .read { ws.finder.showReplace = false; ws.clearEditorFind() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { ws.runFind(reveal: true, fromCaret: false) }
            }
        }
        .background(WindowConfigurator(showLights: !ws.focusMode || showLights || ws.anyChrome || ws.root == nil))
        .onAppear(perform: installMonitors)
        .onDisappear { [keyMonitor, moveMonitor, clickMonitor, navMonitor] in
            if let navMonitor { NSEvent.removeMonitor(navMonitor) }
            if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            if let moveMonitor { NSEvent.removeMonitor(moveMonitor) }
        }
    }

    // MARK: Title line — the note, its folder a shade lighter

    var titleLine: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                if let n = ws.titleParts {
                    NavChevrons(ws: ws, only: .back).padding(.trailing, 3)
                    let crumbs = TitlePath.crumbs(folder: n.folder, name: n.name)
                    ForEach(Array(crumbs.enumerated()), id: \.offset) { i, c in
                        if i > 0 { Text("/").foregroundStyle(Color.faint.opacity(0.55)) }
                        switch c.kind {
                        case .folder(let path):
                            PathSegment(text: c.name, color: Color.faint.opacity(0.85), help: "Reveal \(c.name) in the sidebar") {
                                ws.revealFolder(path)
                            }
                        case .note:
                            PathSegment(text: c.name, color: Color.muted, help: "Copy [[\(c.name)]]") {
                                ws.copyWikilink(); ws.copiedFlash += 1
                            }
                        }
                    }
                    if copied {
                        Text("copied").foregroundStyle(Color.faint).transition(.opacity)
                    } else if ws.isDirty {
                        Circle().fill(Color.faint).frame(width: 4, height: 4).transition(.opacity)
                    }
                    NavChevrons(ws: ws, only: .forward).padding(.leading, 3)
                    GraphButton(ws: ws).padding(.leading, 2)
                }
            }
            .onChange(of: ws.copiedFlash) {
                withAnimation(.easeOut(duration: 0.15)) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation(.easeIn(duration: 0.3)) { copied = false } }
            }
            .font(.system(size: 12))
            .lineLimit(1).truncationMode(.head)
            .padding(.horizontal, 90)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(alignment: .top) {
                // body text scrolls up under a soft paper fade instead of colliding with the path
                LinearGradient(stops: [.init(color: Color.paper, location: 0), .init(color: Color.paper, location: 0.55), .init(color: Color.paper.opacity(0), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 46).allowsHitTesting(false)
            }
            Spacer().allowsHitTesting(false)
        }
    }

    // MARK: Footer — a quiet bar under the page; icons settle until you hover

    var footer: some View {
        VStack {
            Spacer()
            HStack(spacing: 1) {
                HStack(spacing: 1) {
                    FooterButton(symbol: "sidebar.left", help: "Files (⌘K)", on: ws.sidebarVisible) { ws.toggleDockedSidebar(.files) }
                    FooterButton(symbol: "magnifyingglass", help: "Quick switcher (⌘O) · search (⇧⌘F)") { ws.show(.switcher) }
                    FooterButton(symbol: "circle.hexagongrid", help: "Graph (⌘G)", on: ws.overlay == .graph) { ws.graphAtlas = false; ws.show(.graph) }
                    FooterButton(symbol: "rectangle.split.2x1", help: "Split (⌘D) · stacked (⇧⌘D) · close pane (⌘W)", on: ws.isSplit) { ws.split(.vertical) }
                    FooterButton(symbol: "rectangle.split.3x1", help: "Three-pane workspace (⌥⌘0)", on: ws.sidebarVisible && ws.inspectorPinned && ws.inspectorVisible) { ws.toggleWorkspaceLayout() }
                    FooterButton(symbol: ws.mode == .read ? "pencil" : "book", help: ws.mode == .read ? "Edit (⌘↩)" : "Save and read (⌘↩)") { ws.toggleMode() }
                    FooterButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Focus mode (⌃⌘F)") { ws.toggleFocusMode() }
                }
                .opacity(footerHover ? 1 : 0.55)
                Spacer()
                if let t = ws.toast {
                    Text(t).font(.system(size: 11.5)).foregroundStyle(Color.muted).lineLimit(1)
                        .transition(.opacity)
                        .task(id: t) { try? await Task.sleep(nanoseconds: 2_800_000_000); withAnimation { ws.toast = nil } }
                    Spacer()
                }
                syncDot.padding(.trailing, 6)
                if let s = ws.obsidianSync { SyncBadge(sync: s) { ws.show(.syncLog) }.padding(.trailing, 6) }
                if let g = ws.git { GitBadge(git: g, openSourceControl: { ws.toggleSidebar(.git) }) { ws.show(.syncLog) }.padding(.trailing, 6) }
                if ws.currentPath != nil {
                    Text(countText).font(.system(size: 11).monospacedDigit()).foregroundStyle(Color.faint).padding(.trailing, 8)
                }
                FooterButton(symbol: "sidebar.right", help: "Inspector (⌘I)", on: ws.inspectorVisible) { ws.toggleInspector() }
                    .opacity(footerHover ? 1 : 0.55)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(Color.secondaryPaper)
            .overlay(alignment: .top) { Rectangle().fill(Color.hairline).frame(height: 0.8) }
            .animation(.easeOut(duration: 0.2), value: footerHover)
            .onHover { footerHover = $0 }
        }
    }

    var countText: String {
        let words = NoteParser.countWords(ws.text)
        var s = "\(words.formatted()) words"
        if footerHover {
            s += " · \(ws.text.count.formatted()) characters"
            if let n = ws.currentPath, let c = ws.snapshot?.backlinks[n]?.count, c > 0 { s += " · \(c) backlinks" }
        }
        return s
    }

    var toastLayer: some View {
        VStack { Spacer(); if let t = ws.toast { Text(t).font(.system(size: 11.5)).foregroundStyle(Color.muted).padding(.horizontal, 12).padding(.vertical, 6).panelChrome().padding(.bottom, 14)
            .task(id: t) { try? await Task.sleep(nanoseconds: 2_800_000_000); withAnimation { ws.toast = nil } } } }
            .frame(maxWidth: .infinity).allowsHitTesting(false)
    }

    // MARK: First-run hints

    var hints: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Onyx, in a few keys").font(Theme.serif(15, bold: true)).foregroundStyle(Color.ink)
                        Spacer()
                        Button { ws.dismissHints() } label: { Image(systemName: "xmark").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Color.faint) }.buttonStyle(.plain)
                    }
                    ForEach(ShortcutHints.all, id: \.0) { k, v in
                        HStack(spacing: 10) {
                            Text(k).font(.system(size: 11.5, design: .rounded).weight(.medium)).foregroundStyle(Color.ink).frame(width: 54, alignment: .trailing)
                            Text(v).font(.system(size: 11.5)).foregroundStyle(Color.muted)
                        }
                    }
                    Text("Every command is in the menu bar, too.").font(.system(size: 10.5)).foregroundStyle(Color.faint).padding(.top, 2)
                }
                .padding(14).frame(width: 290)
                .panelChrome()
                .padding(.trailing, 16).padding(.bottom, 42)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: Page

    @ViewBuilder var page: some View {
        ZStack {
            if ws.currentPath == nil {
                VStack(spacing: 14) {
                    if ws.isIndexing { ProgressView().controlSize(.small) }
                    Text(ws.isIndexing ? "Reading your vault…" : "Nothing open.").font(Theme.serif(19, italic: true)).foregroundStyle(Color.muted)
                    if !ws.isIndexing {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(ShortcutHints.all, id: \.0) { k, v in
                                HStack(spacing: 12) {
                                    Text(k).font(.system(size: 12, design: .rounded).weight(.medium)).foregroundStyle(Color.ink).frame(width: 56, alignment: .trailing)
                                    Text(v).font(.system(size: 12)).foregroundStyle(Color.muted)
                                }
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if ws.isSplit {
                splitPanes
            } else {
                soloNote
                    .overlay { graphOverlay(paneID: nil, clearTitle: true, clearFooter: true) }
                    .clipped()
            }
            if let disk = ws.conflict { conflictBanner(disk) }
        }
    }

    @ViewBuilder var soloNote: some View {
        if ws.isCanvas {
            CanvasView(ws: ws).transition(.opacity)
        } else if ws.isBase {
            BasesView(ws: ws).transition(.opacity)
        } else if ws.mode == .edit {
            EditorView(ws: ws, fontSize: editorSize, measure: measure).transition(.opacity)
        } else {
            ReaderView(ws: ws, fontSize: readerSize, measure: measure).transition(.opacity)
        }
    }

    /// Focus graph / atlas, clipped to one pane (or the solo page) over the note underneath.
    @ViewBuilder func graphOverlay(paneID: UUID?, clearTitle: Bool, clearFooter: Bool) -> some View {
        if ws.overlay == .graph, ws.graphOverlayPaneID == paneID {
            GraphView(ws: ws)
                .padding(.top, clearTitle ? 28 : 0)
                .padding(.bottom, clearFooter ? 30 : 0)
                .background(Color.paper)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }

    // MARK: Split panes — draggable hairline dividers; each pane keeps its own note and mode

    @ViewBuilder var splitPanes: some View {
        GeometryReader { geo in
            let vertical = ws.splitAxis == .vertical
            let total = vertical ? geo.size.width : geo.size.height
            let sizes = ws.paneSizes(along: total)
            let layout = vertical ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            layout {
                ForEach(Array(ws.panes.enumerated()), id: \.element.id) { i, pane in
                    if i > 0 {
                        SplitPaneDivider(ws: ws, index: i - 1, total: total)
                    }
                    paneView(i, pane)
                        .frame(width: vertical ? (i < sizes.count ? sizes[i] : nil) : nil,
                               height: vertical ? nil : (i < sizes.count ? sizes[i] : nil),
                               alignment: .topLeading)
                        .frame(maxWidth: vertical ? nil : .infinity, maxHeight: vertical ? .infinity : nil)
                        .background(GeometryReader { g in
                            Color.clear
                                .onAppear { ws.paneFrames[pane.id] = g.frame(in: .global) }
                                .onChange(of: g.frame(in: .global)) { ws.paneFrames[pane.id] = g.frame(in: .global) }
                        })
                        // Don't use .opacity on the pane: WKWebView goes blank inside an opacity group.
                        .overlay {
                            if i != ws.focusedPane, !(ws.overlay == .graph && ws.graphOverlayPaneID == pane.id) {
                                Color.paper.opacity(0.14).allowsHitTesting(false)
                            }
                        }
                        .overlay {
                            graphOverlay(paneID: pane.id,
                                         clearTitle: !vertical ? i == 0 : true,
                                         clearFooter: !vertical ? i == ws.panes.count - 1 : true)
                        }
                        .clipped()
                }
            }
        }
        .onDisappear { ws.paneFrames = [:] }
    }

    @ViewBuilder func paneView(_ i: Int, _ pane: Pane) -> some View {
        if pane.isGraph {
            GraphView(ws: ws, docked: true).id("\(pane.id)-g").padding(.top, 28)
        } else { notePane(i, pane) }
    }
    @ViewBuilder func notePane(_ i: Int, _ pane: Pane) -> some View {
        let focused = i == ws.focusedPane
        let mode = focused ? ws.mode : pane.mode
        let src: (path: String?, text: String)? = focused ? nil : (pane.path, ws.displayText(pane))
        if (focused ? ws.currentPath : pane.path)?.isCanvasPath == true {
            CanvasView(ws: ws, source: src).id("\(pane.id)-c")
        } else if (focused ? ws.currentPath : pane.path)?.isBasePath == true {
            BasesView(ws: ws, source: src).id("\(pane.id)-b")
        } else if mode == .edit {
            EditorView(ws: ws, fontSize: editorSize, measure: measure, source: src, paneID: focused ? nil : pane.id).id("\(pane.id)-e")
        } else {
            ReaderView(ws: ws, fontSize: readerSize, measure: measure, source: src, paneID: focused ? nil : pane.id).id("\(pane.id)-r")
        }
    }

    func conflictBanner(_ disk: String) -> some View {
        VStack {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Color.muted)
                Text("This note changed elsewhere while you were editing.").font(.system(size: 12))
                Spacer()
                Button("Use theirs") { ws.resolveConflict(keepMine: false) }
                Button("Keep mine") { ws.resolveConflict(keepMine: true) }.keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .frame(maxWidth: 620)
            .panelChrome()
            .padding(.top, 40)
            Spacer()
        }.frame(maxWidth: .infinity).transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: Panels

    @ViewBuilder var panels: some View {
        HStack(alignment: .top, spacing: 0) {
            if ws.sidebarVisible {
                SidebarView(ws: ws)
                    .frame(width: sidebarWidth)
                    .padding(.top, 28)
                    .panelChrome(pinned: true)
                    .overlay(alignment: .trailing) {
                        ResizeHandle(width: $sidebarW, range: Self.sidebarRange, defaultWidth: Self.sidebarDefault, growsRight: true,
                                     showLine: true, dragging: $resizing).offset(x: 4.5)
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            Spacer(minLength: 0)
            if ws.inspectorVisible {
                InspectorView(ws: ws)
                    .frame(width: inspectorWidth)
                    .padding(.top, ws.inspectorPinned ? 28 : 0)
                    .panelChrome(pinned: ws.inspectorPinned)
                    .overlay(alignment: .leading) {
                        ResizeHandle(width: $inspectorW, range: Self.inspectorRange, defaultWidth: Self.inspectorDefault, growsRight: false,
                                     showLine: ws.inspectorPinned, dragging: $resizing).offset(x: -4.5)
                    }
                    .padding(ws.inspectorPinned ? 0 : 10)
                    .padding(.top, ws.inspectorPinned ? 0 : 28)
                    .onHover { inside in
                        if !inside && hoverSummonedInspector && !ws.inspectorPinned {
                            Task { try? await Task.sleep(nanoseconds: 450_000_000); if hoverSummonedInspector && !ws.inspectorPinned && !rightEdgeHover && !resizing { hoverSummonedInspector = false; if ws.inspectorVisible { ws.toggleInspector() } } }
                        }
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxHeight: .infinity)
        .onChange(of: ws.inspectorVisible) { if !ws.inspectorVisible { hoverSummonedInspector = false } }
    }

    /// A breath of ink when something outside Onyx (Obsidian Sync, git, a bot) changes the vault.
    var syncDot: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: ws.externalPulse == nil)) { tl in
            let age = ws.externalPulse.map { tl.date.timeIntervalSince($0) } ?? 99
            let o = age < 2.4 ? max(0, 1 - age / 2.4) : 0
            Circle().fill(Color.cursorBlue).frame(width: 6, height: 6).opacity(o * 0.9)
                .help(ws.lastExternalChange.map { "Vault changed outside Onyx \($0.formatted(.relative(presentation: .named)))" } ?? "")
        }
    }

    // MARK: Overlays

    @ViewBuilder var overlays: some View {
        switch ws.overlay {
        case .switcher:
            dimmer
            VStack {
                PaletteView(placeholder: "Find or create a note…", items: { PaletteCommands.notes(ws, $0) },
                            onCreate: { _ = ws.createNote(named: $0, folder: "") }, exists: { ws.quickIndex.hasExact($0) },
                            dismiss: { ws.show(.none) })
                    .padding(.top, 88)
                Spacer()
            }.frame(maxWidth: .infinity).transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
        case .palette:
            dimmer
            VStack {
                PaletteView(placeholder: "Type a command…", items: { PaletteCommands.filter(PaletteCommands.all(ws, appearance: appearance), $0) }, dismiss: { ws.show(.none) })
                    .padding(.top, 88)
                Spacer()
            }.frame(maxWidth: .infinity).transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
        case .moveTo:
            dimmer
            VStack {
                if !ws.moveSources.isEmpty {
                    let srcs = ws.moveSources
                    let name = TreeSelection.describe(srcs)
                    PaletteView(placeholder: srcs.count == 1 ? "Move “\(name)” to…" : "Move \(name) to…", items: { PaletteCommands.folders(ws, for: srcs, $0) },
                                onCreate: { f in
                                    let folder = f.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
                                    ws.show(.none)
                                    if let r = ws.root { try? FileManager.default.createDirectory(at: r.appendingPathComponent(folder), withIntermediateDirectories: true) }
                                    ws.move(srcs, toFolder: folder)
                                },
                                exists: { q in ws.snapshot?.folders.contains(q.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))) ?? false },
                                noun: "folder", openVerb: "move", allowSplit: false,
                                dismiss: { ws.show(.none) })
                        .padding(.top, 88)
                }
                Spacer()
            }.frame(maxWidth: .infinity).transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
        case .syncLog:
            dimmer
            VStack {
                SyncLogView(store: ws.syncLog, dismiss: { ws.show(.none) })
                    .padding(.top, 72)
                Spacer()
            }.frame(maxWidth: .infinity).transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
        case .graph:
            // Drawn on the focused pane (or the solo page), not over the window.
            EmptyView()
        case .none:
            EmptyView()
        }
    }

    var dimmer: some View {
        Color.black.opacity(0.06).ignoresSafeArea().contentShape(Rectangle())
            .onTapGesture { ws.show(.none) }
            .transition(.opacity)
    }

    // MARK: Events

    func installMonitors() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if ProcessInfo.processInfo.environment["ONYX_DEBUG_KEYS"] != nil {
                let key = e.charactersIgnoringModifiers ?? "?"
                let fr = String(describing: type(of: NSApp.keyWindow?.firstResponder ?? NSObject()))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    print("[key] \(e.keyCode) '\(key)' fr=\(fr) → overlay=\(ws.overlay) atlas=\(ws.graphAtlas) mode=\(ws.mode) sidebar=\(ws.sidebarVisible)/\(ws.sidebarPinned)/\(ws.sidebarTab) inspector=\(ws.inspectorVisible) focus=\(ws.focusMode) panes=\(ws.panes.count)/\(ws.splitAxis) note=\(ws.currentPath ?? "-")")
                    fflush(stdout)
                }
            }
            // ⇧⌘P: the command palette too, for VS Code hands (⌘P is the menu item)
            let mods = e.modifierFlags.intersection([.command, .shift, .option, .control])
            // ⌘F find in the note · ⌥⌘F with replace (editor). While the find bar is open,
            // ⌘G/⇧⌘G and ↩/⇧↩ (in its field) step through matches and Esc closes it;
            // otherwise ⌘G is Focus graph.
            if e.window != nil, e.window === MainWindow.current, ws.overlay == .none, ws.currentPath != nil {
                let key = e.charactersIgnoringModifiers?.lowercased()
                if key == "f", mods == [.command] || mods == [.command, .option] {
                    ws.openFind(replace: mods.contains(.option)); return nil
                }
                if ws.finder.visible {
                    if key == "g", mods == [.command] || mods == [.command, .shift] { ws.findStep(mods.contains(.shift) ? -1 : 1); return nil }
                    if e.keyCode == 36 || e.keyCode == 76, ws.finder.fieldFocused, !(e.window?.firstResponder is OnyxTextView),
                       mods == [.shift] || (mods.isEmpty && ws.finder.findFieldActive) {
                        ws.findStep(mods == [.shift] ? -1 : 1); return nil
                    }
                }
            }
            if mods == [.command, .shift], e.charactersIgnoringModifiers?.lowercased() == "p" {
                ws.overlay == .palette ? ws.show(.none) : ws.show(.palette); return nil
            }
            // ⌘W: close the focused pane when split; otherwise let the window close
            // (keyed to the main Onyx window, so ⌘W in Settings still closes Settings)
            if mods == [.command], e.charactersIgnoringModifiers?.lowercased() == "w", ws.isSplit,
               e.window != nil, e.window === MainWindow.current, ws.overlay == .none {
                ws.closePane(); return nil
            }
            // ⌘I: the inspector, even while the editor has focus (NSTextView otherwise
            // swallows ⌘I before the menu sees it, so a docked inspector couldn't be put away).
            if mods == [.command], e.charactersIgnoringModifiers?.lowercased() == "i",
               e.window != nil, e.window === MainWindow.current {
                ws.toggleInspector(); return nil
            }
            // ⌘[ / ⌘]: back/forward. Here as well as in the Go menu so the web view and the
            // text view can never claim them first; not while a palette or sheet is up.
            if mods == [.command], let ch = e.charactersIgnoringModifiers, ch == "[" || ch == "]",
               e.window != nil, e.window === MainWindow.current, ws.overlay == .none || ws.overlay == .graph {
                ch == "[" ? ws.goBack() : ws.goForward(); return nil
            }
            // ⌘⌫ right after clicking in the file tree deletes the tree selection (one confirm)
            if mods == [.command], e.keyCode == 51, ws.treeFocused, ws.sidebarVisible, ws.sidebarTab == .files,
               ws.treeSelection.count > 0, ws.overlay == .none, e.window != nil, e.window === MainWindow.current {
                let sel = TreeSelection.roots(ws.treeSelection.selected)
                DispatchQueue.main.async { ws.confirmTrash(sel) }
                return nil
            }
            if e.keyCode == 53, mods.isEmpty || mods == [.shift] { // Esc (Shift-Esc is the same)
                return ws.handleEscape(eventWindow: e.window) ? nil : e
            }
            return e
        }
        // Back/forward: mouse buttons 4/5, three-finger swipe ("swipe between pages"), and a
        // two-finger horizontal swipe when the system setting allows it.
        navMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .swipe, .scrollWheel]) { e in
            guard e.window != nil, e.window === MainWindow.current else { return e }
            switch e.type {
            case .otherMouseDown:
                if e.buttonNumber == 3 { ws.goBack(); return nil }
                if e.buttonNumber == 4 { ws.goForward(); return nil }
            case .swipe:
                if e.deltaX > 0 { ws.goBack(); return nil }
                if e.deltaX < 0 { ws.goForward(); return nil }
            case .scrollWheel:
                guard ws.overlay == .none, !ws.isCanvas, e.phase == .began, NSEvent.isSwipeTrackingFromScrollEventsEnabled,
                      abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) * 2, ws.canGoBack || ws.canGoForward else { return e }
                var fired = false
                e.trackSwipeEvent(options: [.lockDirection, .clampGestureAmount],
                                  dampenAmountThresholdMin: ws.canGoForward ? -1 : 0, max: ws.canGoBack ? 1 : 0) { amount, phase, complete, _ in
                    // positive amount = fingers moving right = back, as in Safari
                    if phase == .ended, !fired, abs(amount) >= 0.5 {
                        fired = true
                        DispatchQueue.main.async { amount > 0 ? ws.goBack() : ws.goForward() }
                    }
                    _ = complete
                }
                return nil
            default: break
            }
            return e
        }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { e in
            // any click clears "tree focus"; a tree row's own tap sets it again right after
            if e.type == .leftMouseDown { ws.treeFocused = false }
            // a click in an unfocused pane focuses it first, then the click lands as usual
            // (allowed while the graph overlay is up, so other panes stay reachable)
            guard ws.isSplit, ws.overlay == .none || ws.overlay == .graph, let w = e.window, let content = w.contentView else { return e }
            let p = CGPoint(x: e.locationInWindow.x, y: content.bounds.height - e.locationInWindow.y)
            if let i = ws.panes.firstIndex(where: { ws.paneFrames[$0.id]?.contains(p) == true }), i != ws.focusedPane {
                if ws.overlay == .graph, ws.graphOverlayPaneID == ws.panes[i].id { return e }
                ws.focusPane(i)
            }
            return e
        }
        moveMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { e in
            guard ws.focusMode, let w = e.window, let content = w.contentView else { return e }
            let nearTop = e.locationInWindow.y > content.bounds.height - 44
            if nearTop != showLights { withAnimation(.easeOut(duration: 0.18)) { showLights = nearTop } }
            return e
        }
    }
}

struct FooterButton: View {
    var symbol: String
    var help: String
    var on: Bool = false
    var action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: on ? .medium : .regular))
                .foregroundStyle(on || hover ? Color.ink : Color.faint)
                .frame(width: 22, height: 22)
                .background(hover ? Color.ink.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help).onHover { hover = $0 }
    }
}

enum ShortcutHints {
    static let all: [(String, String)] = [
        ("⌘O", "Find or create a note"), ("⌘P", "Every command (also ⇧⌘P)"), ("⌘K", "Show or hide the sidebar"), ("⇧⌘F", "Search the vault"),
        ("⌘↩", "Read ⇄ edit, saving (also ⌘E)"), ("⌘T", "Today’s daily note (also ⌘\\)"), ("⌘I", "Outline, backlinks, properties"),
        ("⌘G", "Focus graph overlay · ⇧⌘G atlas · Esc closes it · ⌥⌘G graph in a pane (title-bar button: ⇧-click for the atlas)"), ("⌘[  ⌘]", "Back · forward (mouse buttons, swipe)"), ("⌘⌫", "Delete note · or the sidebar selection"), ("⇧⌘M", "Move note to… (links follow)"), ("⌘D", "Split · ⇧⌘D stacked · ⌘W close"), ("⌘F", "Find in note · ⌥⌘F replace · ⌘G/⇧⌘G or ↩/⇧↩ next/previous while finding"), ("⌃⌘F", "Focus: just the text"), ("Esc", "Put things away · in the editor, return to reading"),
    ]
}

/// The window hosting the workspace (not Settings, not a panel), for window-scoped shortcuts.
@MainActor enum MainWindow { static weak var current: NSWindow? }

/// Transparent, hidden titlebar; the traffic lights only appear when you reach for them.
struct WindowConfigurator: NSViewRepresentable {
    var showLights: Bool
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { configure(v.window) }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) { DispatchQueue.main.async { configure(v.window) } }
    func configure(_ w: NSWindow?) {
        guard let w else { return }
        MainWindow.current = w
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.styleMask.insert(.fullSizeContentView)
        w.isMovableByWindowBackground = false
        w.backgroundColor = Theme.paper
        w.acceptsMouseMovedEvents = true
        w.tabbingMode = .disallowed
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let btn = w.standardWindowButton(b) else { continue }
            NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.18; btn.animator().alphaValue = showLights ? 1 : 0 }
        }
        if WindowConfigurator.idFile != nil { WindowConfigurator.writeWindowID(w) }
    }
    nonisolated(unsafe) static var idFile: String?
    static func writeWindowID(_ w: NSWindow) {
        guard let f = idFile else { return }
        // Screenshot runs on a machine someone is using: ONYX_SHOT_QUIET=1 parks the window off
        // screen and deaf to the pointer, so it neither covers their work nor sprouts hover cards.
        // It must never save that frame: the shot app shares the real app's defaults, and a saved
        // off-screen frame would open the next real window off screen. So: no autosave, no
        // restoration, then park it (at the --size asked for, which a restored frame would override).
        if ProcessInfo.processInfo.environment["ONYX_SHOT_QUIET"] == "1", !w.ignoresMouseEvents {
            w.setFrameAutosaveName("")
            w.isRestorable = false
            w.ignoresMouseEvents = true
            let a = CommandLine.arguments
            if let i = a.firstIndex(of: "--size"), a.indices.contains(i + 1) {
                let p = a[i + 1].split(separator: "x").compactMap { Double($0) }
                if p.count == 2 { w.setContentSize(NSSize(width: p[0], height: p[1])) }
            }
            w.setFrameOrigin(NSPoint(x: -w.frame.width - 3000, y: 0))
        }
        try? String(w.windowNumber).write(toFile: f, atomically: true, encoding: .utf8)
    }
}

struct WelcomeView: View {
    @Bindable var ws: Workspace
    var body: some View {
        VStack(spacing: 18) {
            Text("Onyx").font(Theme.titleSerif(44)).foregroundStyle(Color.ink)
            Text("Write like iA Writer. Read like a LaTeX paper.").font(Theme.serif(16, italic: true)).foregroundStyle(Color.muted)
            HStack(spacing: 12) {
                Button("Open Vault…") { pick() }.keyboardShortcut(.defaultAction)
                let notes = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Notes")
                if FileManager.default.fileExists(atPath: notes.path) {
                    Button("Open ~/Notes") { OnyxApp.remember(notes); ws.open(vault: notes) }
                }
            }.controlSize(.large).padding(.top, 8)
            Text("Any folder of Markdown files works, including an Obsidian vault.").font(.system(size: 11.5)).foregroundStyle(Color.faint)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    func pick() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.prompt = "Open Vault"
        if p.runModal() == .OK, let u = p.url { OnyxApp.remember(u); ws.open(vault: u) }
    }
}


/// One clickable piece of the title path: quiet until hovered, then underlined with a pointer.
/// The quiet ‹ › flanking the title path (‹ folder / Note ›), side by side in the graph header. Dim when there's
/// nowhere to go; a hint of ink on hover.
/// The footer's tiny git state: synced ✓, syncing ↻, offline, conflict (tinted), local only.
struct GitBadge: View {
    var git: GitSync
    var openSourceControl: () -> Void = {}
    var action: () -> Void
    var body: some View {
        let (symbol, color): (String, Color) = switch git.state {
            case .synced: ("checkmark.circle", Color.faint)
            case .committing, .pulling: ("arrow.triangle.2.circlepath", Color.faint)
            case .pushing: ("arrow.up.circle", Color.faint)
            case .offline: ("wifi.slash", Color.faint)
            case .localOnly: ("circle.dashed", Color.faint)
            case .conflict: ("exclamationmark.triangle", Color.orange.opacity(0.85))
            case .failed: ("exclamationmark.circle", Color.orange.opacity(0.85))
        }
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10.5)).foregroundStyle(color).frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
        .help(git.help + "\nClick for the sync log")
        .accessibilityLabel(git.help)
        .contextMenu {
            Button("Show Sync Log") { action() }
            Button("Source Control") { openSourceControl() }
        }
    }
}

/// The title bar's graph button, right of the forward chevron: click for the focus graph of this
/// note (⌘G), ⇧-click or right-click for the atlas (⇧⌘G); hovering shows this note's graph card.
/// The footer's graph icon stays.
struct GraphButton: View {
    @Bindable var ws: Workspace
    @State private var hover = false
    func open(atlas: Bool) {
        ws.graphAtlas = atlas
        if ws.overlay != .graph { ws.show(.graph) }
    }
    var body: some View {
        Button { GraphPreviewController.shared.close(); open(atlas: NSEvent.modifierFlags.contains(.shift)) } label: {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(hover ? Color.ink : Color.muted)
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.ink.opacity(hover ? 0.06 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // hover ~400 ms: the same graph card as links, for the note you're on
        .background { if let p = ws.currentPath { GraphPreviewTrigger(ws: ws, path: p) } }
        .contextMenu {
            Button("Focus Graph (This Note)  ⌘G") { open(atlas: false) }
            Button("Atlas (Whole Vault)  ⇧⌘G") { open(atlas: true) }
        }
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .help("Focus graph (⌘G) · ⇧-click or right-click for the atlas (⇧⌘G)")
        .accessibilityLabel("Graph")
    }
}

struct NavChevrons: View {
    enum Which { case both, back, forward }
    @Bindable var ws: Workspace
    var only: Which = .both
    var body: some View {
        HStack(spacing: 1) {
            if only != .forward { chevron("chevron.left", enabled: ws.canGoBack, help: "Back (⌘[)") { ws.goBack() } }
            if only != .back { chevron("chevron.right", enabled: ws.canGoForward, help: "Forward (⌘])") { ws.goForward() } }
        }
    }
    func chevron(_ symbol: String, enabled: Bool, help: String, action: @escaping () -> Void) -> some View {
        NavChevronButton(symbol: symbol, enabled: enabled, action: action).help(help)
    }
}

struct NavChevronButton: View {
    var symbol: String
    var enabled: Bool
    var action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(enabled ? (hover ? Color.ink : Color.muted) : Color.faint.opacity(0.4))
                .frame(width: 18, height: 20)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.ink.opacity(hover && enabled ? 0.06 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
    }
}

struct PathSegment: View {
    let text: String
    let color: Color
    let help: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Text(text)
            .foregroundStyle(hover ? Color.ink.opacity(0.75) : color)
            .underline(hover, color: Color.faint.opacity(0.7))
            .contentShape(Rectangle())
            .onHover { h in
                hover = h
                if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .onTapGesture(perform: action)
            .help(help)
    }
}


/// The hairline between two split panes. A 9pt hit area, a resize cursor on hover,
/// drag to move the split (240pt minimum), double-click to equalize every pane.
struct SplitPaneDivider: View {
    @Bindable var ws: Workspace
    let index: Int
    let total: CGFloat
    @State private var hover = false
    @State private var dragging = false
    @State private var start: [Double]? = nil
    @State private var cursorPushed = false

    var body: some View {
        let vertical = ws.splitAxis == .vertical
        ZStack {
            Rectangle().fill(Color.hairline)
                .frame(width: vertical ? 0.8 : nil, height: vertical ? nil : 0.8)
                .padding(vertical ? .vertical : .horizontal, vertical ? 0 : 24)
            Capsule().fill(Color.ink.opacity(dragging ? 0.34 : hover ? 0.22 : 0))
                .frame(width: vertical ? 3 : 36, height: vertical ? 36 : 3)
                .animation(.easeOut(duration: 0.15), value: hover || dragging)
        }
        .frame(width: vertical ? 0.8 : nil, height: vertical ? nil : 0.8)
        .frame(maxWidth: vertical ? nil : .infinity, maxHeight: vertical ? .infinity : nil)
        .overlay {
            Color.clear
                .frame(width: vertical ? 9 : nil, height: vertical ? nil : 9)
                .frame(maxWidth: vertical ? nil : .infinity, maxHeight: vertical ? .infinity : nil)
                .contentShape(Rectangle())
                .onHover { h in hover = h; updateCursor() }
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { v in
                            if start == nil { start = ws.paneRatios; dragging = true; updateCursor() }
                            let delta = vertical ? v.translation.width : v.translation.height
                            ws.resizePanes(from: start ?? ws.paneRatios, divider: index, delta: delta, total: total)
                        }
                        .onEnded { _ in
                            start = nil; dragging = false; updateCursor()
                            ws.persistSplitLayout()
                        }
                )
                .onTapGesture(count: 2) { ws.equalizePanes() }
        }
        .zIndex(1)
        .help("Drag to resize · double-click to equalize")
        .onDisappear { if cursorPushed { NSCursor.pop(); cursorPushed = false } }
    }

    private func updateCursor() {
        let want = hover || dragging
        if want && !cursorPushed {
            (ws.splitAxis == .vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
            cursorPushed = true
        } else if !want && cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
    }
}

/// The inner edge of a panel: a hairline that shows a small grip and a resize cursor on hover.
/// Drag to resize (clamped to `range`), double-click to go back to the default width.
struct ResizeHandle: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    let defaultWidth: Double
    let growsRight: Bool          // left sidebar: dragging right grows it; inspector: dragging left
    let showLine: Bool
    @Binding var dragging: Bool
    @State private var hover = false
    @State private var start: Double? = nil
    @State private var cursorPushed = false

    var body: some View {
        ZStack {
            Rectangle().fill(showLine ? Color.hairline : .clear).frame(width: 0.8)
            Capsule().fill(Color.ink.opacity(dragging ? 0.34 : hover ? 0.22 : 0))
                .frame(width: 3, height: 36)
                .animation(.easeOut(duration: 0.15), value: hover || dragging)
        }
        .frame(width: 9)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { h in hover = h; updateCursor() }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { v in
                    if start == nil { start = width; dragging = true; updateCursor() }
                    let dx = Double(v.translation.width) * (growsRight ? 1 : -1)
                    width = min(range.upperBound, max(range.lowerBound, (start ?? width) + dx)).rounded()
                }
                .onEnded { _ in start = nil; dragging = false; updateCursor() }
        )
        .onTapGesture(count: 2) { withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) { width = defaultWidth } }
        .help("Drag to resize · double-click to reset")
        .onDisappear { if cursorPushed { NSCursor.pop(); cursorPushed = false } }
    }

    private func updateCursor() {
        let want = hover || dragging
        if want && !cursorPushed { NSCursor.resizeLeftRight.push(); cursorPushed = true }
        else if !want && cursorPushed { NSCursor.pop(); cursorPushed = false }
    }
}
