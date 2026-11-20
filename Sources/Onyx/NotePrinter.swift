import AppKit
import CoreText
import PDFKit
import UniformTypeIdentifiers
import WebKit

/// File ▸ Export as PDF… and Print…: the note set as a book page.
///
/// The reader page is laid out in an offscreen web view exactly as wide as the page's
/// text block plus its margin-note column, so the sidenote packing that runs on screen is
/// the packing on paper. WebKit paginates it (avoiding breaks inside figures, tables, code
/// and after headings, per typeset.css), and then we draw what CSS can't in WebKit, the
/// running head (the note's title in letterspaced small caps, from page 2) and the folio
/// (old-style page numbers), onto every page with Core Text. External links survive.
@MainActor
final class NotePrinter: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    enum Job { case export(URL), print }

    /// Book-page geometry, in points (the page CSS gets the same numbers in pt).
    struct Page {
        var paper: CGSize
        var top: CGFloat = 72, bottom: CGFloat = 76, left: CGFloat = 72, right: CGFloat = 54
        var noteFraction: CGFloat = 0.30, gapFraction: CGFloat = 0.045
        var bodySize: CGFloat = 10.5                     // pt, LaTeX's 10.5pt article
        var printable: CGSize { CGSize(width: paper.width - left - right, height: paper.height - top - bottom) }
        var textWidth: CGFloat { (printable.width * (1 - noteFraction - gapFraction)).rounded() }
        var noteWidth: CGFloat { (printable.width * noteFraction).rounded() }
        var gap: CGFloat { printable.width - textWidth - noteWidth }
    }

    private static var running: [NotePrinter] = []
    /// The test hook (`exportpdf <path>`) writes quietly, without a Finder window.
    var revealSuppressed = false

    let job: Job
    let title: String
    let payload: String
    let face: String
    let sidenotes: Bool
    var page: Page
    private let handler = OnyxSchemeHandler()
    private var window: NSWindow?
    private var webView: WKWebView?
    private var polls = 0
    private let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("onyx-print-\(UUID().uuidString).pdf")

    /// Export or print the focused note. For export, asks where to save first.
    static func run(_ kind: String, ws: Workspace, to given: URL? = nil) {
        guard let path = ws.currentPath, let snap = ws.snapshot else { NSSound.beep(); return }
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let job: Job
        if let given { job = .export(given) }
        else if kind == "export" {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = name + ".pdf"
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            job = .export(url)
        } else { job = .print }
        let info = NSPrintInfo.shared
        var page = Page(paper: info.paperSize.width > 0 ? info.paperSize : CGSize(width: 612, height: 792))
        if !ws.sidenotes { page.noteFraction = 0; page.gapFraction = 0; page.left = 90; page.right = 90 }
        let typeset = Typeset.options(print: ["text": page.textWidth, "note": page.noteWidth, "gap": page.gap])
        let payload = ReaderPayload.build(text: ws.text, path: path, snap: snap, dark: false, sidenotes: ws.sidenotes,
                                          keepScroll: false, typeset: typeset, backlinks: false)
        let p = NotePrinter(job: job, title: name, payload: payload, face: Typeset.faceName, sidenotes: ws.sidenotes, page: page)
        p.handler.vaultRoot = ws.root
        p.revealSuppressed = given != nil
        running.append(p)
        p.start()
    }

    init(job: Job, title: String, payload: String, face: String, sidenotes: Bool, page: Page) {
        self.job = job; self.title = title; self.payload = payload; self.face = face; self.sidenotes = sidenotes; self.page = page
    }

    private func start() {
        let cfg = WKWebViewConfiguration()
        cfg.setURLSchemeHandler(handler, forURLScheme: "onyx")
        cfg.userContentController.add(self, name: "onyx")
        // Wide enough (in CSS px, 4/3 of a point) to hold the text block and the note column.
        let size = CGSize(width: (page.printable.width * 4 / 3).rounded(.up), height: (page.printable.height * 4 / 3).rounded())
        let wv = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: cfg)
        wv.navigationDelegate = self
        let w = NSWindow(contentRect: CGRect(x: -20000, y: -20000, width: size.width, height: size.height), styleMask: [.borderless], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.contentView = wv
        w.orderBack(nil)
        window = w; webView = wv
        wv.load(URLRequest(url: URL(string: "onyx://app/web/reader.html")!))
    }

    nonisolated func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {}

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.paginate() }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.waitUntilReady() }
            }
        }
    }

    private func paginate() {
        guard let webView, let window else { return finish(nil) }
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
        op.runModal(for: window, delegate: self, didRun: #selector(printed(_:success:contextInfo:)), contextInfo: nil)
    }

    /// AppKit finishes a modal print operation on its own thread; everything after is main-actor work.
    @objc nonisolated private func printed(_ op: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.didPaginate(success) } }
    }

    private func didPaginate(_ success: Bool) {
        guard success, FileManager.default.fileExists(atPath: tmp.path) else { return finish(nil) }
        let out: URL
        switch job {
        case .export(let url): out = url
        case .print: out = FileManager.default.temporaryDirectory.appendingPathComponent("onyx-print-\(UUID().uuidString)-book.pdf")
        }
        do { try decorate(tmp, to: out) } catch { return finish(nil) }
        try? FileManager.default.removeItem(at: tmp)
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

    private func finish(_ url: URL?) {
        if url == nil { NSSound.beep() }
        window?.orderOut(nil); window?.contentView = nil; window = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "onyx")
        webView = nil
        NotePrinter.running.removeAll { $0 === self }
    }

    // MARK: Running head and folio

    private func font(_ postScript: String, size: CGFloat, features: [String]) -> CTFont {
        let feats = features.map { [kCTFontOpenTypeFeatureTag: $0, kCTFontOpenTypeFeatureValue: 1] as [CFString: Any] }
        let d = CTFontDescriptorCreateWithAttributes([kCTFontNameAttribute: postScript, kCTFontFeatureSettingsAttribute: feats] as CFDictionary)
        return CTFontCreateWithFontDescriptor(d, size, nil)
    }

    private func line(_ s: String, _ f: CTFont, kern: CGFloat = 0) -> CTLine {
        let a = NSAttributedString(string: s, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): f,
                                                           NSAttributedString.Key(kCTKernAttributeName as String): kern,
                                                           NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.1, alpha: 1)])
        return CTLineCreateWithAttributedString(a)
    }

    /// Copy each page into a fresh PDF, adding the head and folio, and keep external links.
    func decorate(_ src: URL, to dst: URL) throws {
        guard let doc = CGPDFDocument(src as CFURL), doc.numberOfPages > 0 else { throw CocoaError(.fileReadCorruptFile) }
        var box = doc.page(at: 1)!.getBoxRect(.mediaBox)
        let meta: [CFString: Any] = [kCGPDFContextTitle: title, kCGPDFContextCreator: "Onyx", kCGPDFContextAuthor: NSFullUserName()]
        guard let ctx = CGContext(dst as CFURL, mediaBox: &box, meta as CFDictionary) else { throw CocoaError(.fileWriteUnknown) }
        let et = face == "et"
        // The head: the title in letterspaced small caps. LM Roman Caps sets lowercase as small
        // caps; ET Book has real c2sc/smcp. The folio: old-style figures.
        let head = et ? font("ETBookOT-Roman", size: 9, features: ["c2sc", "smcp", "kern"]) : font("LMRomanCaps10-Regular", size: 9, features: ["kern"])
        let folioFont = et ? font("ETBookOT-Roman", size: 10, features: ["onum", "kern"]) : font("LMRoman10-Regular", size: 10, features: ["onum", "kern"])
        let headText = et ? title : title.lowercased()
        for i in 1...doc.numberOfPages {
            guard let pg = doc.page(at: i) else { continue }
            var mb = pg.getBoxRect(.mediaBox)
            ctx.beginPDFPage([kCGPDFContextMediaBox: Data(bytes: &mb, count: MemoryLayout<CGRect>.size)] as CFDictionary)
            ctx.drawPDFPage(pg)
            // Centered over the text block, not the whole page (the margin column is for notes).
            let x0 = mb.minX + page.left, w = page.textWidth
            if i > 1 {
                let l = line(headText, head, kern: 0.9)
                let lw = CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil))
                ctx.textPosition = CGPoint(x: x0 + (w - min(lw, w)) / 2, y: mb.maxY - page.top + 26)
                CTLineDraw(l, ctx)
            }
            let f = line(String(i), folioFont)
            let fw = CGFloat(CTLineGetTypographicBounds(f, nil, nil, nil))
            ctx.textPosition = CGPoint(x: x0 + (w - fw) / 2, y: mb.minY + page.bottom - 36)
            CTLineDraw(f, ctx)
            copyLinks(pg, into: ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }

    /// WebKit writes external links as /Link annotations with a /URI action; redraw them.
    private func copyLinks(_ pg: CGPDFPage, into ctx: CGContext) {
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
