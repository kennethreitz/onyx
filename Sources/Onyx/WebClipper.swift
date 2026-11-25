import AppKit
import WebKit
import OnyxCore

/// Web clipper: File ▸ Clip Web Page… (a URL), the `onyx://clip` URL scheme (the bookmarklet,
/// Shortcuts, scripts). A bare URL is loaded in an offscreen, cookie-less web view and reduced to
/// its article with Mozilla's Readability.js; a selection sent by the bookmarklet is used as is.
/// Either way the HTML becomes Markdown (HTMLToMarkdown) with images hotlinked to the web
/// (nothing is downloaded), and the note lands in the Clippings folder. See docs/web-clipper.md.
@MainActor final class WebClipper {
    static let shared = WebClipper()
    weak var ws: Workspace?
    private var queue: [WebClip.Request] = []
    private var busy = false
    private var waits = 0

    /// Test hook: ONYX_CLIP_TEST=<https or onyx://clip URL> clips it once the vault is open and
    /// prints `[cliptest] …`; ONYX_CLIP_TEST_QUIT=1 quits afterwards. Never set in normal use.
    static func scheduleSelfTestIfRequested() {
        guard let s = ProcessInfo.processInfo.environment["ONYX_CLIP_TEST"], let url = URL(string: s) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if url.scheme == "onyx" { shared.receive(url) } else { shared.enqueue(WebClip.Request(url: s)) }
        }
    }

    static func selfTestReport(_ message: String) {
        let env = ProcessInfo.processInfo.environment
        guard env["ONYX_CLIP_TEST"] != nil else { return }
        print("[cliptest] \(message)")
        fflush(stdout)
        if env["ONYX_CLIP_TEST_QUIT"] == "1" { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) } }
    }

    /// An `onyx://` URL from the system (bookmarklet, `open`, Shortcuts). Unknown actions are ignored.
    func receive(_ url: URL) {
        guard let req = WebClip.request(from: url) else { return }
        enqueue(req)
    }

    func enqueue(_ r: WebClip.Request) {
        queue.append(r)
        pump()
    }

    private func pump() {
        guard !busy, !queue.isEmpty else { return }
        // Launched by the URL: wait for the vault to open (about 30 s at most).
        guard let ws, ws.root != nil else {
            waits += 1
            guard waits < 60 else { queue.removeAll(); waits = 0; return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.pump() }
            return
        }
        waits = 0
        busy = true
        let r = queue.removeFirst()
        Task { @MainActor in
            await self.clip(r, ws: ws)
            self.busy = false
            self.pump()
        }
    }

    private func clip(_ r: WebClip.Request, ws: Workspace) async {
        let host = r.webURL?.host?.replacingOccurrences(of: "www.", with: "") ?? "the page"
        var page: WebClip.Page
        var text: String? = nil
        if r.needsFetch, let url = r.webURL {
            ws.toast = "Clipping \(host)…"
            do {
                page = try await PageExtractor().extract(url)
            } catch {
                ws.toast = "Couldn’t clip \(host): \(error.localizedDescription)"
                WebClipper.selfTestReport("failed: \(error.localizedDescription)")
                return
            }
            // The bookmarklet's metadata fills what the fetched copy lacks.
            if page.title.isEmpty, let t = r.title { page.title = t }
            if page.authors.isEmpty { page.authors = WebClip.authors(r.author) }
            if page.published == nil { page.published = r.published }
            if page.description == nil { page.description = r.description }
            if page.site == nil { page.site = r.site }
        } else {
            page = WebClip.Page(url: r.url ?? "", title: r.title ?? "", authors: WebClip.authors(r.author),
                                published: r.published, description: r.description, site: r.site, html: r.selection ?? "")
            if (r.selection ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { text = r.text }
        }
        if page.title.trimmingCharacters(in: .whitespaces).isEmpty { page.title = r.webURL?.host ?? "Clipping" }
        await ws.saveClip(page, markdown: text, folder: r.folder)
    }

}

// MARK: - Fetching and extraction

/// Loads a page offscreen (no cookies, no storage kept) and runs Readability.js plus
/// Resources/web/clipper/extract.js on it.
@MainActor final class PageExtractor: NSObject, WKNavigationDelegate {
    nonisolated static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private var web: WKWebView?
    private var loaded: CheckedContinuation<Void, Error>?

    func extract(_ url: URL) async throws -> WebClip.Page {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()
        cfg.mediaTypesRequiringUserActionForPlayback = .all
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 1600), configuration: cfg)
        wv.customUserAgent = Self.userAgent
        wv.navigationDelegate = self
        web = wv
        defer { wv.stopLoading(); wv.navigationDelegate = nil; web = nil }

        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            loaded = c
            wv.load(URLRequest(url: url, timeoutInterval: 30))
            // Slow pages: after 25 s use whatever has rendered.
            DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in self?.finishLoad(nil) }
        }
        // Give client-side rendering a moment.
        try? await Task.sleep(nanoseconds: 1_200_000_000)

        let clipper = AppResources.web.appendingPathComponent("clipper")
        guard let readability = try? String(contentsOf: clipper.appendingPathComponent("Readability.js"), encoding: .utf8),
              let extractor = try? String(contentsOf: clipper.appendingPathComponent("extract.js"), encoding: .utf8) else {
            throw Failure(message: "the clipper scripts are missing")
        }
        let raw = try await wv.evaluateJavaScript(readability + "\n;\n" + extractor)
        guard let json = raw as? String, let data = json.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure(message: "couldn’t read the page")
        }
        func s(_ k: String) -> String? {
            (o[k] as? String).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        return WebClip.Page(url: s("url") ?? url.absoluteString, title: s("title") ?? "",
                            authors: WebClip.authors(s("byline")), published: s("published"),
                            description: s("description"), site: s("site"), html: s("html") ?? "")
    }

    private func finishLoad(_ error: Error?) {
        guard let c = loaded else { return }
        loaded = nil
        if let error { c.resume(throwing: error) } else { c.resume() }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated { finishLoad(nil) }
    }
    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { finishLoad(error) }
    }
    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { finishLoad(error) }
    }
    nonisolated func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                             decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        let mime = navigationResponse.response.mimeType?.lowercased() ?? "text/html"
        let isPage = mime.contains("html") || mime.hasPrefix("text/")
        MainActor.assumeIsolated {
            if navigationResponse.isForMainFrame, !isPage {
                decisionHandler(.cancel)
                finishLoad(Failure(message: "it isn’t a web page (\(mime))"))
            } else {
                decisionHandler(.allow)
            }
        }
    }
}

// MARK: - Workspace

extension Workspace {
    /// File ▸ Clip Web Page…: ask for a URL (prefilled from the clipboard) and clip it.
    func promptClip() {
        let a = NSAlert()
        let settings = WebClip.Settings(defaults: .standard)
        a.messageText = "Clip Web Page"
        a.informativeText = "Onyx saves a readable copy of the page (images stay linked to the web) to \(settings.folder.isEmpty ? "the vault root" : settings.folder + "/")."
        var prefill = ""
        if let s = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !s.contains("\n"), WebClip.Request(url: s).webURL != nil { prefill = s }
        let field = NSTextField(string: prefill)
        field.placeholderString = "https://…"
        field.frame = NSRect(x: 0, y: 0, width: 360, height: 24)
        a.accessoryView = field
        a.addButton(withTitle: "Clip"); a.addButton(withTitle: "Cancel")
        a.window.initialFirstResponder = field
        guard a.runModal() == .alertFirstButtonReturn else { return }
        var s = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.isEmpty, !s.contains("://") { s = "https://" + s }
        guard WebClip.Request(url: s).webURL != nil else { toast = "That isn’t a web address"; return }
        WebClipper.shared.ws = self
        WebClipper.shared.enqueue(WebClip.Request(url: s))
    }

    /// Existing notes' frontmatter in `folder` (newest 40), to match their class and tags.
    private func clippingFrontmatters(in folder: String) -> [Frontmatter] {
        guard let root else { return [] }
        let dir = folder.isEmpty ? root : root.appendingPathComponent(folder)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let notes = files.filter { $0.pathExtension.lowercased() == "md" }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            }
            .prefix(40)
        return notes.compactMap { try? String(contentsOf: $0, encoding: .utf8) }.map(Frontmatter.parse)
    }

    /// Write a clipping: convert to Markdown (images hotlinked), fill the template, save it in the Clippings folder, and open it.
    func saveClip(_ page: WebClip.Page, markdown text: String? = nil, folder override: String? = nil) async {
        guard let root else { return }
        let settings = WebClip.Settings(defaults: .standard)
        var folder = (override ?? settings.folder).trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if folder.split(separator: "/").contains("..") { folder = WebClip.Settings.defaultFolder }

        var noteClass = settings.noteClass.trimmingCharacters(in: .whitespaces)
        var tags = WebClip.tagList(settings.tags)
        if noteClass.isEmpty || tags.isEmpty {
            let conv = WebClip.conventions(frontmatters: clippingFrontmatters(in: folder))
            if noteClass.isEmpty { noteClass = conv.noteClass ?? WebClip.Settings.defaultClass }
            if tags.isEmpty { tags = conv.tags ?? WebClip.Settings.defaultTags }
        }

        let fm = FileManager.default
        let name = WebClip.fileName(title: page.title, url: page.url, date: Date())
        let path = AudioNote.uniquePath(folder: folder, name: name) { p in
            snapshot?.notes[p] != nil || fm.fileExists(atPath: root.appendingPathComponent(p).path)
        }

        let converter = HTMLToMarkdown(baseURL: URL(string: page.url))
        let markdown = text ?? converter.convert(page.html)

        var template: String? = nil
        let tp = settings.templatePath.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if !tp.isEmpty, !tp.contains("..") {
            let rel = tp.lowercased().hasSuffix(".md") ? tp : tp + ".md"
            template = try? String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8)
            if template == nil { toast = "Clip template “\(rel)” not found; using the built-in one" }
        }
        let note = WebClip.note(page: page, markdown: markdown, noteClass: noteClass, tags: tags, template: template, clipped: Date())
        guard write(note, to: path, create: true) else {
            toast = "Couldn’t save the clipping to \(path)"
            return
        }
        vaultMutated("Clip \(page.title)", paths: [path])
        openNote(path)
        MainWindow.reveal()
        NSApp.activate(ignoringOtherApps: true)
        WebClipper.selfTestReport("saved \(path)")
        toast = "Clipped “\(page.title)”"
    }
}
