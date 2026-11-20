import SwiftUI
import AppKit
import OnyxCore

/// One link-preview popover for the whole app. Hovering a reader link or an inspector relation
/// waits 400 ms, then shows the note's local relationship graph. Leaving the link closes it,
/// unless the pointer moves into the card.
@MainActor
final class GraphPreviewController: NSObject, NSPopoverDelegate {
    static let shared = GraphPreviewController()
    private var popover: NSPopover?
    private var showTimer: Timer?
    private var closeTimer: Timer?
    private var insideCard = false
    private(set) var shownPath: String?

    func schedule(ws: Workspace, path: String, rect: CGRect, in view: NSView) {
        guard ws.snapshot?.notes[path] != nil else { return }
        closeTimer?.invalidate(); showTimer?.invalidate()
        let delay = ProcessInfo.processInfo.environment["ONYX_PREVIEW_DELAY"].flatMap(Double.init) ?? 0.4
        showTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self, weak view] _ in
            MainActor.assumeIsolated {
                guard let self, let view, view.window != nil else { return }
                self.show(ws: ws, path: path, rect: rect, in: view)
            }
        }
    }

    func show(ws: Workspace, path: String, rect: CGRect, in view: NSView) {
        guard let snap = ws.snapshot else { return }
        let graph = RelationGraph.build(snap, center: path)
        let card = GraphPreviewCard(graph: graph, path: path,
            open: { [weak self] p in self?.close(); ws.openNote(p) },
            hover: { [weak self] inside in self?.insideCard = inside; if inside { self?.closeTimer?.invalidate() } else { self?.leaveLink() } })
        let host = NSHostingController(rootView: card)
        host.sizingOptions = [.preferredContentSize]
        if popover == nil {
            let p = NSPopover(); p.behavior = .semitransient; p.animates = false; p.delegate = self
            popover = p
        }
        popover?.contentViewController = host
        popover?.contentSize = NSSize(width: 340, height: 250)
        shownPath = path
        popover?.show(relativeTo: rect.insetBy(dx: -1, dy: -1), of: view, preferredEdge: view.isFlipped ? .maxY : .minY)   // below the link or button
    }

    func leaveLink() {
        showTimer?.invalidate()
        closeTimer?.invalidate()
        closeTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { if self?.insideCard == false { self?.close() } }
        }
    }
    func close() {
        showTimer?.invalidate(); closeTimer?.invalidate(); insideCard = false; shownPath = nil
        popover?.performClose(nil)
    }
    func popoverDidClose(_ notification: Notification) { shownPath = nil; insideCard = false }
}

struct GraphPreviewCard: View {
    var graph: RelationGraph
    var path: String
    var open: (String) -> Void
    var hover: (Bool) -> Void
    @State private var hot: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(graph.nodes.first?.name ?? "").font(Theme.titleSerif(15)).foregroundStyle(Color.ink).lineLimit(1)
                Spacer()
                Text(summary).font(.system(size: 10)).foregroundStyle(Color.faint)
            }
            GeometryReader { geo in
                Canvas { ctx, size in draw(&ctx, size) }
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        if case .active(let p) = phase { hot = hit(p, geo.size) } else { hot = nil }
                    }
                    .onTapGesture(coordinateSpace: .local) { p in open(hit(p, geo.size) ?? path) }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(width: 340, height: 250)
        .background(Color.paper)
        .onHover(perform: hover)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Graph preview for \(graph.nodes.first?.name ?? "note")")
    }

    var summary: String {
        let n = Dictionary(grouping: graph.nodes, by: \.role).mapValues(\.count)
        if let l = n[.link] { return "\(l + graph.hiddenParts) links" }
        return [("parent", n[.parent] ?? 0), ("part", (n[.part] ?? 0) + graph.hiddenParts), ("related", n[.related] ?? 0)]
            .filter { $0.1 > 0 }.map { "\($0.1) \($0.0)\($0.1 == 1 || $0.0 == "related" ? "" : "s")" }.joined(separator: " · ")
    }

    func point(_ n: RelationGraph.Node, _ s: CGSize) -> CGPoint {
        CGPoint(x: s.width / 2 + n.x * (s.width / 2 - 44), y: s.height / 2 + n.y * (s.height / 2 - 18))
    }
    func hit(_ p: CGPoint, _ s: CGSize) -> String? {
        graph.nodes.min { hypot(point($0, s).x - p.x, point($0, s).y - p.y) < hypot(point($1, s).x - p.x, point($1, s).y - p.y) }
            .flatMap { hypot(point($0, s).x - p.x, point($0, s).y - p.y) < 22 ? $0.path : nil }
    }

    func draw(_ ctx: inout GraphicsContext, _ s: CGSize) {
        guard let c = graph.nodes.first else { return }
        let cp = point(c, s)
        for n in graph.nodes.dropFirst() {
            let p = point(n, s)
            var line = Path(); line.move(to: cp)
            if n.role == .related { line.addQuadCurve(to: p, control: CGPoint(x: (cp.x + p.x) / 2, y: min(cp.y, p.y) - 18)) }
            else { line.addLine(to: p) }
            let style: StrokeStyle
            switch n.role {
            case .parent, .part: style = StrokeStyle(lineWidth: hot == n.path ? 1.6 : 1.05, lineCap: .round)
            case .related: style = StrokeStyle(lineWidth: hot == n.path ? 1.4 : 0.85, dash: [4, 3])
            case .sibling: style = StrokeStyle(lineWidth: 0.55, dash: [1, 3])
            default: style = StrokeStyle(lineWidth: 0.7)
            }
            let opacity = n.role == .sibling ? 0.18 : (hot == n.path ? 0.65 : 0.34)
            ctx.stroke(line, with: .color((n.role == .related ? Color.cursorBlue : Color.ink).opacity(opacity)), style: style)
        }
        var taken: [CGRect] = []
        let order = graph.nodes.sorted { a, b in (a.path == hot ? 0 : (a.role == .center ? 1 : (a.role == .sibling ? 3 : 2))) < (b.path == hot ? 0 : (b.role == .center ? 1 : (b.role == .sibling ? 3 : 2))) }
        for n in graph.nodes {
            let p = point(n, s)
            let r: CGFloat = n.role == .center ? 7 : (n.role == .sibling ? 3.2 : 4.6)
            let tint = n.role == .center ? Color.cursorBlue : ClusterPalette.color(n.path.split(separator: "/").first.map(String.init) ?? "vault")
            let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            if n.role == .center { ctx.fill(Path(ellipseIn: rect.insetBy(dx: -5, dy: -5)), with: .color(tint.opacity(0.14))) }
            ctx.fill(Path(ellipseIn: rect), with: .color(tint.opacity(n.role == .sibling ? 0.34 : 0.92)))
            if hot == n.path { ctx.stroke(Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)), with: .color(Color.cursorBlue), lineWidth: 1) }
        }
        // labels by priority (hovered, center, relations, siblings); a label that would collide waits for hover
        for n in order {
            let p = point(n, s)
            let r: CGFloat = n.role == .center ? 7 : (n.role == .sibling ? 3.2 : 4.6)
            let full = n.role == .center || hot == n.path
            let name = full || n.name.count <= 18 ? n.name : String(n.name.prefix(16)) + "…"
            let text = Text(name).font(Theme.serif(n.role == .center ? 12 : 10.5, bold: hot == n.path)).foregroundColor(n.role == .sibling ? Color.faint : Color.ink)
            let below = n.role == .part || n.role == .center
            let at = CGPoint(x: p.x, y: p.y + (below ? r + 3 : -r - 3))
            let res = ctx.resolve(text), sz = res.measure(in: CGSize(width: 300, height: 40))
            var box = CGRect(x: at.x - sz.width / 2, y: below ? at.y : at.y - sz.height, width: sz.width, height: sz.height).insetBy(dx: -3, dy: -1)
            box.origin.x = min(max(box.origin.x, 0), s.width - box.width)
            if !full && taken.contains(where: { $0.intersects(box) }) { continue }
            taken.append(box)
            ctx.draw(res, at: CGPoint(x: box.midX, y: below ? box.minY + 1 : box.maxY - 1), anchor: below ? .top : .bottom)
        }
        if graph.hiddenParts > 0 || graph.hiddenSiblings > 0 {
            let t = Text([graph.hiddenParts > 0 ? "+\(graph.hiddenParts) more" : nil, graph.hiddenSiblings > 0 ? "+\(graph.hiddenSiblings) siblings" : nil].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 9.5)).foregroundColor(Color.faint)
            ctx.draw(t, at: CGPoint(x: s.width - 2, y: s.height - 2), anchor: .bottomTrailing)
        }
    }
}

/// An inspector row's native hover hook. Tracking areas are geometry-based, so this background
/// view sees enter/exit even while the SwiftUI row handles taps.
struct GraphPreviewTrigger: NSViewRepresentable {
    var ws: Workspace
    var path: String
    func makeNSView(context: Context) -> TriggerView { let v = TriggerView(); v.ws = ws; v.path = path; return v }
    func updateNSView(_ v: TriggerView, context: Context) { v.ws = ws; v.path = path }
    final class TriggerView: NSView {
        weak var ws: Workspace?
        var path = ""
        override func updateTrackingAreas() {
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
        }
        override func mouseEntered(with event: NSEvent) { if let ws { GraphPreviewController.shared.schedule(ws: ws, path: path, rect: bounds, in: self) } }
        override func mouseExited(with event: NSEvent) { GraphPreviewController.shared.leaveLink() }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
