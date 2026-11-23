import AppKit
import SwiftUI
import AVFoundation
import AVKit
import PDFKit
import UniformTypeIdentifiers
import OnyxCore

/// Attachments open in the pane, like notes: images (fit, zoom, pan, animated GIFs), audio
/// (Onyx's own player, with the Record Audio transcript), video (AVKit), PDFs (PDFKit, with
/// page, zoom and find), and a file card for everything else. ⌘[ goes back to the note.
struct FileView: View {
    var ws: Workspace
    let path: String
    /// The focused pane (keys go to it; unfocused panes stay quiet).
    var focused: Bool = true
    @State private var meta = ""
    @State private var image = ImageViewer.Controller()
    @State private var pdf = PDFViewer.Controller()
    @State private var unsupported = false

    var url: URL? { ws.root?.appendingPathComponent(path) }
    var kind: AttachmentKind { AttachmentKind.of(path) }
    var exists: Bool { url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.hairline).frame(height: 0.5)
            Group {
                if let url, exists {
                    switch unsupported ? .other : kind {
                    case .image: ImageViewer(url: url, controller: image, unsupported: $unsupported, meta: $meta)
                    case .pdf: PDFViewer(url: url, controller: pdf, meta: $meta)
                    case .audio: AudioPlayerView(ws: ws, path: path, url: url, focused: focused, unsupported: $unsupported, meta: $meta)
                    case .video: VideoViewer(url: url, unsupported: $unsupported, meta: $meta)
                    case .other: FileCard(ws: ws, path: path, url: url, note: unsupported ? "Onyx can’t preview this \(kind == .other ? "file" : kind.label.lowercased()) here." : nil)
                    }
                } else {
                    VStack { Spacer(); QuietEmpty(title: "This file is gone.", hint: "It was moved or deleted outside Onyx.").frame(maxWidth: 320); Spacer() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 28).padding(.bottom, 30)
        .background(Color.paper)
    }

    var sizeText: String {
        guard let url, let n = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }

    var header: some View {
        HStack(spacing: Space.m) {
            if focused, ws.canGoBack { FooterButton(symbol: "chevron.left", help: "Back  ⌘[") { ws.goBack() } }
            Image(systemName: kind.symbol).font(.system(size: 11)).foregroundStyle(Color.faint)
            Text([kind.label, sizeText, meta].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: TypeScale.small).monospacedDigit()).foregroundStyle(Color.muted).lineLimit(1)
            Spacer(minLength: Space.m)
            if !unsupported, kind == .image { imageControls }
            if !unsupported, kind == .pdf { pdfControls }
            LinkedFromMenu(ws: ws, path: path)
            FooterButton(symbol: "pencil.line", help: "Rename…") { ws.confirmRename(path) }
            FooterButton(symbol: "arrow.up.forward.app", help: "Open in Default App") { if let url { NSWorkspace.shared.open(url) } }
            FooterButton(symbol: "folder", help: "Reveal in Finder") { ws.revealInFinder(path) }
        }
        .padding(.horizontal, Space.l).frame(height: 30)
    }

    @ViewBuilder var imageControls: some View {
        FooterButton(symbol: "minus.magnifyingglass", help: "Zoom Out") { image.zoom(1 / 1.25) }
        Text(image.percent).font(.system(size: TypeScale.caption).monospacedDigit()).foregroundStyle(Color.faint).frame(minWidth: 34)
        FooterButton(symbol: "plus.magnifyingglass", help: "Zoom In") { image.zoom(1.25) }
        FooterButton(symbol: "arrow.down.right.and.arrow.up.left", help: "Fit", on: image.fitting) { image.fit() }
        FooterButton(symbol: "1.magnifyingglass", help: "Actual Size") { image.actual() }
    }

    @ViewBuilder var pdfControls: some View {
        TextField("Find", text: $pdf.query).textFieldStyle(.plain)
            .font(.system(size: TypeScale.small)).frame(width: 110)
            .padding(.horizontal, Space.s).padding(.vertical, 3)
            .background(Color.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: Radius.small))
            .onSubmit { pdf.find(backwards: NSEvent.modifierFlags.contains(.shift)) }
        if pdf.matches > 0 { Text("\(pdf.matchIndex)/\(pdf.matches)").font(.system(size: TypeScale.caption).monospacedDigit()).foregroundStyle(Color.faint) }
        FooterButton(symbol: "chevron.up", help: "Previous Page") { pdf.view?.goToPreviousPage(nil) }
        Text(pdf.pageLabel).font(.system(size: TypeScale.caption).monospacedDigit()).foregroundStyle(Color.faint)
        FooterButton(symbol: "chevron.down", help: "Next Page") { pdf.view?.goToNextPage(nil) }
        FooterButton(symbol: "minus.magnifyingglass", help: "Zoom Out") { pdf.view?.zoomOut(nil) }
        FooterButton(symbol: "plus.magnifyingglass", help: "Zoom In") { pdf.view?.zoomIn(nil) }
        FooterButton(symbol: "arrow.down.right.and.arrow.up.left", help: "Fit Width") { pdf.view?.autoScales = true }
    }
}

/// "Linked from": the notes that link to or embed this file.
struct LinkedFromMenu: View {
    var ws: Workspace
    let path: String
    var body: some View {
        let sources = Array(Set((ws.snapshot?.backlinks(to: path) ?? []).map(\.source))).sorted()
        if !sources.isEmpty {
            Menu {
                ForEach(sources, id: \.self) { s in
                    Button(((s as NSString).lastPathComponent as NSString).deletingPathExtension) { ws.openNote(s) }
                }
            } label: {
                Text(sources.count == 1 ? "1 note" : "\(sources.count) notes").font(.system(size: TypeScale.caption)).foregroundStyle(Color.faint)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Notes that link here")
        }
    }
}

// MARK: Images

/// NSScrollView with magnification: fit by default (never enlarged past 100%), ⌘+/⌘- style
/// zoom from the header, pinch, drag to pan, double-click toggles fit ⇄ actual size.
struct ImageViewer: NSViewRepresentable {
    let url: URL
    var controller: Controller
    @Binding var unsupported: Bool
    @Binding var meta: String

    @Observable final class Controller {
        @ObservationIgnored weak var scroll: ImageScrollView?
        var fitting = true
        var magnification: CGFloat = 1
        var percent: String { "\(Int((magnification * 100).rounded()))%" }
        func fit() { scroll?.fit(); fitting = true; sync() }
        func actual() { scroll?.setMag(1); fitting = false; sync() }
        func zoom(_ f: CGFloat) { guard let s = scroll else { return }; s.setMag(s.magnification * f); fitting = false; sync() }
        func sync() { magnification = scroll?.magnification ?? 1 }
    }

    func makeNSView(context: Context) -> ImageScrollView {
        let s = ImageScrollView()
        s.controller = controller
        controller.scroll = s
        load(s)
        return s
    }
    func updateNSView(_ s: ImageScrollView, context: Context) {
        if s.url != url { load(s) }
    }
    func load(_ s: ImageScrollView) {
        s.url = url
        guard let img = NSImage(contentsOf: url), img.size.width > 0, img.size.height > 0 else {
            DispatchQueue.main.async { unsupported = true }
            return
        }
        s.show(img)
        let rep = img.representations.first
        let w = rep?.pixelsWide ?? 0, h = rep?.pixelsHigh ?? 0
        let m = w > 0 && h > 0 ? "\(w)×\(h)" : "\(Int(img.size.width))×\(Int(img.size.height))"
        DispatchQueue.main.async { meta = m; controller.fitting = true; controller.sync() }
    }
}

final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposed: NSRect) -> NSRect {
        var r = super.constrainBoundsRect(proposed)
        guard let doc = documentView else { return r }
        if r.width > doc.frame.width { r.origin.x = (doc.frame.width - r.width) / 2 }
        if r.height > doc.frame.height { r.origin.y = (doc.frame.height - r.height) / 2 }
        return r
    }
}

final class PanningImageView: NSImageView {
    private var last: NSPoint?
    override func mouseDown(with e: NSEvent) {
        if e.clickCount == 2, let s = enclosingScrollView as? ImageScrollView { s.toggleFit(); return }
        last = e.locationInWindow
        NSCursor.closedHand.push()
    }
    override func mouseDragged(with e: NSEvent) {
        guard let l = last, let clip = enclosingScrollView?.contentView else { return }
        let p = e.locationInWindow
        let m = enclosingScrollView?.magnification ?? 1
        var o = clip.bounds.origin
        o.x -= (p.x - l.x) / m; o.y -= (p.y - l.y) / m
        clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: o, size: clip.bounds.size)).origin)
        enclosingScrollView?.reflectScrolledClipView(clip)
        last = p
    }
    override func mouseUp(with e: NSEvent) { if last != nil { NSCursor.pop() }; last = nil }
}

final class ImageScrollView: NSScrollView {
    var url: URL?
    weak var controller: ImageViewer.Controller?
    let imageView = PanningImageView()
    private var lastSize: NSSize = .zero

    init() {
        super.init(frame: .zero)
        contentView = CenteringClipView()
        drawsBackground = false
        contentView.drawsBackground = false
        hasVerticalScroller = true; hasHorizontalScroller = true; autohidesScrollers = true
        scrollerStyle = .overlay
        allowsMagnification = true
        minMagnification = 0.02; maxMagnification = 32
        imageView.imageScaling = .scaleAxesIndependently
        imageView.animates = true   // GIFs play
        imageView.isEditable = false
        documentView = imageView
        NotificationCenter.default.addObserver(forName: NSScrollView.didEndLiveMagnifyNotification, object: self, queue: .main) { [weak self] _ in
            self?.controller?.fitting = false; self?.controller?.sync()
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(_ img: NSImage) {
        imageView.image = img
        imageView.frame = NSRect(origin: .zero, size: img.size)
        DispatchQueue.main.async { self.fit() }
    }
    func fitScale() -> CGFloat {
        guard let s = imageView.image?.size, s.width > 0, s.height > 0, bounds.width > 0 else { return 1 }
        let inset: CGFloat = 32
        return min(1, (bounds.width - inset) / s.width, (bounds.height - inset) / s.height)
    }
    func fit() { setMag(fitScale()) }
    func setMag(_ m: CGFloat) {
        let m = min(max(m, minMagnification), maxMagnification)
        let c = NSPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
        setMagnification(m, centeredAt: c)
    }
    func toggleFit() {
        if controller?.fitting == true || abs(magnification - fitScale()) < 0.01 { controller?.actual() } else { controller?.fit() }
    }
    override func layout() {
        super.layout()
        if bounds.size != lastSize {
            lastSize = bounds.size
            if controller?.fitting ?? true { fit(); controller?.sync() }
        }
    }
}

// MARK: PDF

struct PDFViewer: NSViewRepresentable {
    let url: URL
    var controller: Controller
    @Binding var meta: String

    @Observable final class Controller {
        @ObservationIgnored weak var view: PDFView?
        var pageLabel = ""
        var query = "" { didSet { if query != oldValue { hits = []; matches = 0; matchIndex = 0 } } }
        var matches = 0
        var matchIndex = 0
        @ObservationIgnored private var hits: [PDFSelection] = []
        func find(backwards: Bool) {
            guard let v = view, let doc = v.document, !query.isEmpty else { return }
            if hits.isEmpty {
                hits = doc.findString(query, withOptions: [.caseInsensitive, .diacriticInsensitive])
                matches = hits.count; matchIndex = 0
                v.highlightedSelections = hits.map { s in s.color = Theme.findMatch; return s }
            }
            guard !hits.isEmpty else { NSSound.beep(); return }
            matchIndex = backwards ? (matchIndex <= 1 ? hits.count : matchIndex - 1) : (matchIndex % hits.count) + 1
            let s = hits[matchIndex - 1]
            v.setCurrentSelection(s, animate: false)
            v.go(to: s)
        }
        func updatePage() {
            guard let v = view, let doc = v.document, let p = v.currentPage else { return }
            pageLabel = "\(doc.index(for: p) + 1) / \(doc.pageCount)"
        }
    }

    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displaysPageBreaks = true
        v.backgroundColor = Theme.paperAlt
        controller.view = v
        NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: v, queue: .main) { [weak controller] _ in controller?.updatePage() }
        load(v)
        return v
    }
    func updateNSView(_ v: PDFView, context: Context) {
        if v.document?.documentURL != url { load(v) }
    }
    func load(_ v: PDFView) {
        let doc = PDFDocument(url: url)
        v.document = doc
        let n = doc?.pageCount ?? 0
        DispatchQueue.main.async {
            meta = doc == nil ? "can’t read" : (n == 1 ? "1 page" : "\(n) pages")
            controller.updatePage()
        }
    }
}

// MARK: Video

struct VideoViewer: NSViewRepresentable {
    let url: URL
    @Binding var unsupported: Bool
    @Binding var meta: String

    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.controlsStyle = .inline
        v.showsFullScreenToggleButton = true
        load(v)
        return v
    }
    func updateNSView(_ v: AVPlayerView, context: Context) {
        if (v.player?.currentItem?.asset as? AVURLAsset)?.url != url { load(v) }
    }
    static func dismantleNSView(_ v: AVPlayerView, coordinator: ()) { v.player?.pause(); v.player = nil }
    func load(_ v: AVPlayerView) {
        v.player?.pause()
        let asset = AVURLAsset(url: url)
        v.player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        Task { @MainActor in
            let (playable, d) = ((try? await asset.load(.isPlayable)) ?? false, (try? await asset.load(.duration)) ?? .zero)
            if !playable { unsupported = true; return }
            var m = d.seconds.isFinite && d.seconds > 0 ? AudioNote.elapsed(d.seconds) : ""
            if let t = try? await asset.loadTracks(withMediaType: .video).first, let s = try? await t.load(.naturalSize), s.width > 0 {
                m += (m.isEmpty ? "" : " · ") + "\(Int(abs(s.width)))×\(Int(abs(s.height)))"
            }
            meta = m
        }
    }
}

// MARK: Anything else

struct FileCard: View {
    var ws: Workspace
    let path: String
    let url: URL
    var note: String? = nil
    var body: some View {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .localizedTypeDescriptionKey])
        VStack(spacing: Space.l) {
            Spacer()
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 72, height: 72)
            Text(url.lastPathComponent).font(Theme.serif(17)).foregroundStyle(Color.ink).multilineTextAlignment(.center)
            Text([values?.localizedTypeDescription, values?.fileSize.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) },
                  values?.contentModificationDate.map { $0.formatted(date: .abbreviated, time: .shortened) }].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: TypeScale.small)).foregroundStyle(Color.muted)
            if let note { Text(note).font(Theme.serif(13.5, italic: true)).foregroundStyle(Color.muted) }
            HStack(spacing: Space.m) {
                Button("Open in Default App") { NSWorkspace.shared.open(url) }.keyboardShortcut(.defaultAction)
                Button("Reveal in Finder") { ws.revealInFinder(path) }
            }.controlSize(.regular)
            Spacer()
        }
        .padding(Space.xxl)
        .frame(maxWidth: 460)
    }
}
