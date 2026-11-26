import SwiftUI
import OnyxCore
import simd

struct GraphCamera: Equatable {
    var zoom: Double
    var pan: SIMD2<Double>
}

/// Focus graph and whole-vault atlas, drawn with the same `GraphIndex` / `FocusLayout` /
/// `Atlas` models as the Mac overlay. Pinch to zoom, drag to pan, tap a note to open it.
struct GraphScreen: View {
    @EnvironmentObject private var vault: MobileVault
    @ObservedObject var store: MobileGraphStore

    @State private var focus: Int? = nil
    @State private var trail: [Int] = []
    @State private var layout: [FocusNode] = []
    @State private var from: [Int: SIMD2<Double>] = [:]
    @State private var exiting: [(Int, SIMD2<Double>)] = []
    @State private var transitionStart = Date.distantPast

    @State private var cam = GraphCamera(zoom: 1, pan: .zero)
    @State private var camFrom = GraphCamera(zoom: 1, pan: .zero)
    @State private var camStart = Date.distantPast
    @State private var fitZoom = 1.0
    @State private var gestureBase: GraphCamera? = nil
    @State private var size: CGSize = .zero

    @State private var query = ""
    @State private var folderFilter = ""
    @State private var tagFilter = ""
    @State private var showOrphans = false
    @AppStorage("onyx.ios.graph.hierarchyOnly") private var hierarchyOnly = false
    @State private var recency = 0.0
    @State private var grouping: Atlas.Grouping = .folders
    @State private var tick = 0
    @State private var camDuration = 0.55
    @State private var loading = true
    @FocusState private var searchFocused: Bool

    let duration = 0.55
    let atlasAnimDuration = 0.3

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color.paper
                let _ = tick
                if loading && store.index == nil {
                    ProgressView("Building graph…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if animating {
                    TimelineView(.animation) { tl in canvas(now: tl.date) }
                } else {
                    canvas(now: Date())
                }
                VStack(spacing: 0) {
                    header
                    if !vault.graphAtlas && !trail.isEmpty { breadcrumbs }
                    Spacer()
                    legend
                }
            }
            .onAppear {
                size = geo.size
                start()
            }
            .onChange(of: geo.size) { _, new in
                size = new
                refit(animated: false)
            }
        }
        .background(Color.paper)
        .onChange(of: vault.snapshotGeneration) { _, _ in start() }
        .onChange(of: vault.graphAtlas) { _, _ in
            refit(animated: true)
            Task { await loadAtlas() }
        }
        .onChange(of: hierarchyOnly) { _, _ in if let f = focus { setFocus(f, record: false) } }
        .onChange(of: filterKey) { _, _ in
            Task { await loadAtlas() }
            if let f = focus { setFocus(f, record: false) }
        }
        .onChange(of: grouping) { _, _ in Task { await loadAtlas() } }
        .onChange(of: vault.selectedPath) { _, path in
            guard !vault.graphAtlas, let p = path, let g = store.index, let i = g.index[p], i != focus else { return }
            setFocus(i)
        }
    }

    var animating: Bool {
        Date().timeIntervalSince(transitionStart) < duration + 0.05
            || Date().timeIntervalSince(camStart) < camDuration + 0.05
    }

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
        Task {
            guard let snap = vault.snapshot else {
                await MainActor.run { loading = false }
                return
            }
            await store.ensureIndex(snap, gen: vault.snapshotGeneration)
            await MainActor.run {
                guard let g = store.index else { loading = false; return }
                if let p = vault.selectedPath, let i = g.index[p] {
                    setFocus(i, record: false, animated: false)
                } else if let hub = g.ids.indices.max(by: { g.degree[$0] < g.degree[$1] }) {
                    setFocus(hub, record: false, animated: false)
                }
            }
            await loadAtlas()
            await MainActor.run {
                refit(animated: false)
                loading = false
            }
        }
    }

    func loadAtlas() async {
        await store.ensureAtlas(grouping: grouping, filterKey: filterKey, include: includeFn())
        if let a = store.atlas { _ = atlasColors(a) }
        if vault.graphAtlas {
            await MainActor.run { refit(animated: false) }
        }
    }

    func setFocus(_ i: Int, record: Bool = true, animated: Bool = true) {
        guard let g = store.index else { return }
        let now = Date()
        let current = currentPositions(now)
        if record, let f = focus, f != i { trail.append(f); if trail.count > 30 { trail.removeFirst() } }
        let inc = includeFn()
        let newLayout = FocusLayout.layout(g, center: i, include: { inc($0) || $0 == i }, hierarchy: hierarchyOnly)
        let newIDs = Set(newLayout.map(\.node))
        exiting = animated ? current.filter { !newIDs.contains($0.key) }.map { ($0.key, $0.value) } : []
        from = animated ? current : [:]
        layout = newLayout
        focus = i
        transitionStart = animated ? now : .distantPast
        settleLater(animated)
        if !vault.graphAtlas { refit(animated: animated) }
    }

    func back() {
        guard let last = trail.popLast() else { return }
        setFocus(last, record: false)
    }

    func open(_ i: Int) {
        guard let g = store.index, g.ids.indices.contains(i) else { return }
        vault.openNote(g.ids[i])
    }

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

    func camera(_ now: Date) -> GraphCamera {
        let t = ease(min(1, max(0, now.timeIntervalSince(camStart) / max(camDuration, 0.001))))
        if t >= 1 { return cam }
        return GraphCamera(zoom: camFrom.zoom + (cam.zoom - camFrom.zoom) * t,
                           pan: camFrom.pan + (cam.pan - camFrom.pan) * t)
    }

    func setCamera(_ c: GraphCamera, animated: Bool, duration d: Double? = nil) {
        var c = c
        c.zoom = GraphZoom.clamp(c.zoom, fit: fitZoom)
        camFrom = animated ? camera(Date()) : c
        cam = c
        camDuration = animated ? (d ?? duration) : duration
        camStart = animated ? Date() : .distantPast
        settleLater(animated, last: camDuration)
    }

    func settleLater(_ animated: Bool, last: Double? = nil) {
        tick += 1
        if animated { DispatchQueue.main.asyncAfter(deadline: .now() + (last ?? duration) + 0.08) { tick += 1 } }
    }

    func atlasChromePadding() -> SIMD2<Double> {
        SIMD2(max(80, Double(size.width) - 48), max(80, Double(size.height) - 180))
    }

    func fitAllCamera() -> GraphCamera? {
        guard size.width > 0 else { return nil }
        let avail = atlasChromePadding()
        if vault.graphAtlas, let a = store.atlas, !a.clusters.isEmpty {
            var lo = SIMD2(Double.infinity, .infinity), hi = -lo
            for c in a.clusters where c.level == 0 {
                lo = simd_min(lo, c.center - c.radius)
                hi = simd_max(hi, c.center + c.radius)
            }
            let ext = hi - lo
            let z = min(avail.x / max(ext.x, 1), avail.y / max(ext.y, 1))
            return GraphCamera(zoom: z, pan: -(lo + hi) / 2 * z + SIMD2(0, 10))
        } else {
            let ext = (layout.map { simd_length($0.pos) }.max() ?? 100) + 90
            let z = min(1.5, max(0.3, min(avail.x, avail.y) / 2 / ext))
            return GraphCamera(zoom: z, pan: SIMD2(0, 18))
        }
    }

    func fitClusterCamera(_ cl: AtlasCluster) -> GraphCamera? {
        guard size.width > 0 else { return nil }
        let avail = atlasChromePadding() - SIMD2(48, 48)
        let span = max(cl.radius * 2, 1)
        let z = min(avail.x / span, avail.y / span)
        return GraphCamera(zoom: z, pan: -cl.center * z + SIMD2(0, 10))
    }

    func refit(animated: Bool, duration d: Double? = nil) {
        guard let dest = fitAllCamera() else { return }
        fitZoom = GraphZoom.clamp(dest.zoom, fit: dest.zoom)
        setCamera(dest, animated: animated, duration: d)
    }

    func maximizeCluster(_ cl: AtlasCluster) {
        guard let dest = fitClusterCamera(cl) else { return }
        setCamera(dest, animated: true, duration: atlasAnimDuration)
    }

    func screen(_ p: SIMD2<Double>, _ c: GraphCamera) -> CGPoint {
        CGPoint(x: Double(size.width) / 2 + p.x * c.zoom + c.pan.x,
                y: Double(size.height) / 2 + p.y * c.zoom + c.pan.y)
    }
    func world(_ s: CGPoint, _ c: GraphCamera) -> SIMD2<Double> {
        SIMD2((Double(s.x) - Double(size.width) / 2 - c.pan.x) / c.zoom,
              (Double(s.y) - Double(size.height) / 2 - c.pan.y) / c.zoom)
    }

    func nodeRadius(_ deg: Int, ring: Int = 1) -> Double {
        ring == 0 ? 9 : min(11, 2.6 + sqrt(Double(deg)) * 1.05) * (ring == 2 ? 0.8 : 1)
    }

    var matches: Set<Int> {
        guard let g = store.index, query.count >= 2 else { return [] }
        let q = query.lowercased()
        return Set(g.ids.indices.filter { g.names[$0].lowercased().contains(q) })
    }

    func canvas(now: Date) -> some View {
        let c = camera(now)
        let m = matches
        return Canvas { ctx, _ in
            guard let g = store.index else { return }
            if vault.graphAtlas { drawAtlas(&ctx, g, c, m) } else { drawFocus(&ctx, g, c, now, m) }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 8)
            .onChanged { v in
                if gestureBase == nil { gestureBase = camera(Date()) }
                let b = gestureBase!
                setCamera(GraphCamera(zoom: b.zoom, pan: b.pan + SIMD2(Double(v.translation.width), Double(v.translation.height))), animated: false)
            }
            .onEnded { _ in gestureBase = nil })
        .simultaneousGesture(MagnifyGesture()
            .onChanged { v in
                if gestureBase == nil { gestureBase = camera(Date()) }
                zoom(by: v.magnification, around: v.startLocation, base: gestureBase!)
            }
            .onEnded { _ in gestureBase = nil })
        .onTapGesture(count: 2, coordinateSpace: .local) { loc in
            handleDoubleTap(loc)
        }
        .onTapGesture(count: 1, coordinateSpace: .local) { loc in
            handleTap(loc)
        }
    }

    func zoom(by f: Double, around loc: CGPoint, base: GraphCamera) {
        let nz = GraphZoom.clamp(base.zoom * f, fit: fitZoom)
        let w = world(loc, base)
        let pan = SIMD2(Double(loc.x) - Double(size.width) / 2 - w.x * nz,
                        Double(loc.y) - Double(size.height) / 2 - w.y * nz)
        setCamera(GraphCamera(zoom: nz, pan: pan), animated: false)
    }

    func handleTap(_ loc: CGPoint) {
        let (node, cluster) = hitTest(loc)
        if let i = node {
            open(i)
            return
        }
        if vault.graphAtlas, let ci = cluster, let a = store.atlas, a.clusters.indices.contains(ci) {
            maximizeCluster(a.clusters[ci])
        }
    }

    func handleDoubleTap(_ loc: CGPoint) {
        let (node, cluster) = hitTest(loc)
        if let i = node {
            open(i)
            return
        }
        guard vault.graphAtlas else { return }
        if let ci = cluster, let a = store.atlas, a.clusters.indices.contains(ci) {
            maximizeCluster(a.clusters[ci])
        } else {
            refit(animated: true, duration: atlasAnimDuration)
        }
    }

    /// Touch targets are at least 22 pt so a finger can hit a small node.
    func hitTest(_ loc: CGPoint) -> (Int?, Int?) {
        guard let g = store.index else { return (nil, nil) }
        let c = camera(Date())
        if vault.graphAtlas {
            guard let a = store.atlas else { return (nil, nil) }
            let rel = c.zoom / max(fitZoom, 0.0001)
            if showOrphans {
                var best: (Int, Double)? = nil
                for (i, p) in orphanPositions(a, g) {
                    let s = screen(p, c)
                    let d = hypot(s.x - loc.x, s.y - loc.y)
                    if d < 22 && d < (best?.1 ?? .infinity) { best = (i, d) }
                }
                if let b = best { return (b.0, nil) }
            }
            if smooth(2.4, 3.4, rel) > 0.3 {
                var best: (Int, Double)? = nil
                for (i, p) in a.notePos {
                    let s = screen(p, c)
                    let d = hypot(s.x - loc.x, s.y - loc.y)
                    let r = max(22, nodeRadius(g.degree[i]) * min(1.6, c.zoom / fitZoom / 3) + 8)
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
            let r = max(22, nodeRadius(g.degree[n.node], ring: n.ring) * c.zoom + 10)
            if d < r && d < (best?.1 ?? .infinity) { best = (n.node, d) }
        }
        return (best?.0, nil)
    }

    func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    struct LabelPlacer {
        var taken: [CGRect] = []
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
                for k in 0..<12 {
                    let a = Double(k) / 12 * 2 * .pi
                    c.draw(ro, at: CGPoint(x: p.x + cos(a) * w, y: p.y + sin(a) * w), anchor: anchor)
                }
            }
            if let h = halo {
                let rh = c.resolve(h.text)
                for k in 0..<12 {
                    let a = Double(k) / 12 * 2 * .pi
                    c.draw(rh, at: CGPoint(x: p.x + cos(a) * h.width, y: p.y + sin(a) * h.width), anchor: anchor)
                }
            }
            c.draw(r, at: p, anchor: anchor)
            return true
        }
    }

    func drawFocus(_ ctx: inout GraphicsContext, _ g: GraphIndex, _ c: GraphCamera, _ now: Date, _ m: Set<Int>) {
        let t = progress(now, transitionStart)
        let pos = currentPositions(now)
        guard let f = focus, let cp = pos[f] else { return }
        let ink = Color.ink, accent = Color.cursorBlue
        let center = screen(cp, c)

        let r1 = layout.filter { $0.ring == 1 }.map { simd_length($0.pos) }.max() ?? 0
        let r2 = layout.filter { $0.ring == 2 }.map { simd_length($0.pos) }.min() ?? 0
        for (r, o) in [(r1, 0.07), (r2, 0.045)] where r > 0 {
            let rr = r * c.zoom
            ctx.stroke(Path(ellipseIn: CGRect(x: center.x - rr, y: center.y - rr, width: rr * 2, height: rr * 2)),
                       with: .color(ink.opacity(o * t)), style: StrokeStyle(lineWidth: 0.6, dash: [2, 4]))
        }
        for (i, p0) in exiting {
            let p = p0 + (cp - p0) * t * 0.4
            let s = screen(p, c)
            let r = nodeRadius(g.degree[i]) * c.zoom * (1 - t)
            if r > 0.3 {
                ctx.fill(Path(ellipseIn: CGRect(x: s.x - r, y: s.y - r, width: r * 2, height: r * 2)),
                         with: .color(ink.opacity(0.4 * (1 - t))))
            }
        }
        let ring1 = layout.filter { $0.ring == 1 }
        let ring1Set = Set(ring1.map(\.node))
        for n in layout where n.ring == 2 {
            guard let p = pos[n.node] else { continue }
            let a = from[n.node] == nil ? t : 1
            for par in n.parents {
                guard let q = pos[par] else { continue }
                var path = Path(); path.move(to: screen(p, c)); path.addLine(to: screen(q, c))
                ctx.stroke(path, with: .color(ink.opacity(0.10 * a)), lineWidth: 0.5)
            }
        }
        for n in ring1 {
            for j in g.out[n.node] where ring1Set.contains(j) {
                guard let p = pos[n.node], let q = pos[j] else { continue }
                var path = Path(); path.move(to: screen(p, c))
                path.addQuadCurve(to: screen(q, c), control: screen((p + q) * 0.35 + cp * 0.3, c))
                let kind = g.edgeKind(n.node, j)
                ctx.stroke(path, with: .color((kind == .related ? accent : ink).opacity(kind == .link ? 0.07 : 0.14)),
                           style: StrokeStyle(lineWidth: kind == .partOf ? 0.95 : 0.6, dash: kind == .related ? [1.5, 3] : []))
            }
        }
        for n in ring1 {
            guard let p = pos[n.node] else { continue }
            let a = from[n.node] == nil ? t : 1
            var path = Path(); path.move(to: center); path.addLine(to: screen(p, c))
            let w = n.outgoing && n.incoming ? 1.3 : 0.8
            let kind = g.edgeKind(f, n.node)
            let style: StrokeStyle
            switch kind {
            case .partOf: style = StrokeStyle(lineWidth: w + 0.55, lineCap: .round)
            case .related: style = StrokeStyle(lineWidth: w, dash: [1.5, 3])
            case .link: style = n.outgoing ? StrokeStyle(lineWidth: w) : StrokeStyle(lineWidth: w, dash: [3, 3])
            }
            let tone = kind == .related ? accent : (kind == .partOf ? Color.muted : ink)
            ctx.stroke(path, with: .color(tone.opacity((kind == .link ? 0.32 : 0.42) * a)), style: style)
            if kind == .partOf {
                let toParent = g.partOf[f].contains(n.node)
                let (c0, p0) = toParent ? (center, screen(p, c)) : (screen(p, c), center)
                let dx = p0.x - c0.x, dy = p0.y - c0.y, len = max(1, (dx * dx + dy * dy).squareRoot())
                let ux = dx / len, uy = dy / len, mid = CGPoint(x: c0.x + dx * 0.55, y: c0.y + dy * 0.55), k = 3.4
                var head = Path()
                head.move(to: CGPoint(x: mid.x - ux * k - uy * k, y: mid.y - uy * k + ux * k))
                head.addLine(to: mid)
                head.addLine(to: CGPoint(x: mid.x - ux * k + uy * k, y: mid.y - uy * k - ux * k))
                ctx.stroke(head, with: .color(tone.opacity(0.5 * a)), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
            }
        }
        var placer = LabelPlacer()
        let order = layout.sorted { ($0.ring, -g.degree[$0.node]) < ($1.ring, -g.degree[$1.node]) }
        for n in order.reversed() {
            guard let p = pos[n.node] else { continue }
            let s = screen(p, c)
            let a = from[n.node] == nil ? t : 1
            let r = nodeRadius(g.degree[n.node], ring: n.ring) * max(0.7, min(c.zoom, 1.4))
            let rect = CGRect(x: s.x - r, y: s.y - r, width: r * 2, height: r * 2)
            if n.ring == 0 {
                ctx.fill(Path(ellipseIn: rect.insetBy(dx: -5, dy: -5)), with: .color(accent.opacity(0.14)))
                ctx.fill(Path(ellipseIn: rect), with: .color(accent))
            } else if n.ring == 1 && !n.outgoing {
                ctx.fill(Path(ellipseIn: rect), with: .color(Color.paper))
                let tint = ClusterPalette.color(g.folders[n.node].split(separator: "/").first.map(String.init) ?? "vault")
                ctx.stroke(Path(ellipseIn: rect), with: .color(tint.opacity(0.95 * a)), lineWidth: 1.3)
            } else {
                let tint = ClusterPalette.color(g.folders[n.node].split(separator: "/").first.map(String.init) ?? "vault")
                ctx.fill(Path(ellipseIn: rect), with: .color(tint.opacity((n.ring == 2 ? 0.5 : 0.92) * a)))
            }
            if m.contains(n.node) { ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -3.5, dy: -3.5)), with: .color(accent), lineWidth: 1.2) }
        }
        let prio = layout.sorted { a, b in
            func pr(_ n: FocusNode) -> Int { n.ring == 0 ? 0 : (m.contains(n.node) ? 2 : n.ring + 3) }
            return (pr(a), -g.degree[a.node]) < (pr(b), -g.degree[b.node])
        }
        for n in prio {
            guard let p = pos[n.node] else { continue }
            if from[n.node] == nil && t < 0.6 { continue }
            let s = screen(p, c)
            let r = nodeRadius(g.degree[n.node], ring: n.ring) * max(0.7, min(c.zoom, 1.4))
            let isHot = n.ring == 0
            let size: CGFloat = n.ring == 0 ? 17 : (n.ring == 1 ? 12.5 : 10.5)
            let color: Color = n.ring == 0 ? Color.ink : (n.ring == 2 ? Color.muted : Color.ink)
            let base = Text(g.names[n.node]).font(n.ring == 0 ? MobileTheme.titleSerif(size) : MobileTheme.serif(size, bold: isHot))
            let text = base.foregroundColor(color)
            let dir = n.ring == 0 ? SIMD2(0.0, 1.0) : simd_normalize(p - cp)
            let anchor: UnitPoint
            let at: CGPoint
            if n.ring == 0 { anchor = .top; at = CGPoint(x: s.x, y: s.y + r + 8) }
            else if dir.x > 0.35 { anchor = .leading; at = CGPoint(x: s.x + r + 5, y: s.y) }
            else if dir.x < -0.35 { anchor = .trailing; at = CGPoint(x: s.x - r - 5, y: s.y) }
            else if dir.y > 0 { anchor = .top; at = CGPoint(x: s.x, y: s.y + r + 3) }
            else { anchor = .bottom; at = CGPoint(x: s.x, y: s.y - r - 3) }
            placer.place(&ctx, text, at: at, anchor: anchor, force: isHot, halo: (base.foregroundColor(Color.paper), 2))
        }
        if layout.count == 1 {
            let tx = Text("No links yet. Write a [[wikilink]] and this note joins the map.")
                .font(MobileTheme.serif(14, italic: true)).foregroundColor(Color.faint)
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

    func drawAtlas(_ ctx: inout GraphicsContext, _ g: GraphIndex, _ c: GraphCamera, _ m: Set<Int>) {
        guard let a = store.atlas else { return }
        let ink = Color.ink, accent = Color.cursorBlue, paper = Color.paper
        let rel = c.zoom / max(fitZoom, 0.0001)
        let subA = smooth(1.3, 2.0, rel)
        let noteA = smooth(2.4, 3.4, rel)
        let labelSpacing = Atlas.spacing * c.zoom
        let view = CGRect(origin: .zero, size: size).insetBy(dx: -60, dy: -60)
        let currentIdx = vault.selectedPath.flatMap { g.index[$0] }
        var placer = LabelPlacer()
        let maxTop = Double(a.topEdges.first?.2 ?? 1), maxSub = Double(a.subEdges.first?.2 ?? 1)
        let colors = atlasColors(a)

        for (x, y, w) in a.topEdges {
            let p = screen(a.clusters[x].center, c), q = screen(a.clusters[y].center, c)
            var path = Path(); path.move(to: p); path.addLine(to: q)
            ctx.stroke(path, with: .color(ink.opacity((0.06 + 0.4 * Double(w) / maxTop) * (1 - subA * 0.8))),
                       lineWidth: 0.6 + 3 * sqrt(Double(w) / maxTop))
        }
        if subA > 0.01 {
            for (x, y, w) in a.subEdges.prefix(260) {
                let p = screen(a.clusters[x].center, c), q = screen(a.clusters[y].center, c)
                guard view.contains(p) || view.contains(q) else { continue }
                var path = Path(); path.move(to: p); path.addLine(to: q)
                ctx.stroke(path, with: .color(ink.opacity((0.03 + 0.3 * Double(w) / maxSub) * subA * (1 - noteA * 0.7))),
                           lineWidth: 0.5 + 2 * sqrt(Double(w) / maxSub))
            }
        }
        for (ci, cl) in a.clusters.enumerated() {
            let s = screen(cl.center, c), r = cl.radius * c.zoom
            let rect = CGRect(x: s.x - r, y: s.y - r, width: r * 2, height: r * 2)
            guard rect.intersects(view) else { continue }
            let tint = colors[ci]
            let hasCurrent = currentIdx.map { cl.members.contains($0) } ?? false
            if cl.level == 0 {
                ctx.fill(Path(ellipseIn: rect), with: .color(tint.opacity(0.07)))
                ctx.stroke(Path(ellipseIn: rect), with: .color(tint.opacity(0.55)), lineWidth: hasCurrent ? 1.4 : 0.9)
            } else if subA > 0.01 {
                ctx.fill(Path(ellipseIn: rect), with: .color(tint.opacity(0.06 * subA * (1 - noteA * 0.4))))
                ctx.stroke(Path(ellipseIn: rect), with: .color(tint.opacity(0.4 * subA)),
                           style: StrokeStyle(lineWidth: 0.7, dash: noteA > 0.5 ? [2, 3] : []))
            }
        }
        let orphans = orphanPositions(a, g)
        for (i, p) in orphans {
            let s = screen(p, c)
            guard view.contains(s) else { continue }
            let r = max(1.4, min(3, 1.2 * sqrt(c.zoom / max(fitZoom, 0.0001))))
            let hot = m.contains(i)
            ctx.fill(Path(ellipseIn: CGRect(x: s.x - r, y: s.y - r, width: 2 * r, height: 2 * r)),
                     with: .color(hot ? accent : ink.opacity(0.2)))
        }
        if noteA > 0.01 {
            for (i, p) in a.notePos {
                let s = screen(p, c)
                guard view.contains(s) else { continue }
                let r = nodeRadius(g.degree[i]) * min(1.5, max(0.5, rel / 3.5))
                let rect = CGRect(x: s.x - r, y: s.y - r, width: r * 2, height: r * 2)
                let tint = a.noteCluster[i].map { colors[$0] } ?? ink
                if i == currentIdx {
                    ctx.fill(Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)), with: .color(accent.opacity(0.18 * noteA)))
                    ctx.fill(Path(ellipseIn: rect), with: .color(accent.opacity(noteA)))
                } else {
                    ctx.fill(Path(ellipseIn: rect), with: .color(tint.opacity(noteA * 0.9)))
                }
                if m.contains(i) { ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)), with: .color(accent), lineWidth: 1.2) }
            }
        } else if !m.isEmpty || currentIdx != nil {
            for i in m.union(currentIdx.map { [$0] } ?? []) {
                if let p = a.notePos[i] {
                    let s = screen(p, c)
                    let r = i == currentIdx ? 3.6 : 2.6
                    if i == currentIdx {
                        ctx.fill(Path(ellipseIn: CGRect(x: s.x - r - 3, y: s.y - r - 3, width: r * 2 + 6, height: r * 2 + 6)),
                                 with: .color(accent.opacity(0.22)))
                    }
                    ctx.fill(Path(ellipseIn: CGRect(x: s.x - r, y: s.y - r, width: r * 2, height: r * 2)),
                             with: .color(i == currentIdx ? accent : ink.opacity(0.7)))
                }
            }
        }

        let haloW: CGFloat = 2.2
        if let ci = currentIdx, let p = a.notePos[ci] {
            let sp = screen(p, c)
            let tx = Text(g.names[ci]).font(MobileTheme.serif(12.5, bold: true))
            placer.place(&ctx, tx.foregroundColor(accent), at: CGPoint(x: sp.x, y: sp.y + 7), anchor: .top,
                         halo: (tx.foregroundColor(paper), haloW))
        }
        for i in m.prefix(40) {
            if let p = a.notePos[i] {
                let sp = screen(p, c)
                let tx = Text(g.names[i]).font(MobileTheme.serif(11.5))
                placer.place(&ctx, tx.foregroundColor(ink), at: CGPoint(x: sp.x, y: sp.y + 6), anchor: .top,
                             halo: (tx.foregroundColor(paper), haloW))
            }
        }
        let tops = a.clusters.indices.filter { a.clusters[$0].level == 0 }.sorted { a.clusters[$0].members.count > a.clusters[$1].members.count }
        let topFade = 1 - 0.82 * smooth(1.5, 3.0, rel)
        for ci in tops {
            let cl = a.clusters[ci]
            let s = screen(cl.center, c), r = cl.radius * c.zoom
            guard CGRect(x: s.x - r, y: s.y - r, width: 2 * r, height: 2 * r).intersects(view) else { continue }
            let size = CGFloat(min(34, max(15, r / 4.2)))
            let tint = colors[ci]
            let title = Text(cl.label).font(MobileTheme.titleSerif(size))
            let count = Text("\(cl.members.count) notes").font(MobileTheme.serif(max(10.5, size * 0.42)))
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
                let tx = Text(cl.label).font(MobileTheme.serif(size, bold: true))
                let at = noteA > 0.5 ? CGPoint(x: s.x, y: s.y - r - 3) : s
                placer.place(&ctx, tx.foregroundColor(tint), at: at, anchor: noteA > 0.5 ? .bottom : .center,
                             halo: (tx.foregroundColor(paper), 2.2), outline: tx.foregroundColor(tint.opacity(0.22)),
                             opacity: subA * (1 - noteA * 0.25))
            }
        }
        if noteA > 0.5 && labelSpacing > 11 {
            let visible = a.notePos.filter { view.contains(screen($0.value, c)) }.sorted { g.degree[$0.key] > g.degree[$1.key] }.prefix(500)
            for (i, p) in visible {
                let s = screen(p, c)
                let tx = Text(g.names[i]).font(MobileTheme.serif(labelSpacing > 22 ? 12 : 10.5))
                placer.place(&ctx, tx.foregroundColor(ink.opacity(0.88)), at: CGPoint(x: s.x, y: s.y + 5), anchor: .top,
                             halo: (tx.foregroundColor(paper), 1.6))
            }
        }
    }

    var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Picker("Mode", selection: $vault.graphAtlas) {
                    Text("Focus").tag(false)
                    Text("Atlas").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)
                if vault.graphAtlas {
                    Picker("Group", selection: $grouping) {
                        Text("Folders").tag(Atlas.Grouping.folders)
                        Text("Tags").tag(Atlas.Grouping.tags)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 150)
                }
                filterMenu
                Spacer(minLength: 0)
                Button("Fit") { refit(animated: true) }
                    .font(.subheadline)
                Button("Close") { vault.closeGraph() }
                    .font(.subheadline)
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Color.faint)
                TextField("Highlight notes", text: $query)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit { jumpToMatch() }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.paper, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.hairline))
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    var filterMenu: some View {
        Menu {
            Section("Folder") {
                Button(folderFilter.isEmpty ? "✓ Whole vault" : "Whole vault") { folderFilter = "" }
                ForEach(topFolders, id: \.self) { f in
                    Button(folderFilter == f ? "✓ \(f)" : f) { folderFilter = f }
                }
            }
            Section("Tag") {
                Button(tagFilter.isEmpty ? "✓ Any tag" : "Any tag") { tagFilter = "" }
                ForEach(topTags, id: \.self) { t in
                    Button(tagFilter == t ? "✓ #\(t)" : "#\(t)") { tagFilter = t }
                }
            }
            Divider()
            Toggle("Show orphans", isOn: $showOrphans)
            Toggle("Hierarchy only (partOf)", isOn: $hierarchyOnly)
            if !folderFilter.isEmpty || !tagFilter.isEmpty || recency > 0 {
                Button("Clear filters") { folderFilter = ""; tagFilter = ""; recency = 0 }
            }
        } label: {
            Label(filterLabel, systemImage: "line.3.horizontal.decrease")
                .font(.subheadline)
        }
    }

    var filterLabel: String {
        var parts: [String] = []
        if !folderFilter.isEmpty { parts.append(folderFilter) }
        if !tagFilter.isEmpty { parts.append("#" + tagFilter) }
        if hierarchyOnly && !vault.graphAtlas { parts.append("Hierarchy") }
        return parts.isEmpty ? "Filter" : parts.joined(separator: " · ")
    }

    var topFolders: [String] {
        guard let snap = vault.snapshot else { return [] }
        var out = Set(snap.folders.compactMap { $0.split(separator: "/").first.map(String.init) }).sorted()
        if !folderFilter.isEmpty && !out.contains(folderFilter) { out.append(folderFilter) }
        return out
    }

    var topTags: [String] {
        (vault.snapshot?.tags ?? [:]).sorted { $0.value.count > $1.value.count }.prefix(20).map(\.key)
    }

    func jumpToMatch() {
        guard let i = matches.sorted(by: { (store.index?.names[$0] ?? "") < (store.index?.names[$1] ?? "") }).first else { return }
        if vault.graphAtlas, let a = store.atlas, let p = a.notePos[i] {
            let z = max(camera(Date()).zoom, fitZoom * 3)
            setCamera(GraphCamera(zoom: z, pan: -p * z), animated: true)
        } else {
            setFocus(i)
        }
    }

    var breadcrumbs: some View {
        HStack(spacing: 6) {
            Button { back() } label: {
                Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Color.muted)
            if let g = store.index {
                ForEach(Array(trail.suffix(5).enumerated()), id: \.offset) { k, i in
                    Button(g.names[i]) {
                        jumpBack(to: trail.count - min(5, trail.count) + k)
                    }
                    .font(MobileTheme.serif(13))
                    .foregroundStyle(Color.muted)
                    .lineLimit(1)
                    Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(Color.faint)
                }
                if let f = focus {
                    Text(g.names[f]).font(MobileTheme.serif(13, bold: true)).foregroundStyle(Color.ink).lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 24)
    }

    func jumpBack(to k: Int) {
        guard trail.indices.contains(k) else { return }
        let target = trail[k]
        trail = Array(trail.prefix(k))
        setFocus(target, record: false)
    }

    func orphanPositions(_ a: Atlas, _ g: GraphIndex) -> [Int: SIMD2<Double>] {
        guard showOrphans, !a.orphans.isEmpty else { return [:] }
        let tops = a.clusters.filter { $0.level == 0 }
        var byKey: [String: AtlasCluster] = [:]
        for c in tops { byKey[c.key.lowercased()] = c }
        var lo = SIMD2(Double.infinity, .infinity), hi = -lo
        for c in tops { lo = simd_min(lo, c.center - c.radius); hi = simd_max(hi, c.center + c.radius) }
        let mid = tops.isEmpty ? .zero : (lo + hi) / 2
        let outer = tops.isEmpty ? 200.0 : simd_length(hi - lo) / 2
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

    var legend: some View {
        Text(vault.graphAtlas
             ? "Pinch to zoom · drag to pan · tap a note to open · tap a folder to fill the view"
             : "Pinch to zoom · drag to pan · tap a note to open")
            .font(.caption)
            .foregroundStyle(Color.faint)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
    }
}

/// Compact filters and mode switch for the Graph sidebar tab.
struct GraphSidebar: View {
    @EnvironmentObject private var vault: MobileVault

    var body: some View {
        List {
            Section {
                Picker("View", selection: $vault.graphAtlas) {
                    Text("Focus").tag(false)
                    Text("Atlas").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            } header: {
                Text("Graph")
            } footer: {
                Text(vault.graphAtlas
                     ? "The atlas is the whole vault, clustered by folder or tag. Pinch in to see notes; tap a note to open it."
                     : "The focus graph puts the current note at the center, with its links around it. Tap a note to open it.")
            }
            Section {
                Button("Show graph") { vault.openGraph(atlas: vault.graphAtlas) }
                if vault.selectedNote != nil {
                    Button("Focus on this note") { vault.openGraph(atlas: false) }
                }
                Button("Open atlas") { vault.openGraph(atlas: true) }
            }
        }
        .listStyle(.insetGrouped)
    }
}
