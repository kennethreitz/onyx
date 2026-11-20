import SwiftUI
import OnyxCore
import simd

/// A force-directed graph of wikilinks, drawn like a TikZ figure:
/// ink dots, hairline edges, Latin Modern labels on paper.
@MainActor @Observable
final class GraphModel {
    var data: GraphData?
    var focus: String?
    var settled = false
    private var task: Task<Void, Never>?

    func load(_ snap: VaultSnapshot, focus: String?, local: Bool) {
        task?.cancel()
        settled = false
        self.focus = focus
        let f = local ? focus : nil
        task = Task {
            var g = await Task.detached(priority: .userInitiated) { () -> GraphData in
                var g = GraphData.build(snap, focus: f, depth: 2)
                g.layout(iterations: 40, pinned: f.flatMap { g.ids.firstIndex(of: $0) })
                return g
            }.value
            if Task.isCancelled { return }
            data = g
            // keep settling, animating as we go
            let pinned = f.flatMap { g.ids.firstIndex(of: $0) }
            let total = g.ids.count > 800 ? 260 : 360
            while g.iterationsRun < total && !Task.isCancelled {
                let cur = g
                g = await Task.detached { var x = cur; x.layout(iterations: 6, pinned: pinned); return x }.value
                if Task.isCancelled { return }
                data = g
            }
            settled = true
        }
    }
    func cancel() { task?.cancel() }
}

struct GraphView: View {
    @Bindable var ws: Workspace
    @State private var model = GraphModel()
    @State private var zoom: CGFloat = 1
    @State private var baseZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var basePan: CGSize = .zero
    @State private var hover: Int? = nil
    @State private var fitted = false
    @State private var scrollMonitor: Any?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color.paper.opacity(0.985).ignoresSafeArea()
                canvas(size: geo.size)
                header
            }
            .onAppear { reload(); installScroll() }
            .onDisappear { model.cancel(); if let m = scrollMonitor { NSEvent.removeMonitor(m) } }
            .onChange(of: ws.graphLocal) { reload() }
            .onChange(of: model.data?.ids.count) { fit(geo.size) }
        }
    }

    var header: some View {
        HStack(spacing: 14) {
            Text(ws.graphLocal ? (ws.currentNote?.name ?? "Local graph") : "Graph").font(Theme.titleSerif(17)).foregroundStyle(Color.ink)
            if let d = model.data {
                Text("\(d.ids.count) notes · \(d.edges.count) links\(model.settled ? "" : " · settling")").font(.system(size: 11)).foregroundStyle(Color.faint)
            }
            Spacer()
            Picker("", selection: $ws.graphLocal) {
                Text("Global").tag(false)
                Text("Local").tag(true)
            }.pickerStyle(.segmented).frame(width: 150).labelsHidden()
            Button { ws.show(.graph) } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.muted) }
                .buttonStyle(.plain).help("Close (Esc)")
        }
        .padding(.horizontal, 24).padding(.top, 30)
    }

    func reload() {
        guard let snap = ws.snapshot else { return }
        fitted = false
        model.load(snap, focus: ws.currentPath, local: ws.graphLocal)
    }

    func fit(_ size: CGSize) {
        guard let d = model.data, !d.positions.isEmpty else { return }
        let b = d.bounds
        let w = CGFloat(b.max.x - b.min.x) + 80, h = CGFloat(b.max.y - b.min.y) + 80
        zoom = min(4, max(0.08, min(size.width / w, (size.height - 80) / h)))
        baseZoom = zoom
        let c = (b.min + b.max) / 2
        pan = CGSize(width: -CGFloat(c.x) * zoom, height: -CGFloat(c.y) * zoom + 20)
        basePan = pan
        fitted = true
    }

    func screen(_ p: SIMD2<Float>, _ size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2 + CGFloat(p.x) * zoom + pan.width, y: size.height / 2 + CGFloat(p.y) * zoom + pan.height)
    }

    func radius(_ deg: Int) -> CGFloat { (2.2 + sqrt(CGFloat(deg)) * 1.25) * max(0.55, min(zoom, 1.6)) }

    func canvas(size: CGSize) -> some View {
        let d = model.data
        let focusIndex = d.flatMap { dd in model.focus.flatMap { dd.ids.firstIndex(of: $0) } }
        var neighbors = Set<Int>()
        if let h = hover, let d { for (a, b) in d.edges { if a == h { neighbors.insert(b) }; if b == h { neighbors.insert(a) } } }
        return Canvas { ctx, sz in
            guard let d else { return }
            let ink = Color.ink
            var edges = Path()
            var hot = Path()
            for (a, b) in d.edges {
                let p = screen(d.positions[a], sz), q = screen(d.positions[b], sz)
                if hover != nil && (a == hover || b == hover) { hot.move(to: p); hot.addLine(to: q) }
                else { edges.move(to: p); edges.addLine(to: q) }
            }
            ctx.stroke(edges, with: .color(ink.opacity(hover == nil ? 0.16 : 0.06)), lineWidth: 0.6)
            ctx.stroke(hot, with: .color(ink.opacity(0.8)), lineWidth: 0.9)
            let showAllLabels = zoom > 1.1 || d.ids.count < 120
            for i in d.ids.indices {
                let p = screen(d.positions[i], sz)
                guard p.x > -40 && p.y > -40 && p.x < sz.width + 40 && p.y < sz.height + 40 else { continue }
                let r = radius(d.degree[i])
                let dim = hover != nil && hover != i && !neighbors.contains(i)
                let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                if i == focusIndex {
                    ctx.fill(Path(ellipseIn: rect.insetBy(dx: -2.5, dy: -2.5)), with: .color(Color.paper))
                    ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -2.5, dy: -2.5)), with: .color(ink), lineWidth: 1)
                }
                ctx.fill(Path(ellipseIn: rect), with: .color(ink.opacity(dim ? 0.2 : (d.degree[i] == 0 ? 0.35 : 0.88))))
                let big = d.degree[i] >= max(8, d.ids.count / 60)
                if i == hover || neighbors.contains(i) || i == focusIndex || (showAllLabels && !dim) || (big && hover == nil) {
                    let size: CGFloat = i == hover ? 14 : (big ? 12.5 : 11)
                    let t = Text(d.labels[i]).font(Theme.serif(size, bold: i == hover || i == focusIndex)).foregroundColor(dim ? Color.faint : Color.ink)
                    ctx.draw(t, at: CGPoint(x: p.x, y: p.y + r + 8), anchor: .top)
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 2)
            .onChanged { v in pan = CGSize(width: basePan.width + v.translation.width, height: basePan.height + v.translation.height) }
            .onEnded { _ in basePan = pan })
        .simultaneousGesture(MagnifyGesture()
            .onChanged { v in zoom = max(0.05, min(8, baseZoom * v.magnification)) }
            .onEnded { _ in baseZoom = zoom })
        .onContinuousHover { phase in
            switch phase {
            case .active(let loc): hover = nearest(loc, size)
            case .ended: hover = nil
            }
        }
        .onTapGesture(count: 1, coordinateSpace: .local) { loc in
            if let i = nearest(loc, size), let d = model.data { ws.openNote(d.ids[i]) }
        }
    }

    func nearest(_ loc: CGPoint, _ size: CGSize) -> Int? {
        guard let d = model.data else { return nil }
        var best: Int? = nil
        var bestD = CGFloat.greatestFiniteMagnitude
        for i in d.ids.indices {
            let p = screen(d.positions[i], size)
            let dd = (p.x - loc.x) * (p.x - loc.x) + (p.y - loc.y) * (p.y - loc.y)
            let r = radius(d.degree[i]) + 6
            if dd <= r * r && dd < bestD { best = i; bestD = dd }
        }
        return best
    }

    func installScroll() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { e in
            guard ws.overlay == .graph else { return e }
            if e.modifierFlags.contains(.command) || !e.hasPreciseScrollingDeltas {
                let f = exp(e.scrollingDeltaY * (e.hasPreciseScrollingDeltas ? 0.01 : 0.08))
                let nz = max(0.05, min(8, zoom * f))
                pan = CGSize(width: pan.width * nz / zoom, height: pan.height * nz / zoom)
                zoom = nz
            } else {
                pan.width += e.scrollingDeltaX; pan.height += e.scrollingDeltaY
            }
            baseZoom = zoom; basePan = pan
            return nil
        }
    }
}
