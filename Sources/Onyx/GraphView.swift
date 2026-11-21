import SwiftUI
import AppKit
import OnyxCore
import simd

/// Cached link index + atlas layouts, rebuilt off the main thread when the vault changes.
@MainActor @Observable
final class GraphStore {
    var index: GraphIndex?
    var atlas: Atlas?
    private var builtGen = -1
    private var atlasKey = ""
    private var building = false

    func ensureIndex(_ snap: VaultSnapshot, gen: Int) async {
        guard builtGen != gen, !building else { return }
        building = true
        let g = await Task.detached(priority: .userInitiated) { GraphIndex.build(snap) }.value
        index = g; builtGen = gen; atlasKey = ""; building = false
    }

    func ensureAtlas(grouping: Atlas.Grouping, filterKey: String, include: @escaping @Sendable (Int) -> Bool) async {
        guard let g = index else { return }
        let key = "\(builtGen)|\(grouping.rawValue)|\(filterKey)"
        guard key != atlasKey else { return }
        atlasKey = key
        let a = await Task.detached(priority: .userInitiated) { Atlas.build(g, grouping: grouping, include: include, includeOrphans: false) }.value
        if atlasKey == key { atlas = a }
    }
}

struct Camera: Equatable { var zoom: Double; var pan: SIMD2<Double> }

/// The focus graph and atlas.
///
/// Presented as an overlay on the current pane (or the solo page), sitting on top of the
/// note underneath — never over the sidebar, inspector, or other split panes. `docked` is
/// the standing "graph in a pane" beside notes (⌥⌘G). Interaction: click a node to travel
/// and re-center (neighborhood browse); double-click or ↩ opens that note in this pane and
/// dismisses the overlay; ⌫ steps back along the trail; Esc closes the overlay and returns
/// focus to the note. Atlas uses the same overlay and the same open/dismiss rules. Orphans
/// stay hidden until Filter → Show orphans (satellites, no list). Hover graph cards are
/// unchanged (title-bar button, links, inspector).
struct GraphView: View {
    @Bindable var ws: Workspace
    /// In a pane beside notes rather than as an overlay: keys stay with the editor, scroll only
    /// zooms under the pointer, and the focus graph follows the note you're on.
    var docked = false
    @State private var frameInWindow: CGRect = .zero
    var store: GraphStore { ws.graphStore }

    // focus state
    @State private var focus: Int? = nil
    @State private var trail: [Int] = []
    @State private var layout: [FocusNode] = []
    @State private var from: [Int: SIMD2<Double>] = [:]
    @State private var exiting: [(Int, SIMD2<Double>)] = []
    @State private var transitionStart = Date.distantPast
    // camera
    @State private var cam = Camera(zoom: 1, pan: .zero)
    @State private var camFrom = Camera(zoom: 1, pan: .zero)
    @State private var camStart = Date.distantPast
    @State private var fitZoom = 1.0
    @State private var gestureBase: Camera? = nil
    @State private var size: CGSize = .zero
    // interaction + filters
    @State private var hover: Int? = nil
    @State private var hoverCluster: Int? = nil
    @State private var query = ""
    @State private var folderFilter = ""
    @State private var tagFilter = ""
    @State private var showOrphans = false
    @State private var recency = 0.0
    @State private var grouping: Atlas.Grouping = .folders
    @State private var monitors: [Any] = []
    @State private var tick = 0
    @FocusState private var searchFocused: Bool

    let duration = 0.55

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color.paper
                let _ = tick
                if animating {
                    TimelineView(.animation) { tl in canvas(now: tl.date) }
                } else {
                    canvas(now: Date())
                }
                VStack(spacing: 0) {
                    header
                    if !ws.graphAtlas && !trail.isEmpty { breadcrumbs }
                    Spacer()
                    if !docked { legend }
                }
            }
            .onAppear { size = geo.size; frameInWindow = geo.frame(in: .global); start() }
            .onChange(of: geo.size) { size = geo.size; refit(animated: false) }
            .onChange(of: geo.frame(in: .global)) { frameInWindow = geo.frame(in: .global) }
            .onChange(of: ws.currentPath) {
                guard docked, !ws.graphAtlas, let p = ws.currentPath, let g = store.index, let i = g.index[p], i != focus else { return }
                setFocus(i)
            }
        }
        .onDisappear { monitors.forEach { NSEvent.removeMonitor($0) }; monitors = [] }
        .onChange(of: ws.graphAtlas) { refit(animated: true); Task { await loadAtlas() } }
        .onChange(of: filterKey) { Task { await loadAtlas() }; if let f = focus { setFocus(f, record: false) } }
        .onChange(of: grouping) { Task { await loadAtlas() } }
    }

    var animating: Bool {
        Date().timeIntervalSince(transitionStart) < duration + 0.05 || Date().timeIntervalSince(camStart) < duration + 0.05
    }

    // MARK: Data

    var filterKey: String { "\(folderFilter)|\(tagFilter)|\(Int(recency * 100))" }

    func includeFn() -> @Sendable (Int) -> Bool {
        guard let g = store.index else { return { _ in true } }
        let folder = folderFilter, tag = tagFilter.lowercased()
        let cutoff: Date? = recency > 0.001 ? cutoffDate(g) : nil
        let folders = g.folders, tags = g.tags, mtimes = g.mtimes
        return { i in
            if !folder.isEmpty && !(folders[i] == folder || folders[i].hasPrefix(folder + "/")) { return false }
            if !tag.isEmpty && !tags[i].contains(where: { $0.lowercased() == tag || $0.lowercased().hasPrefix(tag + "/") }) { return false }
            if let c = cutoff, mtimes[i] < c { return false }
            return true
        }
    }

    func cutoffDate(_ g: GraphIndex) -> Date {
        let minD = g.mtimes.min() ?? Date()
        return minD.addingTimeInterval(Date().timeIntervalSince(minD) * recency)
    }

    func start() {
        installMonitors()
        Task {
            guard let snap = ws.snapshot else { return }
            await store.ensureIndex(snap, gen: ws.snapshotGen)
            guard let g = store.index else { return }
            if let p = ws.currentPath, let i = g.index[p] { setFocus(i, record: false, animated: false) }
            else if let hub = g.ids.indices.max(by: { g.degree[$0] < g.degree[$1] }) { setFocus(hub, record: false, animated: false) }
            await loadAtlas()
            refit(animated: false)
        }
    }

    func loadAtlas() async {
        await store.ensureAtlas(grouping: grouping, filterKey: filterKey, include: includeFn())
        if let a = store.atlas { _ = atlasColors(a) }   // settle region hues before the focus graph borrows them
        if ws.graphAtlas { refit(animated: false) }
    }

    // MARK: Focus navigation

    func setFocus(_ i: Int, record: Bool = true, animated: Bool = true) {
        guard let g = store.index else { return }
        let now = Date()
        let current = currentPositions(now)
        if record, let f = focus, f != i { trail.append(f); if trail.count > 30 { trail.removeFirst() } }
        let inc = includeFn()
        let newLayout = FocusLayout.layout(g, center: i, include: { inc($0) || $0 == i })
        let newIDs = Set(newLayout.map(\.node))
        exiting = animated ? current.filter { !newIDs.contains($0.key) }.map { ($0.key, $0.value) } : []
        from = animated ? current : [:]
        // a note that was already on screen glides to the center; everything else rises out of it
        layout = newLayout
        focus = i
        transitionStart = animated ? now : .distantPast
        settleLater(animated)
        if !ws.graphAtlas { refit(animated: animated) }
    }

    func back() {
        guard let last = trail.popLast() else { return }
        setFocus(last, record: false)
    }

    func open(_ i: Int) {
        guard let g = store.index else { return }
        ws.openNote(g.ids[i])
    }

    // MARK: Geometry

    func ease(_ t: Double) -> Double { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
    func progress(_ now: Date, _ start: Date) -> Double { ease(min(1, max(0, now.timeIntervalSince(start) / duration))) }

    func currentPositions(_ now: Date) -> [Int: SIMD2<Double>] {
        let t = progress(now, transitionStart)
        let centerFrom = focus.flatMap { from[$0] } ?? .zero
        var out: [Int: SIMD2<Double>] = [:]
        for n in layout {
            let a = from[n.node] ?? (centerFrom + (n.pos - centerFrom) * 0.25)
            out[n.node] = a + (n.pos - a) * t
        }
        return out
    }

    func camera(_ now: Date) -> Camera {
        let t = progress(now, camStart)
        if t >= 1 { return cam }
        return Camera(zoom: camFrom.zoom + (cam.zoom - camFrom.zoom) * t, pan: camFrom.pan + (cam.pan - camFrom.pan) * t)
    }

    func setCamera(_ c: Camera, animated: Bool) {
        camFrom = animated ? camera(Date()) : c
        cam = c
        camStart = animated ? Date() : .distantPast
        settleLater(animated)
    }

    /// Re-render once an animation finishes so the static canvas shows the final frame.
    func settleLater(_ animated: Bool) {
        tick += 1
        if animated { DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.08) { tick += 1 } }
    }

    func refit(animated: Bool) {
        guard size.width > 0 else { return }
        let avail = SIMD2(Double(size.width) - 80, Double(size.height) - 220)
        if ws.graphAtlas, let a = store.atlas, !a.clusters.isEmpty {
            var lo = SIMD2(Double.infinity, .infinity), hi = -lo
            for c in a.clusters where c.level == 0 { lo = simd_min(lo, c.center - c.radius); hi = simd_max(hi, c.center + c.radius) }
            let ext = hi - lo
            let z = min(avail.x / ext.x, avail.y / ext.y)
            fitZoom = z
            setCamera(Camera(zoom: z, pan: -(lo + hi) / 2 * z + SIMD2(0, 10)), animated: animated)
        } else {
            let ext = (layout.map { simd_length($0.pos) }.max() ?? 100) + 90
            let z = min(1.5, max(0.3, min(avail.x, avail.y) / 2 / ext))
            fitZoom = z
            setCamera(Camera(zoom: z, pan: SIMD2(0, 18)), animated: animated)
        }
    }

    func screen(_ p: SIMD2<Double>, _ c: Camera) -> CGPoint {
        CGPoint(x: Double(size.width) / 2 + p.x * c.zoom + c.pan.x, y: Double(size.height) / 2 + p.y * c.zoom + c.pan.y)
    }
    func world(_ s: CGPoint, _ c: Camera) -> SIMD2<Double> {
        SIMD2((Double(s.x) - Double(size.width) / 2 - c.pan.x) / c.zoom, (Double(s.y) - Double(size.height) / 2 - c.pan.y) / c.zoom)
    }

    func nodeRadius(_ deg: Int, ring: Int = 1) -> Double { ring == 0 ? 9 : min(11, 2.6 + sqrt(Double(deg)) * 1.05) * (ring == 2 ? 0.8 : 1) }

    var matches: Set<Int> {
        guard let g = store.index, query.count >= 2 else { return [] }
        let q = query.lowercased()
        return Set(g.ids.indices.filter { g.names[$0].lowercased().contains(q) })
    }

    // MARK: Drawing

    func canvas(now: Date) -> some View {
        let c = camera(now)
        let m = matches
        return Canvas { ctx, sz in
            guard let g = store.index else { return }
            if ws.graphAtlas { drawAtlas(&ctx, g, c, m) } else { drawFocus(&ctx, g, c, now, m) }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 3)
            .onChanged { v in
                if gestureBase == nil { gestureBase = camera(Date()) }
                let b = gestureBase!
                setCamera(Camera(zoom: b.zoom, pan: b.pan + SIMD2(Double(v.translation.width), Double(v.translation.height))), animated: false)
            }
            .onEnded { _ in gestureBase = nil })
        .simultaneousGesture(MagnifyGesture()
            .onChanged { v in
                if gestureBase == nil { gestureBase = camera(Date()) }
                zoom(by: v.magnification, around: v.startLocation, base: gestureBase!)
            }
            .onEnded { _ in gestureBase = nil })
        .onContinuousHover { phase in
            switch phase {
            case .active(let loc): (hover, hoverCluster) = hitTest(loc)
            case .ended: hover = nil; hoverCluster = nil
            }
        }
        .onTapGesture(count: 2, coordinateSpace: .local) { loc in
            if let i = hitTest(loc).0 { open(i) }
        }
        .onTapGesture(count: 1, coordinateSpace: .local) { loc in click(loc) }
    }

    func zoom(by f: Double, around loc: CGPoint, base: Camera) {
        let nz = max(0.02, min(12, base.zoom * f))
        let w = world(loc, base)
        // keep the point under the cursor fixed
        let pan = SIMD2(Double(loc.x) - Double(size.width) / 2 - w.x * nz, Double(loc.y) - Double(size.height) / 2 - w.y * nz)
        setCamera(Camera(zoom: nz, pan: pan), animated: false)
    }

    func click(_ loc: CGPoint) {
        let (node, cluster) = hitTest(loc)
        if let i = node {
            if ws.graphAtlas { ws.graphAtlas = false; trail.removeAll() }
            if i == focus { open(i) } else { setFocus(i) }
        } else if ws.graphAtlas, let ci = cluster, let a = store.atlas {
            let cl = a.clusters[ci]
            let avail = min(Double(size.width) - 120, Double(size.height) - 240)
            let z = max(camera(Date()).zoom * 1.4, avail / (cl.radius * 2))
            setCamera(Camera(zoom: z, pan: -cl.center * z + SIMD2(0, 10)), animated: true)
        }
    }

    func hitTest(_ loc: CGPoint) -> (Int?, Int?) {
        guard let g = store.index else { return (nil, nil) }
        let c = camera(Date())
        if ws.graphAtlas {
            guard let a = store.atlas else { return (nil, nil) }
            let rel = c.zoom / fitZoom
            if showOrphans {
                var best: (Int, Double)? = nil
                for (i, p) in orphanPositions(a, g) {
                    let s = screen(p, c); let d = hypot(s.x - loc.x, s.y - loc.y)
                    if d < 6 && d < (best?.1 ?? .infinity) { best = (i, d) }
                }
                if let b = best { return (b.0, nil) }
            }
            if smooth(2.4, 3.4, rel) > 0.3 {
                var best: (Int, Double)? = nil
                for (i, p) in a.notePos {
                    let s = screen(p, c)
                    let d = hypot(s.x - loc.x, s.y - loc.y)
                    let r = max(7, nodeRadius(g.degree[i]) * min(1.6, c.zoom / fitZoom / 3) + 4)
                    if d < r && d < (best?.1 ?? .infinity) { best = (i, d) }
                }
                if let b = best { return (b.0, a.noteCluster[b.0]) }
            }
            let w = world(loc, c)
            let showSubs = smooth(1.3, 2.0, rel) > 0.4
            let hit = a.clusters.indices.filter { (a.clusters[$0].level == 1) == showSubs && simd_length(a.clusters[$0].center - w) < a.clusters[$0].radius }
            return (nil, hit.min { a.clusters[$0].radius < a.clusters[$1].radius })
        }
        let pos = currentPositions(Date())
        var best: (Int, Double)? = nil
        for n in layout {
            guard let p = pos[n.node] else { continue }
            let s = screen(p, c)
            let d = hypot(s.x - loc.x, s.y - loc.y)
            if d < max(10, nodeRadius(g.degree[n.node], ring: n.ring) * c.zoom + 5) && d < (best?.1 ?? .infinity) { best = (n.node, d) }
        }
        return (best?.0, nil)
    }

    func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double { let t = min(1, max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t) }

    /// Greedy, priority-ordered label placement: a label is drawn only where it fits.
    struct LabelPlacer {
        var taken: [CGRect] = []
        /// Draws only where it fits. `halo` paints a paper-colored stroke behind the glyphs
        /// (eight offset copies) and `outline` a thin tinted ring outside that, so labels read over edges.
        @discardableResult
        mutating func place(_ ctx: inout GraphicsContext, _ text: Text, at p: CGPoint, anchor: UnitPoint, force: Bool = false,
                            halo: (text: Text, width: CGFloat)? = nil, outline: Text? = nil, opacity: Double = 1) -> Bool {
            let r = ctx.resolve(text)
            let s = r.measure(in: CGSize(width: 520, height: 120))
            let rect = CGRect(x: p.x - s.width * anchor.x, y: p.y - s.height * anchor.y, width: s.width, height: s.height).insetBy(dx: -4, dy: -2)
            if !force && taken.contains(where: { $0.intersects(rect) }) { return false }
            taken.append(rect)
            var c = ctx
            c.opacity = opacity
            if let o = outline {
                let ro = c.resolve(o)
                let w = (halo?.width ?? 1.5) + 1.1
                for k in 0..<12 { let a = Double(k) / 12 * 2 * .pi; c.draw(ro, at: CGPoint(x: p.x + cos(a) * w, y: p.y + sin(a) * w), anchor: anchor) }
            }
            if let h = halo {
                let rh = c.resolve(h.text)
                for k in 0..<12 { let a = Double(k) / 12 * 2 * .pi; c.draw(rh, at: CGPoint(x: p.x + cos(a) * h.width, y: p.y + sin(a) * h.width), anchor: anchor) }
            }
            c.draw(r, at: p, anchor: anchor)
            return true
        }
    }

    func drawFocus(_ ctx: inout GraphicsContext, _ g: GraphIndex, _ c: Camera, _ now: Date, _ m: Set<Int>) {
        let t = progress(now, transitionStart)
        let pos = currentPositions(now)
        guard let f = focus, let cp = pos[f] else { return }
        let ink = Color.ink, accent = Color.cursorBlue
        let hoverN: Set<Int> = hover.map { g.neighbors($0).union([$0]) } ?? []
        func dimmed(_ i: Int) -> Bool { hover != nil && !hoverN.contains(i) && i != f }
        let center = screen(cp, c)

        // faint ring guides, like a printed diagram
        let r1 = layout.filter { $0.ring == 1 }.map { simd_length($0.pos) }.max() ?? 0
        let r2 = layout.filter { $0.ring == 2 }.map { simd_length($0.pos) }.min() ?? 0
        for (r, o) in [(r1, 0.07), (r2, 0.045)] where r > 0 {
            let rr = r * c.zoom
            ctx.stroke(Path(ellipseIn: CGRect(x: center.x - rr, y: center.y - rr, width: rr * 2, height: rr * 2)), with: .color(ink.opacity(o * t)), style: StrokeStyle(lineWidth: 0.6, dash: [2, 4]))
        }
        // exiting nodes fade toward the old center
        for (i, p0) in exiting {
            let p = p0 + (cp - p0) * t * 0.4
            let s = screen(p, c); let r = nodeRadius(g.degree[i]) * c.zoom * (1 - t)
            if r > 0.3 { ctx.fill(Path(ellipseIn: CGRect(x: s.x - r, y: s.y - r, width: r * 2, height: r * 2)), with: .color(ink.opacity(0.4 * (1 - t)))) }
        }
        // edges: second ring to its parents (hairlines), first ring among itself, center spokes
        let ring1 = layout.filter { $0.ring == 1 }
        let ring1Set = Set(ring1.map(\.node))
        for n in layout where n.ring == 2 {
            guard let p = pos[n.node] else { continue }
            let a = from[n.node] == nil ? t : 1
            for par in n.parents {
                guard let q = pos[par] else { continue }
                let hot = hover == n.node || hover == par
                var path = Path(); path.move(to: screen(p, c)); path.addLine(to: screen(q, c))
                ctx.stroke(path, with: .color(ink.opacity((hot ? 0.55 : (hover == nil ? 0.10 : 0.04)) * a)), lineWidth: hot ? 0.9 : 0.5)
            }
        }
        for n in ring1 {
            for j in g.out[n.node] where ring1Set.contains(j) {
                guard let p = pos[n.node], let q = pos[j] else { continue }
                let hot = hover == n.node || hover == j
                var path = Path(); path.move(to: screen(p, c))
                path.addQuadCurve(to: screen(q, c), control: screen((p + q) * 0.35 + cp * 0.3, c))
                let kind = g.edgeKind(n.node, j)
                ctx.stroke(path, with: .color((kind == .related ? accent : ink).opacity(hot ? 0.5 : (hover == nil ? (kind == .link ? 0.07 : 0.14) : 0.03))),
                           style: StrokeStyle(lineWidth: kind == .partOf ? 0.95 : 0.6, dash: kind == .related ? [1.5, 3] : []))
            }
        }
        for n in ring1 {
            guard let p = pos[n.node] else { continue }
            let a = from[n.node] == nil ? t : 1
            let hot = hover == n.node || hover == f
            var path = Path(); path.move(to: center); path.addLine(to: screen(p, c))
            let w = n.outgoing && n.incoming ? 1.3 : 0.8
            let kind = g.edgeKind(f, n.node)
            let style: StrokeStyle
            switch kind {
            case .partOf: style = StrokeStyle(lineWidth: w + 0.55, lineCap: .round)   // hierarchy reads as a firmer stem
            case .related: style = StrokeStyle(lineWidth: w, dash: [1.5, 3])
            case .link: style = n.outgoing ? StrokeStyle(lineWidth: w) : StrokeStyle(lineWidth: w, dash: [3, 3])
            }
            let tone = kind == .related ? accent : (kind == .partOf ? Color.muted : ink)
            ctx.stroke(path, with: .color(tone.opacity((hot ? 0.75 : (hover == nil ? (kind == .link ? 0.32 : 0.42) : 0.1)) * a)), style: style)
        }
        // nodes
        var placer = LabelPlacer()
        let order = layout.sorted { ($0.ring, -g.degree[$0.node]) < ($1.ring, -g.degree[$1.node]) }
        for n in order.reversed() {
            guard let p = pos[n.node] else { continue }
            let s = screen(p, c)
            let a = (from[n.node] == nil ? t : 1) * (dimmed(n.node) ? 0.25 : 1)
            let r = nodeRadius(g.degree[n.node], ring: n.ring) * max(0.7, min(c.zoom, 1.4))
            let rect = CGRect(x: s.x - r, y: s.y - r, width: r * 2, height: r * 2)
            if n.ring == 0 {
                ctx.fill(Path(ellipseIn: rect.insetBy(dx: -5, dy: -5)), with: .color(accent.opacity(0.14)))
                ctx.fill(Path(ellipseIn: rect), with: .color(accent))
            } else if n.ring == 1 && !n.outgoing {
                // linked *from* this note only: a hollow ring, like a citation
                ctx.fill(Path(ellipseIn: rect), with: .color(Color.paper))
                let tint = ClusterPalette.color(g.folders[n.node].split(separator: "/").first.map(String.init) ?? "vault")
                ctx.stroke(Path(ellipseIn: rect), with: .color(tint.opacity(0.95 * a)), lineWidth: 1.3)
            } else {
                let tint = ClusterPalette.color(g.folders[n.node].split(separator: "/").first.map(String.init) ?? "vault")
                ctx.fill(Path(ellipseIn: rect), with: .color(tint.opacity((n.ring == 2 ? 0.5 : 0.92) * a)))
            }
            if m.contains(n.node) { ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -3.5, dy: -3.5)), with: .color(accent), lineWidth: 1.2) }
        }
        // labels, by priority: center, hover, search hits, ring 1, ring 2
        let prio = layout.sorted { a, b in
            func pr(_ n: FocusNode) -> Int { n.ring == 0 ? 0 : (n.node == hover ? 1 : (m.contains(n.node) ? 2 : (hoverN.contains(n.node) ? 3 : n.ring + 3))) }
            return (pr(a), -g.degree[a.node]) < (pr(b), -g.degree[b.node])
        }
        for n in prio {
            guard let p = pos[n.node] else { continue }
            if from[n.node] == nil && t < 0.6 { continue }
            let s = screen(p, c)
            let r = nodeRadius(g.degree[n.node], ring: n.ring) * max(0.7, min(c.zoom, 1.4))
            let isHot = n.node == hover || n.ring == 0
            let size: CGFloat = n.ring == 0 ? 17 : (n.ring == 1 ? 12.5 : 10.5)
            let color: Color = n.ring == 0 ? Color.ink : (dimmed(n.node) ? Color.faint.opacity(0.6) : (n.ring == 2 ? Color.muted : Color.ink))
            let base = Text(g.names[n.node]).font(n.ring == 0 ? Theme.titleSerif(size) : Theme.serif(size, bold: isHot))
            let text = base.foregroundColor(color)
            let dir = n.ring == 0 ? SIMD2(0.0, 1.0) : simd_normalize(p - cp)
            let anchor: UnitPoint
            var at: CGPoint
            if n.ring == 0 { anchor = .top; at = CGPoint(x: s.x, y: s.y + r + 8) }
            else if dir.x > 0.35 { anchor = .leading; at = CGPoint(x: s.x + r + 5, y: s.y) }
            else if dir.x < -0.35 { anchor = .trailing; at = CGPoint(x: s.x - r - 5, y: s.y) }
            else if dir.y > 0 { anchor = .top; at = CGPoint(x: s.x, y: s.y + r + 3) }
            else { anchor = .bottom; at = CGPoint(x: s.x, y: s.y - r - 3) }
            placer.place(&ctx, text, at: at, anchor: anchor, force: isHot, halo: (base.foregroundColor(Color.paper), 2))
        }
        if layout.count == 1 {
            let tx = Text("No links yet. Write a [[wikilink]] and this note joins the map.").font(Theme.serif(14, italic: true)).foregroundColor(Color.faint)
            ctx.draw(tx, at: CGPoint(x: center.x, y: center.y + 60), anchor: .top)
        }
    }

    func atlasColors(_ a: Atlas) -> [Color] {
        let tops = a.clusters.filter { $0.level == 0 }.sorted { $0.members.count > $1.members.count }.map { $0.key.isEmpty ? "vault" : $0.key }
        ClusterPalette.assign(tops)
        return a.clusters.indices.map { clusterColor(a, $0) }
    }

    func clusterColor(_ a: Atlas, _ ci: Int) -> Color {
        let top = a.clusters[ci].parent ?? ci
        return ClusterPalette.color(a.clusters[top].key.isEmpty ? "vault" : a.clusters[top].key)
    }

    func drawAtlas(_ ctx: inout GraphicsContext, _ g: GraphIndex, _ c: Camera, _ m: Set<Int>) {
        guard let a = store.atlas else { return }
        let ink = Color.ink, accent = Color.cursorBlue, paper = Color.paper
        let rel = c.zoom / fitZoom
        let subA = smooth(1.3, 2.0, rel)
        let noteA = smooth(2.4, 3.4, rel)
        let labelSpacing = Atlas.spacing * c.zoom
        let view = CGRect(origin: .zero, size: size).insetBy(dx: -60, dy: -60)
        let currentIdx = ws.currentPath.flatMap { g.index[$0] }
        var placer = LabelPlacer()
        let maxTop = Double(a.topEdges.first?.2 ?? 1), maxSub = Double(a.subEdges.first?.2 ?? 1)
        let colors = atlasColors(a)

        // cluster-level edges, weight → width and ink
        for (x, y, w) in a.topEdges {
            let p = screen(a.clusters[x].center, c), q = screen(a.clusters[y].center, c)
            var path = Path(); path.move(to: p); path.addLine(to: q)
            let hot = hoverCluster == x || hoverCluster == y
            ctx.stroke(path, with: .color(ink.opacity((0.06 + 0.4 * Double(w) / maxTop) * (1 - subA * 0.8) * (hot ? 1.8 : 1))), lineWidth: 0.6 + 3 * sqrt(Double(w) / maxTop))
        }
        if subA > 0.01 {
            for (x, y, w) in a.subEdges.prefix(260) {
                let p = screen(a.clusters[x].center, c), q = screen(a.clusters[y].center, c)
                guard view.contains(p) || view.contains(q) else { continue }
                var path = Path(); path.move(to: p); path.addLine(to: q)
                ctx.stroke(path, with: .color(ink.opacity((0.03 + 0.3 * Double(w) / maxSub) * subA * (1 - noteA * 0.7))), lineWidth: 0.5 + 2 * sqrt(Double(w) / maxSub))
            }
        }
        // cluster discs, tinted by their region's color
        for (ci, cl) in a.clusters.enumerated() {
            let s = screen(cl.center, c), r = cl.radius * c.zoom
            let rect = CGRect(x: s.x - r, y: s.y - r, width: r * 2, height: r * 2)
            guard rect.intersects(view) else { continue }
            let tint = colors[ci]
            let isHover = hoverCluster == ci
            let hasCurrent = currentIdx.map { cl.members.contains($0) } ?? false
            if cl.level == 0 {
                ctx.fill(Path(ellipseIn: rect), with: .color(tint.opacity(0.07 + (isHover && subA < 0.5 ? 0.05 : 0))))
                ctx.stroke(Path(ellipseIn: rect), with: .color(tint.opacity(0.55)), lineWidth: hasCurrent ? 1.4 : 0.9)
            } else if subA > 0.01 {
                ctx.fill(Path(ellipseIn: rect), with: .color(tint.opacity((0.06 + (isHover ? 0.05 : 0)) * subA * (1 - noteA * 0.4))))
                ctx.stroke(Path(ellipseIn: rect), with: .color(tint.opacity(0.4 * subA)), style: StrokeStyle(lineWidth: 0.7, dash: noteA > 0.5 ? [2, 3] : []))
            }
        }
        // orphans, if asked for: the faintest ink on the page
        let orphans = orphanPositions(a, g)
        for (i, p) in orphans {
            let s = screen(p, c)
            guard view.contains(s) else { continue }
            let r = max(1.4, min(3, 1.2 * sqrt(c.zoom / fitZoom)))
            let hot = hover == i || m.contains(i)
            ctx.fill(Path(ellipseIn: CGRect(x: s.x - r, y: s.y - r, width: 2 * r, height: 2 * r)), with: .color(hot ? accent : ink.opacity(0.2)))
        }
        // notes
        if noteA > 0.01 {
            let hoverN: Set<Int> = hover.map { g.neighbors($0).union([$0]) } ?? []
            if let h = hover, let hp = a.notePos[h] {
                for j in g.neighbors(h) { if let q = a.notePos[j] {
                    var path = Path(); path.move(to: screen(hp, c)); path.addLine(to: screen(q, c))
                    ctx.stroke(path, with: .color(ink.opacity(0.5)), lineWidth: 0.7)
                } }
            }
            for (i, p) in a.notePos {
                let s = screen(p, c)
                guard view.contains(s) else { continue }
                let r = nodeRadius(g.degree[i]) * min(1.5, max(0.5, rel / 3.5))
                let dim = hover != nil && !hoverN.contains(i)
                let rect = CGRect(x: s.x - r, y: s.y - r, width: r * 2, height: r * 2)
                let tint = a.noteCluster[i].map { colors[$0] } ?? ink
                if i == currentIdx {
                    ctx.fill(Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)), with: .color(accent.opacity(0.18 * noteA)))
                    ctx.fill(Path(ellipseIn: rect), with: .color(accent.opacity(noteA)))
                } else {
                    ctx.fill(Path(ellipseIn: rect), with: .color(tint.opacity(noteA * (dim ? 0.2 : 0.9))))
                }
                if m.contains(i) { ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)), with: .color(accent), lineWidth: 1.2) }
            }
        } else if !m.isEmpty || currentIdx != nil {
            for i in m.union(currentIdx.map { [$0] } ?? []) { if let p = a.notePos[i] {
                let s = screen(p, c); let r = i == currentIdx ? 3.6 : 2.6
                if i == currentIdx { ctx.fill(Path(ellipseIn: CGRect(x: s.x - r - 3, y: s.y - r - 3, width: r * 2 + 6, height: r * 2 + 6)), with: .color(accent.opacity(0.22))) }
                ctx.fill(Path(ellipseIn: CGRect(x: s.x - r, y: s.y - r, width: r * 2, height: r * 2)), with: .color(i == currentIdx ? accent : ink.opacity(0.7)))
            } }
        }

        // Labels. Priority: hovered note, current note, search hits, big region titles,
        // sub-region titles, then notes by link count. Each gets a paper halo.
        let haloW: CGFloat = 2.2
        if let h = hover, let p = a.notePos[h] ?? orphans[h] {
            let sp = screen(p, c)
            let t = Text(g.names[h]).font(Theme.serif(13.5, bold: true))
            placer.place(&ctx, t.foregroundColor(ink), at: CGPoint(x: sp.x, y: sp.y - 9), anchor: .bottom, force: true, halo: (t.foregroundColor(paper), haloW))
        }
        if let ci = currentIdx, let p = a.notePos[ci] {
            let sp = screen(p, c)
            let t = Text(g.names[ci]).font(Theme.serif(12.5, bold: true))
            placer.place(&ctx, t.foregroundColor(accent), at: CGPoint(x: sp.x, y: sp.y + 7), anchor: .top, halo: (t.foregroundColor(paper), haloW))
        }
        for i in m.prefix(40) { if let p = a.notePos[i] {
            let sp = screen(p, c)
            let t = Text(g.names[i]).font(Theme.serif(11.5))
            placer.place(&ctx, t.foregroundColor(ink), at: CGPoint(x: sp.x, y: sp.y + 6), anchor: .top, halo: (t.foregroundColor(paper), haloW))
        } }
        // Region titles at their centroids: big, bold, tinted, haloed; they shrink and fade as you zoom in.
        let tops = a.clusters.indices.filter { a.clusters[$0].level == 0 }.sorted { a.clusters[$0].members.count > a.clusters[$1].members.count }
        let topFade = 1 - 0.82 * smooth(1.5, 3.0, rel)
        for ci in tops {
            let cl = a.clusters[ci]
            let s = screen(cl.center, c), r = cl.radius * c.zoom
            guard CGRect(x: s.x - r, y: s.y - r, width: 2 * r, height: 2 * r).intersects(view) else { continue }
            let size = CGFloat(min(34, max(15, r / 4.2)))
            let tint = colors[ci]
            let title = Text(cl.label).font(Theme.titleSerif(size))
            let count = Text("\(cl.members.count) notes").font(Theme.serif(max(10.5, size * 0.42)))
            let at = subA > 0.5 ? CGPoint(x: s.x, y: s.y - r * 0.5) : s
            let placed = placer.place(&ctx, title.foregroundColor(tint), at: at, anchor: .center, force: ci == tops.first,
                                      halo: (title.foregroundColor(paper), 2.6), outline: title.foregroundColor(tint.opacity(0.16)), opacity: topFade)
            if placed && subA < 0.5 {
                placer.place(&ctx, count.foregroundColor(Color.muted), at: CGPoint(x: at.x, y: at.y + size * 0.7), anchor: .top, force: true,
                             halo: (count.foregroundColor(paper), 1.8), opacity: topFade * (1 - subA * 2))
            }
        }
        if subA > 0.3 {
            let subs = a.clusters.indices.filter { a.clusters[$0].level == 1 }.sorted { a.clusters[$0].members.count > a.clusters[$1].members.count }
            for ci in subs {
                let cl = a.clusters[ci]
                let s = screen(cl.center, c), r = cl.radius * c.zoom
                guard view.contains(s), r > 14 else { continue }
                let tint = colors[ci]
                let size = CGFloat(min(20, max(11.5, r / 4.5))) * (noteA > 0.5 ? 0.8 : 1)
                let t = Text(cl.label).font(Theme.serif(size, bold: true))
                let at = noteA > 0.5 ? CGPoint(x: s.x, y: s.y - r - 3) : s
                placer.place(&ctx, t.foregroundColor(tint), at: at, anchor: noteA > 0.5 ? .bottom : .center,
                             halo: (t.foregroundColor(paper), 2.2), outline: t.foregroundColor(tint.opacity(0.22)), opacity: subA * (1 - noteA * 0.25))
            }
        }
        if noteA > 0.5 && labelSpacing > 11 {
            let visible = a.notePos.filter { view.contains(screen($0.value, c)) }.sorted { g.degree[$0.key] > g.degree[$1.key] }.prefix(500)
            for (i, p) in visible {
                let s = screen(p, c)
                let t = Text(g.names[i]).font(Theme.serif(labelSpacing > 22 ? 12 : 10.5))
                placer.place(&ctx, t.foregroundColor(hover != nil && hover != i ? Color.faint : ink.opacity(0.88)), at: CGPoint(x: s.x, y: s.y + 5), anchor: .top, halo: (t.foregroundColor(paper), 1.6))
            }
        }
    }

    // MARK: Chrome

    var header: some View {
        HStack(spacing: 12) {
            if !docked { NavChevrons(ws: ws) }
            Picker("", selection: $ws.graphAtlas) {
                Text("Focus").tag(false)
                Text("Atlas").tag(true)
            }.pickerStyle(.segmented).frame(width: 140).labelsHidden()
            if ws.graphAtlas {
                Picker("", selection: $grouping) {
                    Text("Folders").tag(Atlas.Grouping.folders)
                    Text("Tags").tag(Atlas.Grouping.tags)
                }.pickerStyle(.segmented).frame(width: 130).labelsHidden()
            }
            filterMenu
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").font(.system(size: 10.5)).foregroundStyle(Color.faint)
                TextField("Highlight notes", text: $query).textFieldStyle(.plain).font(.system(size: 12)).focused($searchFocused)
                    .onSubmit { jumpToMatch() }
            }
            .padding(.horizontal, 8).padding(.vertical, 5).frame(width: 130)
            .background(Color.paper, in: RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.hairline))
            Spacer(minLength: 0)
            if docked {
                Button { ws.closeGraphPane() } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.muted).frame(width: 22, height: 22) }
                    .buttonStyle(.plain).help("Close graph pane (⌘W)")
            } else {
                Button { ws.openGraphPane(atlas: ws.graphAtlas) } label: { Image(systemName: "rectangle.righthalf.inset.filled").font(.system(size: 11.5)).foregroundStyle(Color.muted).frame(width: 22, height: 22) }
                    .buttonStyle(.plain).help("Keep open as a pane beside your notes")
                Button { ws.show(.graph) } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.muted).frame(width: 22, height: 22) }
                    .buttonStyle(.plain).help("Close (Esc)")
            }
        }
        .controlSize(.small)
        .padding(.leading, docked ? 12 : 16).padding(.trailing, docked ? 10 : 12).padding(.top, 6).frame(height: 40)
    }

    var filterMenu: some View {
        Menu {
            Section("Folder") {
                Button(folderFilter.isEmpty ? "✓ Whole vault" : "Whole vault") { folderFilter = "" }
                ForEach(topFolders, id: \.self) { f in Button(folderFilter == f ? "✓ \(f)" : f) { folderFilter = f } }
            }
            Section("Tag") {
                Button(tagFilter.isEmpty ? "✓ Any tag" : "Any tag") { tagFilter = "" }
                ForEach(topTags, id: \.self) { t in Button(tagFilter == t ? "✓ #\(t)" : "#\(t)") { tagFilter = t } }
            }
            Divider()
            Toggle("Show orphans", isOn: $showOrphans)
            Section("Recency") {
                Slider(value: $recency, in: 0...0.995).controlSize(.mini)
                Text(recencyLabel).foregroundStyle(Color.faint)
            }
            if !folderFilter.isEmpty || !tagFilter.isEmpty || recency > 0 { Button("Clear filters") { folderFilter = ""; tagFilter = ""; recency = 0 } }
        } label: {
            Label(filterLabel, systemImage: "line.3.horizontal.decrease").font(.system(size: 11.5))
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    var filterLabel: String {
        var parts: [String] = []
        if !folderFilter.isEmpty { parts.append(folderFilter) }
        if !tagFilter.isEmpty { parts.append("#" + tagFilter) }
        return parts.isEmpty ? "Filter" : parts.joined(separator: " · ")
    }
    var topFolders: [String] {
        guard let snap = ws.snapshot else { return [] }
        let tops = Set(snap.folders.compactMap { $0.split(separator: "/").first.map(String.init) })
        var out = tops.sorted()
        if !folderFilter.isEmpty && !out.contains(folderFilter) { out.append(folderFilter) }
        if let cur = ws.currentNote?.folder, !cur.isEmpty, cur.contains("/") { out.append(cur) }
        return out
    }
    var topTags: [String] {
        (ws.snapshot?.tags ?? [:]).sorted { $0.value.count > $1.value.count }.prefix(20).map(\.key)
    }
    var recencyLabel: String {
        guard recency > 0.001, let g = store.index else { return "Any time" }
        return "Since " + cutoffDate(g).formatted(.dateTime.month(.abbreviated).year())
    }
    var breadcrumbs: some View {
        HStack(spacing: 6) {
            Button { back() } label: { Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold)) }
                .buttonStyle(.plain).foregroundStyle(Color.muted).help("Back (⌫)")
            if let g = store.index {
                ForEach(Array(trail.suffix(6).enumerated()), id: \.offset) { k, i in
                    Text(g.names[i]).font(Theme.serif(12.5)).foregroundStyle(Color.muted).lineLimit(1)
                        .onTapGesture { jumpBack(to: trail.count - min(6, trail.count) + k) }
                    Image(systemName: "chevron.right").font(.system(size: 7.5)).foregroundStyle(Color.faint)
                }
                if let f = focus { Text(g.names[f]).font(Theme.serif(12.5, bold: true)).foregroundStyle(Color.ink).lineLimit(1) }
            }
            Spacer()
        }
        .padding(.horizontal, 26).frame(height: 24)
        .transition(.opacity)
    }

    func jumpBack(to k: Int) {
        guard trail.indices.contains(k) else { return }
        let target = trail[k]
        trail = Array(trail.prefix(k))
        setFocus(target, record: false)
    }

    /// Orphans (no links) as faint satellites just outside their region's rim; regionless ones
    /// orbit the whole map. Only drawn when "Show orphans" is on.
    func orphanPositions(_ a: Atlas, _ g: GraphIndex) -> [Int: SIMD2<Double>] {
        guard showOrphans, !a.orphans.isEmpty else { return [:] }
        let tops = a.clusters.filter { $0.level == 0 }
        var byKey: [String: AtlasCluster] = [:]
        for c in tops { byKey[c.key.lowercased()] = c }
        var lo = SIMD2(Double.infinity, .infinity), hi = -lo
        for c in tops { lo = simd_min(lo, c.center - c.radius); hi = simd_max(hi, c.center + c.radius) }
        let mid = tops.isEmpty ? .zero : (lo + hi) / 2
        let outer = tops.isEmpty ? 200 : simd_length(hi - lo) / 2
        var out: [Int: SIMD2<Double>] = [:]
        for i in a.orphans {
            var h: UInt64 = 0xcbf29ce484222325
            for b in g.ids[i].utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
            let ang = Double(h % 10_000) / 10_000 * 2 * .pi, jit = Double((h >> 20) % 1000) / 1000
            let top = g.folders[i].split(separator: "/").first.map { String($0).lowercased() } ?? ""
            if let c = byKey[top] {
                out[i] = c.center + SIMD2(cos(ang), sin(ang)) * (c.radius + Atlas.spacing * (0.7 + jit * 1.4))
            } else {
                out[i] = mid + SIMD2(cos(ang), sin(ang)) * (outer + Atlas.spacing * (1.5 + jit * 2))
            }
        }
        return out
    }

    @ViewBuilder var legendKeys: some View {
        HStack(spacing: 5) { Circle().fill(Color.ink).frame(width: 7, height: 7); Text("links to") }
        HStack(spacing: 5) { Circle().strokeBorder(Color.ink, lineWidth: 1).frame(width: 8, height: 8); Text("links here") }
        HStack(spacing: 5) { Circle().fill(Color.muted.opacity(0.6)).frame(width: 6, height: 6); Text("two steps away") }
        HStack(spacing: 5) { Capsule().fill(Color.muted).frame(width: 16, height: 2); Text("part of") }
        HStack(spacing: 5) { Text("┄").foregroundStyle(Color.cursorBlue); Text("related") }
    }

    var legend: some View {
        HStack(spacing: 12) {
            if ws.graphAtlas {
                ViewThatFits(in: .horizontal) {
                    Text("Pinch or scroll to zoom into a region · click a region to enter it · click a note to focus it").foregroundStyle(Color.faint).lineLimit(1)
                    Text("Scroll to zoom · click to enter · ↩ opens · Esc closes").foregroundStyle(Color.faint).lineLimit(1)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        legendKeys
                        Text("click to travel · double-click or ↩ opens · Esc closes").foregroundStyle(Color.faint).lineLimit(1)
                    }
                    HStack(spacing: 10) {
                        legendKeys
                        Text("click travels · ↩ opens · Esc closes").foregroundStyle(Color.faint).lineLimit(1)
                    }
                    HStack(spacing: 8) { legendKeys }
                }
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 10.5)).foregroundStyle(Color.muted)
        .padding(.horizontal, 16).padding(.bottom, 12).frame(height: 30)
    }

    func jumpToMatch() {
        guard let g = store.index else { return }
        let q = query.lowercased()
        guard let best = matches.min(by: { ((g.names[$0].lowercased() != q) ? 1 : 0, g.names[$0].count) < ((g.names[$1].lowercased() != q) ? 1 : 0, g.names[$1].count) }) else { return }
        if ws.graphAtlas { ws.graphAtlas = false }
        setFocus(best)
        searchFocused = false
    }

    func installMonitors() {
        guard monitors.isEmpty else { return }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { e in
            var loc = e.window.map { w -> CGPoint in let p = e.locationInWindow; return CGPoint(x: p.x, y: (w.contentView?.bounds.height ?? 0) - p.y) } ?? .zero
            guard frameInWindow.contains(loc) else { return e }
            if docked {
                guard ws.overlay == .none else { return e }
            } else {
                guard ws.overlay == .graph else { return e }
            }
            loc = CGPoint(x: loc.x - frameInWindow.minX, y: loc.y - frameInWindow.minY)
            let base = camera(Date())
            if e.modifierFlags.contains(.command) || !e.hasPreciseScrollingDeltas {
                zoom(by: exp(Double(e.scrollingDeltaY) * (e.hasPreciseScrollingDeltas ? 0.01 : 0.1)), around: loc, base: base)
            } else {
                setCamera(Camera(zoom: base.zoom, pan: base.pan + SIMD2(Double(e.scrollingDeltaX), Double(e.scrollingDeltaY))), animated: false)
            }
            return nil
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { e in
            guard !docked, ws.overlay == .graph, !(NSApp.keyWindow?.firstResponder is NSTextView) else { return e }
            // Exact modifiers only, so ⌘↩ (read/edit), ⇧⌘F (vault search) and ⌃⌘F (focus mode)
            // still reach the menu while the graph is open.
            let mods = e.modifierFlags.intersection([.command, .shift, .option, .control])
            switch e.keyCode {
            case 36 where mods.isEmpty, 76 where mods.isEmpty: if let f = hover ?? focus { open(f) }; return nil   // return / enter
            case 51 where mods.isEmpty: back(); return nil                                                        // delete
            case 3 where mods == [.command]: searchFocused = true; return nil                                     // ⌘F
            default: return e
            }
        }) { monitors.append(m) }
    }
}
