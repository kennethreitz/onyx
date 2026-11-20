import SwiftUI
import AppKit
import OnyxCore

/// Calm by default: the typeset page, a quiet title line, a footer that dims
/// itself, and a docked file list you can put away. Everything else is
/// summoned (⌘O ⌘P ⌘K ⌘I ⌘G, or the window edges); ⌃⌘F is pure text.
struct RootView: View {
    @State private var copied = false
    @Bindable var ws: Workspace
    var appearance: (String) -> Void
    @AppStorage(Prefs.readerSize) private var readerSize = 19.0
    @AppStorage(Prefs.editorSize) private var editorSize = 14.0
    @AppStorage(Prefs.measure) private var measure = 41.0
    @State private var leftEdgeHover = false
    @State private var rightEdgeHover = false
    @State private var leftEdgeArmed = true   // disarmed by a hide until the pointer leaves the edge
    @State private var hoverSummonedSidebar = false
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
    var leftInset: CGFloat { ws.sidebarPinned && ws.sidebarVisible ? sidebarWidth : 0 }
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
                if !ws.focusMode {
                    titleLine.padding(.leading, leftInset).padding(.trailing, rightInset)
                    footer.padding(.leading, leftInset).padding(.trailing, rightInset)
                } else {
                    toastLayer
                }
                edges
                panels
                if ws.showHints && !ws.focusMode && ws.overlay == .none { hints.padding(.trailing, rightInset) }
                overlays
            }
        }
        .ignoresSafeArea()
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
                if let n = ws.currentNote {
                    NavChevrons(ws: ws, only: .back).padding(.trailing, 3)
                    let parts = n.folder.isEmpty ? [] : n.folder.split(separator: "/").map(String.init)
                    ForEach(Array(parts.enumerated()), id: \.offset) { i, name in
                        PathSegment(text: name, color: Color.faint.opacity(0.85), help: "Reveal \(name) in the sidebar") {
                            ws.revealFolder(parts[0...i].joined(separator: "/"))
                        }
                        Text("/").foregroundStyle(Color.faint.opacity(0.55))
                    }
                    PathSegment(text: n.name, color: Color.muted, help: "Copy [[\(n.name)]]") {
                        ws.copyWikilink(); ws.copiedFlash += 1
                    }
                    if copied {
                        Text("copied").foregroundStyle(Color.faint).transition(.opacity)
                    } else if ws.isDirty {
                        Circle().fill(Color.faint).frame(width: 4, height: 4).transition(.opacity)
                    }
                    NavChevrons(ws: ws, only: .forward).padding(.leading, 3)
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

    // MARK: Footer — quiet affordances that come up when you reach for them

    var footer: some View {
        VStack {
            Spacer()
            HStack(spacing: 2) {
                FooterButton(symbol: "sidebar.left", help: "Files (⌘K)", on: ws.sidebarVisible) { ws.toggleDockedSidebar(.files) }
                FooterButton(symbol: "magnifyingglass", help: "Quick switcher (⌘O) · search (⇧⌘F)") { ws.show(.switcher) }
                FooterButton(symbol: "circle.hexagongrid", help: "Graph (⌘G)", on: ws.overlay == .graph) { ws.graphAtlas = false; ws.show(.graph) }
                FooterButton(symbol: "rectangle.split.2x1", help: "Split (⌘D) · stacked (⇧⌘D) · close pane (⌘W)", on: ws.isSplit) { ws.split(.vertical) }
                FooterButton(symbol: "rectangle.split.3x1", help: "Three-pane workspace (⌥⌘0)", on: ws.sidebarPinned && ws.inspectorPinned && ws.sidebarVisible && ws.inspectorVisible) { ws.toggleWorkspaceLayout() }
                FooterButton(symbol: ws.mode == .read ? "pencil" : "book", help: ws.mode == .read ? "Edit (⌘↩)" : "Save and read (⌘↩)") { ws.toggleMode() }
                FooterButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Focus mode (⌃⌘F)") { ws.toggleFocusMode() }
                Spacer()
                if let t = ws.toast {
                    Text(t).font(.system(size: 11.5)).foregroundStyle(Color.muted).lineLimit(1)
                        .transition(.opacity)
                        .task(id: t) { try? await Task.sleep(nanoseconds: 2_800_000_000); withAnimation { ws.toast = nil } }
                    Spacer()
                }
                syncDot.padding(.trailing, 6)
                if let s = ws.obsidianSync { SyncBadge(sync: s).padding(.trailing, 6) }
                if let g = ws.git { GitBadge(git: g) { ws.toggleSidebar(.git) }.padding(.trailing, 6) }
                if ws.currentPath != nil {
                    Text(countText).font(.system(size: 11).monospacedDigit()).foregroundStyle(Color.faint).padding(.trailing, 8)
                }
                FooterButton(symbol: "sidebar.right", help: "Inspector (⌘I)", on: ws.inspectorVisible) { ws.toggleInspector() }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Color.paper.opacity(footerHover ? 0.96 : 0))
            .opacity(footerHover ? 1 : 0.42)
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
        if ws.rhymesOn { s += " · ♪" }
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
            } else if ws.mode == .edit {
                EditorView(ws: ws, fontSize: editorSize, measure: measure).transition(.opacity)
            } else {
                ReaderView(ws: ws, fontSize: readerSize, measure: measure).transition(.opacity)
            }
            if let disk = ws.conflict { conflictBanner(disk) }
        }
    }

    // MARK: Split panes — hairline dividers; each pane keeps its own note and mode

    @ViewBuilder var splitPanes: some View {
        let layout = ws.splitAxis == .vertical ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
        layout {
            ForEach(Array(ws.panes.enumerated()), id: \.element.id) { i, pane in
                if i > 0 {
                    Rectangle().fill(Color.hairline)
                        .frame(width: ws.splitAxis == .vertical ? 0.8 : nil, height: ws.splitAxis == .horizontal ? 0.8 : nil)
                        .padding(ws.splitAxis == .vertical ? .vertical : .horizontal, ws.splitAxis == .vertical ? 0 : 24)
                }
                paneView(i, pane)
                    .padding(.top, ws.splitAxis == .horizontal && i > 0 ? 8 : 0)
                    .background(GeometryReader { g in
                        Color.clear
                            .onAppear { ws.paneFrames[pane.id] = g.frame(in: .global) }
                            .onChange(of: g.frame(in: .global)) { ws.paneFrames[pane.id] = g.frame(in: .global) }
                    })
                    .opacity(i == ws.focusedPane ? 1 : 0.86)
            }
        }
        .onDisappear { ws.paneFrames = [:] }
    }

    @ViewBuilder func paneView(_ i: Int, _ pane: Pane) -> some View {
        let focused = i == ws.focusedPane
        let mode = focused ? ws.mode : pane.mode
        let src: (path: String?, text: String)? = focused ? nil : (pane.path, ws.displayText(pane))
        if mode == .edit {
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

    // MARK: Hover edges

    var edges: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 8).contentShape(Rectangle())
                .onHover { inside in
                    leftEdgeHover = inside
                    if !inside { leftEdgeArmed = true }
                    guard inside, leftEdgeArmed, !ws.sidebarVisible else { return }
                    Task { try? await Task.sleep(nanoseconds: 220_000_000); if leftEdgeHover && !ws.sidebarVisible { hoverSummonedSidebar = true; ws.toggleSidebar(.files) } }
                }
            // No right-edge hover: a pointer parked at the window's right edge kept
            // re-summoning the inspector the moment it was hidden. ⌘I / the footer button own it.
            Spacer()
        }
        .padding(.top, 40).padding(.bottom, 40)
    }

    // MARK: Panels

    @ViewBuilder var panels: some View {
        HStack(alignment: .top, spacing: 0) {
            if ws.sidebarVisible {
                SidebarView(ws: ws)
                    .frame(width: sidebarWidth)
                    .padding(.top, ws.sidebarPinned ? 28 : 0)
                    .panelChrome(pinned: ws.sidebarPinned)
                    .overlay(alignment: .trailing) {
                        ResizeHandle(width: $sidebarW, range: Self.sidebarRange, defaultWidth: Self.sidebarDefault, growsRight: true,
                                     showLine: ws.sidebarPinned, dragging: $resizing).offset(x: 4.5)
                    }
                    .padding(ws.sidebarPinned ? 0 : 10)
                    .padding(.top, ws.sidebarPinned ? 0 : 28)
                    .onHover { inside in
                        if !inside && hoverSummonedSidebar && !ws.sidebarPinned {
                            Task { try? await Task.sleep(nanoseconds: 450_000_000); if hoverSummonedSidebar && !ws.sidebarPinned && !leftEdgeHover && !resizing { hoverSummonedSidebar = false; if ws.sidebarVisible { ws.toggleSidebar() } } }
                        } else if inside { hoverSummonedSidebar = hoverSummonedSidebar && true }
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
        .onChange(of: ws.sidebarVisible) { if !ws.sidebarVisible { hoverSummonedSidebar = false; if leftEdgeHover { leftEdgeArmed = false } } }
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
        case .graph:
            GraphView(ws: ws).transition(.opacity)
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
            if e.keyCode == 53 { // Esc
                if let tv = MainWindow.current?.firstResponder as? OnyxTextView, tv.suggestionsVisible { return e }
                if ws.sidebarVisible, ws.clearTreeSelection() { return nil }   // Esc drops a multi-selection first
                if NSApp.keyWindow?.firstResponder is NSTextView, ws.overlay == .none, !ws.sidebarVisible, !ws.inspectorVisible { return e }
                return ws.dismissTop() ? nil : e
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
                guard ws.overlay == .none, e.phase == .began, NSEvent.isSwipeTrackingFromScrollEventsEnabled,
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
            guard ws.isSplit, ws.overlay == .none, let w = e.window, let content = w.contentView else { return e }
            let p = CGPoint(x: e.locationInWindow.x, y: content.bounds.height - e.locationInWindow.y)
            if let i = ws.panes.firstIndex(where: { ws.paneFrames[$0.id]?.contains(p) == true }), i != ws.focusedPane { ws.focusPane(i) }
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
                .font(.system(size: 12.5, weight: on ? .semibold : .regular))
                .foregroundStyle(on || hover ? Color.ink : Color.muted)
                .frame(width: 28, height: 24)
                .background(hover ? Color.ink.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help).onHover { hover = $0 }
    }
}

enum ShortcutHints {
    static let all: [(String, String)] = [
        ("⌘O", "Find or create a note"), ("⌘P", "Every command (also ⇧⌘P)"), ("⌘K", "Show or hide the sidebar"), ("⇧⌘F", "Search the vault"),
        ("⌘↩", "Read ⇄ edit, saving (also ⌘E)"), ("⌘T", "Today’s daily note (also ⌘\\)"), ("⌘I", "Outline, backlinks, properties"),
        ("⌘G", "Focus graph · ⇧⌘G atlas"), ("⌘[  ⌘]", "Back · forward (mouse buttons, swipe)"), ("⌘⌫", "Delete note · or the sidebar selection"), ("⇧⌘M", "Move note to… (links follow)"), ("⌘D", "Split · ⇧⌘D stacked · ⌘W close"), ("⌃⌘F", "Focus: just the text"), ("Esc", "Put things away"),
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
        .help(git.help)
        .accessibilityLabel(git.help)
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
