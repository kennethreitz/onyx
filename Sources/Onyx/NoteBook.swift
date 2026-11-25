import AppKit
import CoreText
import PDFKit
import UniformTypeIdentifiers
import WebKit
import OnyxCore

/// File ▸ Export Selection as PDF… / Export Folder as PDF…: a typeset book of the
/// selected notes and folders, with a table of contents, folder part pages, and each
/// note starting on a new page (margin notes and a running head, same as a single-note export).
@MainActor
final class NoteBookPrinter: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let job: NotePrinter.Job
    let items: [SectionExport.Item]
    let title: String
    let face: String
    let sidenotes: Bool
    var page: NotePrinter.Page
    let typeset: [String: Any]
    let snap: VaultSnapshot
    let root: URL?
    var revealSuppressed = false

    private let handler = OnyxSchemeHandler()
    private var window: NSWindow?
    private var webView: WKWebView?
    private var polls = 0
    private var queue: [SectionExport.Item] = []
    private var current: SectionExport.Item?
    private var notePDFs: [String: URL] = [:]
    private var noteAnchors: [String: PDFLinkMap.AnchorSet] = [:]
    private static var running: [NoteBookPrinter] = []

    static func run(_ paths: [String], ws: Workspace, to given: URL? = nil) {
        guard let snap = ws.snapshot else { NSSound.beep(); return }
        let items = SectionExport.outline(selected: paths, root: snap.tree, children: ws.treeChildren)
        guard items.contains(where: { $0.kind == .note || $0.kind == .part }) else { NSSound.beep(); return }
        let name = SectionExport.defaultFilename(items)
        let job: NotePrinter.Job
        if let given { job = .export(given) }
        else {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = name
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            job = .export(url)
        }
        let info = NSPrintInfo.shared
        var page = NotePrinter.Page(paper: info.paperSize.width > 0 ? info.paperSize : CGSize(width: 612, height: 792))
        if !ws.sidenotes { page.noteFraction = 0; page.gapFraction = 0; page.left = 90; page.right = 90 }
        let typeset = Typeset.options(print: ["text": page.textWidth, "note": page.noteWidth, "gap": page.gap])
        let book = NoteBookPrinter(job: job, items: items, title: (name as NSString).deletingPathExtension,
                                   face: Typeset.faceName, sidenotes: ws.sidenotes, page: page, typeset: typeset,
                                   snap: snap, root: ws.root)
        book.handler.vaultRoot = ws.root
        book.revealSuppressed = given != nil
        running.append(book)
        book.start()
    }

    init(job: NotePrinter.Job, items: [SectionExport.Item], title: String, face: String, sidenotes: Bool,
         page: NotePrinter.Page, typeset: [String: Any], snap: VaultSnapshot, root: URL?) {
        self.job = job; self.items = items; self.title = title; self.face = face
        self.sidenotes = sidenotes; self.page = page; self.typeset = typeset; self.snap = snap; self.root = root
        self.queue = items.filter { $0.kind == .note }
    }

    private func start() {
        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(handler, forURLScheme: "onyx")
        cfg.userContentController.add(self, name: "onyx")
        let size = CGSize(width: (page.printable.width * 4 / 3).rounded(.up), height: (page.printable.height * 4 / 3).rounded())
        let wv = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: cfg)
        wv.navigationDelegate = self
        let w = NSWindow(contentRect: CGRect(x: -20000, y: -20000, width: size.width, height: size.height),
                         styleMask: [.borderless], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.contentView = wv
        w.orderBack(nil)
        window = w; webView = wv
        if queue.isEmpty {
            assemble()
            return
        }
        wv.load(URLRequest(url: URL(string: "onyx://app/web/reader.html")!))
    }

    nonisolated func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {}

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { renderNext() }

    private func renderNext() {
        guard let next = queue.first, let webView else { assemble(); return }
        current = next
        queue.removeFirst()
        polls = 0
        guard let note = snap.notes[next.path] else { renderNext(); return }
        let payload = ReaderPayload.build(text: note.content, path: next.path, snap: snap, dark: false,
                                          sidenotes: sidenotes, keepScroll: false, typeset: typeset, backlinks: false)
        let g = "{text: \(page.textWidth), note: \(page.noteWidth), gap: \(page.gap), size: \(page.bodySize), paper: [\(page.paper.width), \(page.paper.height)], margin: [\(page.top), \(page.right), \(page.bottom), \(page.left)]}"
        webView.evaluateJavaScript("Onyx.render(\(payload)); Onyx.setPrint(\(g)); true") { [weak self] _, _ in
            self?.waitUntilReady()
        }
    }

    private func waitUntilReady() {
        webView?.evaluateJavaScript("Onyx.printReady()") { [weak self] r, _ in
            guard let self else { return }
            self.polls += 1
            if (r as? Bool) == true || self.polls > 60 {
                self.captureAnchorsThenPaginate()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.waitUntilReady() }
            }
        }
    }

    private func captureAnchorsThenPaginate() {
        guard let webView else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.paginate() }
            return
        }
        webView.evaluateJavaScript("Onyx.printAnchors()") { [weak self] r, _ in
            guard let self else { return }
            if let current = self.current, let set = PDFLinkMap.AnchorSet(json: r) {
                self.noteAnchors[current.path] = set
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.paginate() }
        }
    }

    private func paginate() {
        guard let webView, let window, self.current != nil else { renderNext(); return }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("onyx-book-\(UUID().uuidString).pdf")
        let info = NSPrintInfo(dictionary: [:])
        info.paperSize = page.paper
        info.topMargin = page.top; info.bottomMargin = page.bottom
        info.leftMargin = page.left; info.rightMargin = page.right
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false; info.isVerticallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = tmp
        let op = webView.printOperation(with: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        op.view?.frame = webView.bounds
        pendingTmp = tmp
        op.runModal(for: window, delegate: self, didRun: #selector(printed(_:success:contextInfo:)), contextInfo: nil)
    }

    private var pendingTmp: URL?

    @objc nonisolated private func printed(_ op: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.didPaginate(success) } }
    }

    private func didPaginate(_ success: Bool) {
        if success, let tmp = pendingTmp, FileManager.default.fileExists(atPath: tmp.path), let current {
            notePDFs[current.path] = tmp
        }
        pendingTmp = nil
        renderNext()
    }

    private func assemble() {
        let out: URL
        switch job {
        case .export(let url): out = url
        case .print: out = FileManager.default.temporaryDirectory.appendingPathComponent("onyx-book-\(UUID().uuidString).pdf")
        }
        do {
            try writeBook(to: out)
        } catch {
            finish(nil)
            return
        }
        switch job {
        case .export(let url):
            finish(url)
            print("[pdf] \(url.path)"); fflush(stdout)
            if !revealSuppressed { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        case .print:
            finish(out)
            guard let doc = PDFDocument(url: out) else { return }
            let info = NSPrintInfo.shared.copy() as! NSPrintInfo
            info.topMargin = 0; info.bottomMargin = 0; info.leftMargin = 0; info.rightMargin = 0
            if let op = doc.printOperation(for: info, scalingMode: .pageScaleNone, autoRotate: false) {
                op.jobTitle = title
                op.showsPrintPanel = true
                if let w = MainWindow.current ?? NSApp.keyWindow { op.runModal(for: w, delegate: nil, didRun: nil, contextInfo: nil) } else { op.run() }
            }
        }
    }

    private func writeBook(to dst: URL) throws {
        // Count note pages first, then lay out the TOC (which needs those numbers), then
        // stitch TOC + part pages + notes with continuous folios and a running head.
        var noteCounts: [String: Int] = [:]
        var noteDocs: [String: CGPDFDocument] = [:]
        for it in items where it.kind == .note {
            guard let url = notePDFs[it.path], let doc = CGPDFDocument(url as CFURL), doc.numberOfPages > 0 else { continue }
            noteDocs[it.path] = doc
            noteCounts[it.path] = doc.numberOfPages
        }
        var start: [String: Int] = [:]
        func assign(tocPages: Int) {
            start.removeAll()
            var folio = tocPages + 1
            for it in items {
                start[it.path] = folio
                if it.kind == .part { folio += 1 }
                else { folio += noteCounts[it.path] ?? 0 }
            }
        }
        var tocURL = FileManager.default.temporaryDirectory.appendingPathComponent("onyx-toc-\(UUID().uuidString).pdf")
        assign(tocPages: 1)
        var toc = try PDFChrome.drawTOC(items: items, start: start, page: page, face: face, to: tocURL)
        var tocPages = toc.pages
        assign(tocPages: tocPages)
        if tocPages != (CGPDFDocument(tocURL as CFURL)?.numberOfPages ?? tocPages) {
            try? FileManager.default.removeItem(at: tocURL)
            tocURL = FileManager.default.temporaryDirectory.appendingPathComponent("onyx-toc-\(UUID().uuidString).pdf")
            toc = try PDFChrome.drawTOC(items: items, start: start, page: page, face: face, to: tocURL)
            tocPages = toc.pages
            assign(tocPages: tocPages)
        }

        var partURLs: [String: URL] = [:]
        for it in items where it.kind == .part {
            let u = FileManager.default.temporaryDirectory.appendingPathComponent("onyx-part-\(UUID().uuidString).pdf")
            try PDFChrome.drawPart(title: it.title, page: page, face: face, to: u)
            partURLs[it.path] = u
        }

        var leaves: [PDFChrome.Leaf] = []
        var folio = 1
        if let toc = CGPDFDocument(tocURL as CFURL) {
            for i in 1...toc.numberOfPages {
                leaves.append(.init(doc: toc, index: i, head: i > 1 ? "Contents" : nil, folio: folio))
                folio += 1
            }
        }
        var partDocs: [String: CGPDFDocument] = [:]
        for it in items {
            if it.kind == .part, let url = partURLs[it.path], let doc = CGPDFDocument(url as CFURL), let pg = doc.page(at: 1) {
                _ = pg
                partDocs[it.path] = doc
                leaves.append(.init(doc: doc, index: 1, head: nil, folio: folio))
                folio += 1
            } else if it.kind == .note, let doc = noteDocs[it.path] {
                for i in 1...doc.numberOfPages {
                    leaves.append(.init(doc: doc, index: i, head: i > 1 ? it.title : nil, folio: folio))
                    folio += 1
                }
            }
        }
        try PDFChrome.write(leaves: leaves, page: page, face: face, title: title, to: dst)
        try linkBook(dst, start: start, toc: toc, noteCounts: noteCounts)
        try? FileManager.default.removeItem(at: tocURL)
        for u in partURLs.values { try? FileManager.default.removeItem(at: u) }
        for u in notePDFs.values { try? FileManager.default.removeItem(at: u) }
    }

    /// Clickable TOC rows, in-note heading links, and a PDF outline (bookmarks).
    private func linkBook(_ dst: URL, start: [String: Int], toc: PDFChrome.TOCLayout, noteCounts: [String: Int]) throws {
        let geo = PDFAnnotator.geometry(page)
        let destY = page.paper.height - page.top
        var jumps: [PDFLinkMap.Jump] = []
        var dests: [String: [String: (page: Int, y: CGFloat)]] = [:]
        for it in items where it.kind == .note {
            guard let set = noteAnchors[it.path], let first = start[it.path], let count = noteCounts[it.path], count > 0 else { continue }
            dests[it.path] = PDFLinkMap.destinations(in: set, geometry: geo, pageCount: count, pageOffset: first - 1)
        }
        func resolve(from path: String, heading: String, target: String) -> (page: Int, y: CGFloat)? {
            let destPath: String
            if target.isEmpty {
                destPath = path
            } else if dests[target] != nil {
                destPath = target
            } else if let it = items.first(where: {
                $0.kind == .note && ($0.path == target || $0.title == target
                    || (($0.path as NSString).deletingPathExtension as NSString).lastPathComponent == target)
            }) {
                destPath = it.path
            } else { return nil }
            return dests[destPath]?[PDFLinkMap.normalize(heading)]
        }
        for it in items where it.kind == .note {
            guard let set = noteAnchors[it.path], let first = start[it.path], let count = noteCounts[it.path], count > 0 else { continue }
            jumps.append(contentsOf: PDFLinkMap.jumps(in: set, geometry: geo, pageCount: count, pageOffset: first - 1) { heading, target in
                resolve(from: it.path, heading: heading, target: target)
            })
        }
        for link in toc.links {
            guard let dest = start[link.path] else { continue }
            if let it = items.first(where: { $0.path == link.path }), it.kind == .note, (noteCounts[it.path] ?? 0) == 0 { continue }
            jumps.append(PDFLinkMap.Jump(page: link.page, rect: link.rect, destPage: dest, destY: destY))
        }
        var flat: [(title: String, page: Int, depth: Int, y: CGFloat?)] = []
        for it in items {
            guard let folio = start[it.path] else { continue }
            if it.kind == .note, (noteCounts[it.path] ?? 0) == 0 { continue }
            flat.append((it.title, folio, it.depth, destY))
        }
        var kids: [Int: [PDFLinkMap.OutlineNode]] = [:]
        for it in items where it.kind == .note {
            guard let set = noteAnchors[it.path], let first = start[it.path], let count = noteCounts[it.path], count > 0 else { continue }
            let heads = PDFLinkMap.headingOutline(in: set, geometry: geo, pageCount: count, pageOffset: first - 1)
            if !heads.isEmpty { kids[first] = heads }
        }
        let outline = PDFLinkMap.graft(PDFLinkMap.nestOutline(flat), children: kids)
        try PDFAnnotator.apply(to: dst, jumps: jumps, outline: outline)
    }

    private func finish(_ url: URL?) {
        if url == nil { NSSound.beep() }
        window?.orderOut(nil); window?.contentView = nil; window = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "onyx")
        webView = nil
        NoteBookPrinter.running.removeAll { $0 === self }
    }
}

/// Shared Core Text drawing for running heads, folios, the TOC, and folder part pages.
enum PDFChrome {
    struct Leaf {
        var doc: CGPDFDocument
        var index: Int
        var head: String?
        var folio: Int
    }

    static func font(_ postScript: String, size: CGFloat, features: [String]) -> CTFont {
        let feats = features.map { [kCTFontOpenTypeFeatureTag: $0, kCTFontOpenTypeFeatureValue: 1] as [CFString: Any] }
        let d = CTFontDescriptorCreateWithAttributes([kCTFontNameAttribute: postScript, kCTFontFeatureSettingsAttribute: feats] as CFDictionary)
        return CTFontCreateWithFontDescriptor(d, size, nil)
    }

    static func line(_ s: String, _ f: CTFont, kern: CGFloat = 0, color: CGColor = CGColor(gray: 0.1, alpha: 1)) -> CTLine {
        let a = NSAttributedString(string: s, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): f,
                                                           NSAttributedString.Key(kCTKernAttributeName as String): kern,
                                                           NSAttributedString.Key(kCTForegroundColorAttributeName as String): color])
        return CTLineCreateWithAttributedString(a)
    }

    static func headFont(face: String, size: CGFloat = 9) -> CTFont {
        face == "et" ? font("ETBookOT-Roman", size: size, features: ["c2sc", "smcp", "kern"])
                     : font("LMRomanCaps10-Regular", size: size, features: ["kern"])
    }
    static func bodyFont(face: String, size: CGFloat = 10.5) -> CTFont {
        face == "et" ? font("ETBookOT-Roman", size: size, features: ["kern", "onum"])
                     : font("LMRoman10-Regular", size: size, features: ["kern", "onum"])
    }
    static func folioFont(face: String) -> CTFont {
        face == "et" ? font("ETBookOT-Roman", size: 10, features: ["onum", "kern"])
                     : font("LMRoman10-Regular", size: 10, features: ["onum", "kern"])
    }

    static func write(leaves: [Leaf], page: NotePrinter.Page, face: String, title: String, to dst: URL) throws {
        guard let first = leaves.first, let pg0 = first.doc.page(at: first.index) else { throw CocoaError(.fileReadCorruptFile) }
        var box = pg0.getBoxRect(.mediaBox)
        let meta: [CFString: Any] = [kCGPDFContextTitle: title, kCGPDFContextCreator: "Onyx", kCGPDFContextAuthor: NSFullUserName()]
        guard let ctx = CGContext(dst as CFURL, mediaBox: &box, meta as CFDictionary) else { throw CocoaError(.fileWriteUnknown) }
        let et = face == "et"
        let headF = headFont(face: face)
        let folioF = folioFont(face: face)
        for leaf in leaves {
            guard let pg = leaf.doc.page(at: leaf.index) else { continue }
            var mb = pg.getBoxRect(.mediaBox)
            ctx.beginPDFPage([kCGPDFContextMediaBox: Data(bytes: &mb, count: MemoryLayout<CGRect>.size)] as CFDictionary)
            ctx.drawPDFPage(pg)
            let x0 = mb.minX + page.left, w = page.textWidth
            if let raw = leaf.head, !raw.isEmpty {
                let text = et ? raw : raw.lowercased()
                let l = line(text, headF, kern: 0.9)
                let lw = CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil))
                ctx.textPosition = CGPoint(x: x0 + (w - min(lw, w)) / 2, y: mb.maxY - page.top + 26)
                CTLineDraw(l, ctx)
            }
            let f = line(String(leaf.folio), folioF)
            let fw = CGFloat(CTLineGetTypographicBounds(f, nil, nil, nil))
            ctx.textPosition = CGPoint(x: x0 + (w - fw) / 2, y: mb.minY + page.bottom - 36)
            CTLineDraw(f, ctx)
            copyLinks(pg, into: ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }

    struct TOCLink {
        var page: Int
        var rect: CGRect
        var path: String
    }
    struct TOCLayout {
        var pages: Int
        var links: [TOCLink]
    }

    /// Draw TOC pages; returns the page count and the clickable row rects (PDF space).
    static func drawTOC(items: [SectionExport.Item], start: [String: Int], page: NotePrinter.Page, face: String, to url: URL) throws -> TOCLayout {
        var box = CGRect(origin: .zero, size: page.paper)
        let meta: [CFString: Any] = [kCGPDFContextTitle: "Contents", kCGPDFContextCreator: "Onyx"]
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, meta as CFDictionary) else { throw CocoaError(.fileWriteUnknown) }
        let titleF = headFont(face: face, size: 18)
        let body = bodyFont(face: face, size: 11)
        let et = face == "et"
        let textW = page.textWidth
        let x0 = page.left
        let topY = page.paper.height - page.top
        let bottomY = page.bottom + 12
        let leading: CGFloat = 18
        var pages = 0
        var links: [TOCLink] = []

        func beginPage() -> CGFloat {
            var mb = box
            ctx.beginPDFPage([kCGPDFContextMediaBox: Data(bytes: &mb, count: MemoryLayout<CGRect>.size)] as CFDictionary)
            pages += 1
            if pages == 1 {
                let label = et ? "Contents" : "contents"
                let l = line(label, titleF, kern: 1.2)
                ctx.textPosition = CGPoint(x: x0, y: topY - 8)
                CTLineDraw(l, ctx)
                return topY - 8 - 36
            }
            return topY
        }

        var y = beginPage()
        for it in items {
            if y < bottomY + leading {
                ctx.endPDFPage()
                y = beginPage()
            }
            let indent = CGFloat(it.depth) * 16
            let folio = start[it.path].map(String.init) ?? ""
            let f = it.kind == .part ? headFont(face: face, size: 11) : body
            let name = et && it.kind == .part ? it.title : it.title
            let titleLine = line(name, f, kern: it.kind == .part ? 0.4 : 0)
            let folioLine = line(folio, folioFont(face: face))
            let tw = CGFloat(CTLineGetTypographicBounds(titleLine, nil, nil, nil))
            let fw = CGFloat(CTLineGetTypographicBounds(folioLine, nil, nil, nil))
            // Leader dots between the title and the page number.
            let dotsStart = x0 + indent + min(tw, textW - indent - fw - 16) + 6
            let dotsEnd = x0 + textW - fw - 6
            if dotsEnd > dotsStart {
                ctx.setStrokeColor(CGColor(gray: 0.55, alpha: 1))
                ctx.setLineWidth(0.4)
                ctx.setLineDash(phase: 0, lengths: [1.2, 3])
                ctx.move(to: CGPoint(x: dotsStart, y: y + 3))
                ctx.addLine(to: CGPoint(x: dotsEnd, y: y + 3))
                ctx.strokePath()
                ctx.setLineDash(phase: 0, lengths: [])
            }
            ctx.textPosition = CGPoint(x: x0 + indent, y: y)
            CTLineDraw(titleLine, ctx)
            ctx.textPosition = CGPoint(x: x0 + textW - fw, y: y)
            CTLineDraw(folioLine, ctx)
            let row = PDFLinkMap.tocRowRect(x: x0 + indent, y: y, width: textW - indent)
            if start[it.path] != nil, row.width > 0 {
                links.append(TOCLink(page: pages, rect: row, path: it.path))
            }
            y -= leading
        }
        ctx.endPDFPage()
        ctx.closePDF()
        return TOCLayout(pages: max(pages, 1), links: links)
    }

    static func drawPart(title: String, page: NotePrinter.Page, face: String, to url: URL) throws {
        var box = CGRect(origin: .zero, size: page.paper)
        let meta: [CFString: Any] = [kCGPDFContextTitle: title, kCGPDFContextCreator: "Onyx"]
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, meta as CFDictionary) else { throw CocoaError(.fileWriteUnknown) }
        ctx.beginPDFPage([kCGPDFContextMediaBox: Data(bytes: &box, count: MemoryLayout<CGRect>.size)] as CFDictionary)
        let f = headFont(face: face, size: 22)
        let et = face == "et"
        let text = et ? title : title.lowercased()
        let l = line(text, f, kern: 1.6)
        let lw = CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil))
        let x0 = page.left, w = page.textWidth
        ctx.textPosition = CGPoint(x: x0 + (w - min(lw, w)) / 2, y: page.paper.height * 0.62)
        CTLineDraw(l, ctx)
        ctx.endPDFPage()
        ctx.closePDF()
    }

    static func copyLinks(_ pg: CGPDFPage, into ctx: CGContext) {
        guard let dict = pg.dictionary else { return }
        var annots: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(dict, "Annots", &annots), let annots else { return }
        for j in 0..<CGPDFArrayGetCount(annots) {
            var a: CGPDFDictionaryRef?
            guard CGPDFArrayGetDictionary(annots, j, &a), let a else { continue }
            var action: CGPDFDictionaryRef?, uri: CGPDFStringRef?, rect: CGPDFArrayRef?
            guard CGPDFDictionaryGetDictionary(a, "A", &action), let action,
                  CGPDFDictionaryGetString(action, "URI", &uri), let uri,
                  let s = CGPDFStringCopyTextString(uri) as String?, let url = URL(string: s),
                  CGPDFDictionaryGetArray(a, "Rect", &rect), let rect, CGPDFArrayGetCount(rect) == 4 else { continue }
            var v = [CGPDFReal](repeating: 0, count: 4)
            for k in 0..<4 { CGPDFArrayGetNumber(rect, k, &v[k]) }
            ctx.setURL(url as CFURL, for: CGRect(x: min(v[0], v[2]), y: min(v[1], v[3]), width: abs(v[2] - v[0]), height: abs(v[3] - v[1])))
        }
    }
}
