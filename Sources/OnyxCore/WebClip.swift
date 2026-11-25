import Foundation

/// The pure half of Onyx's web clipper: reading `onyx://clip` requests (from the bookmarklet),
/// naming the clipping, filling the note template, and matching the vault's clipping conventions.
/// Fetching, Readability extraction, and image downloads live in the app (WebClipper.swift).
public enum WebClip {
    // MARK: Requests

    /// What the bookmarklet (or another app) sends: `onyx://clip?url=…&title=…&selection=…`.
    public struct Request: Equatable, Sendable {
        public var url: String?
        public var title: String?
        /// Selected HTML (XHTML from the bookmarklet). When present, only the selection is clipped.
        public var selection: String?
        /// Plain-text content, for callers that have no HTML (Shortcuts, scripts).
        public var text: String?
        public var author: String?
        public var description: String?
        public var published: String?
        public var site: String?
        /// Optional vault folder overriding the Clippings folder setting.
        public var folder: String?

        public init(url: String? = nil, title: String? = nil, selection: String? = nil, text: String? = nil,
                    author: String? = nil, description: String? = nil, published: String? = nil,
                    site: String? = nil, folder: String? = nil) {
            self.url = url; self.title = title; self.selection = selection; self.text = text
            self.author = author; self.description = description; self.published = published
            self.site = site; self.folder = folder
        }

        /// Whether Onyx has to fetch the page itself (nothing but a URL came along).
        public var needsFetch: Bool {
            (selection ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && webURL != nil
        }

        /// The page URL when it is http(s).
        public var webURL: URL? {
            guard let s = url?.trimmingCharacters(in: .whitespacesAndNewlines), let u = URL(string: s),
                  let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https", u.host != nil else { return nil }
            return u
        }
    }

    /// Parse `onyx://clip?…` (also `onyx:///clip?…` and `onyx://x-callback-url/clip?…`). Nil for any other onyx URL.
    public static func request(from url: URL) -> Request? {
        guard url.scheme?.lowercased() == "onyx",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let host = (comps.host ?? "").lowercased()
        let path = comps.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard host == "clip" || (host.isEmpty && path == "clip") || (host == "x-callback-url" && path == "clip") else { return nil }
        var r = Request()
        for item in comps.queryItems ?? [] {
            let v = item.value.flatMap { $0.isEmpty ? nil : $0 }
            switch item.name.lowercased() {
            case "url", "source", "href": r.url = v
            case "title", "name": r.title = v
            case "selection", "html": r.selection = v
            case "text", "content", "markdown": r.text = v
            case "author", "byline": r.author = v
            case "description", "excerpt": r.description = v
            case "published", "date": r.published = v
            case "site", "sitename": r.site = v
            case "folder", "path": r.folder = v
            default: break
            }
        }
        guard r.url != nil || r.selection != nil || r.text != nil else { return nil }
        return r
    }

    // MARK: Pages

    /// An extracted page: Readability's result merged with the request's metadata.
    public struct Page: Equatable, Sendable {
        public var url: String
        public var title: String
        public var authors: [String]
        public var published: String?
        public var description: String?
        public var site: String?
        /// Article HTML (XHTML), converted with HTMLToMarkdown.
        public var html: String

        public init(url: String, title: String, authors: [String] = [], published: String? = nil,
                    description: String? = nil, site: String? = nil, html: String) {
            self.url = url; self.title = title; self.authors = authors; self.published = published
            self.description = description; self.site = site; self.html = html
        }
    }

    /// "By Jane Doe and John Roe" / "Jane Doe, John Roe" → ["Jane Doe", "John Roe"].
    public static func authors(_ byline: String?) -> [String] {
        guard var s = byline?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return [] }
        s = s.replacingOccurrences(of: #"^(?i)(written\s+)?by[:\s]+"#, with: "", options: .regularExpression)
        // Drop a trailing date or role ("Jane Doe | March 3, 2024", "Jane Doe — Staff Writer").
        if let cut = s.range(of: #"\s+[|·•—–]\s+"#, options: .regularExpression) { s = String(s[..<cut.lowerBound]) }
        let parts = s.components(separatedBy: CharacterSet(charactersIn: ",;&"))
            .flatMap { $0.components(separatedBy: " and ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 80 && !$0.contains("://") }
        var seen = Set<String>()
        return parts.filter { seen.insert($0.lowercased()).inserted }
    }

    /// The page's publication date as `YYYY-MM-DD`, or nil when it can't be read.
    public static func normalizedDate(_ raw: String?) -> String? {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if let r = s.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) { return String(s[r]) }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        for fmt in ["MMMM d, yyyy", "MMM d, yyyy", "d MMMM yyyy", "d MMM yyyy", "EEE, dd MMM yyyy HH:mm:ss Z", "yyyy/MM/dd", "MM/dd/yyyy"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) {
                f.dateFormat = "yyyy-MM-dd"
                return f.string(from: d)
            }
        }
        return nil
    }

    // MARK: Naming

    /// The clipping's file name: the title, made safe for a vault (Obsidian's rules), trimmed to a
    /// readable length; the site and date when there is no title.
    public static func fileName(title: String, url: String?, date: Date, timeZone: TimeZone = .current) -> String {
        var t = title.replacingOccurrences(of: ":", with: " -")
        t = Attachments.sanitize(t)
        if t == "Untitled" || t.isEmpty {
            let host = url.flatMap { URL(string: $0)?.host }?.replacingOccurrences(of: "www.", with: "") ?? "Clipping"
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = timeZone; f.dateFormat = "yyyy-MM-dd HHmm"
            t = Attachments.sanitize("\(host) \(f.string(from: date))")
        }
        if t.count > 120 {
            let cut = t.prefix(120)
            t = cut.range(of: " ", options: .backwards).map { String(cut[..<$0.lowerBound]) } ?? String(cut)
        }
        while t.hasSuffix(".") || t.hasSuffix(" ") { t.removeLast() }
        return (t.isEmpty ? "Clipping" : t) + ".md"
    }

    /// A name for a downloaded image: the URL's file name (made safe), with an extension from the
    /// MIME type when the URL has none.
    public static func imageName(url: String, mimeType: String?, index: Int) -> String {
        let u = URL(string: url)
        var base = (u?.lastPathComponent.removingPercentEncoding ?? u?.lastPathComponent ?? "")
        if base == "/" { base = "" }
        var ext = (base as NSString).pathExtension.lowercased()
        var stem = (base as NSString).deletingPathExtension
        let fromMime: String? = {
            switch mimeType?.lowercased().split(separator: ";").first.map({ $0.trimmingCharacters(in: .whitespaces) }) {
            case "image/jpeg", "image/jpg", "image/pjpeg": return "jpg"
            case "image/png": return "png"
            case "image/gif": return "gif"
            case "image/webp": return "webp"
            case "image/svg+xml": return "svg"
            case "image/avif": return "avif"
            case "image/heic": return "heic"
            case "image/bmp": return "bmp"
            case "image/tiff": return "tiff"
            default: return nil
            }
        }()
        if !Attachments.imageExts.contains(ext) {
            if !ext.isEmpty { stem = base }
            ext = fromMime ?? "png"
        }
        stem = Attachments.sanitize(stem)
        if stem == "Untitled" || stem.count < 2 { stem = "Clipped image \(index + 1)" }
        if stem.count > 80 { stem = String(stem.prefix(80)).trimmingCharacters(in: .whitespaces) }
        return stem + "." + ext
    }

    // MARK: Conventions

    /// Clipper preferences (stored by the app in UserDefaults).
    public struct Settings: Equatable, Sendable {
        public static let folderKey = "onyx.clip.folder"
        public static let classKey = "onyx.clip.class"
        public static let tagsKey = "onyx.clip.tags"
        public static let imagesKey = "onyx.clip.downloadImages"
        public static let templateKey = "onyx.clip.template"
        public static let defaultFolder = "Clippings"
        public static let defaultClass = "Source"
        public static let defaultTags = ["clippings"]

        /// Vault folder for new clippings.
        public var folder: String
        /// `class:` for new clippings; empty = match the folder's existing clippings (else "Source").
        public var noteClass: String
        /// `tags:`; empty = match the folder's existing clippings (else `clippings`).
        public var tags: String
        public var downloadImages: Bool
        /// A vault note used as the template; empty = the built-in one.
        public var templatePath: String

        public init(folder: String = Settings.defaultFolder, noteClass: String = "", tags: String = "",
                    downloadImages: Bool = true, templatePath: String = "") {
            self.folder = folder; self.noteClass = noteClass; self.tags = tags
            self.downloadImages = downloadImages; self.templatePath = templatePath
        }

        public init(defaults d: UserDefaults) {
            let f = (d.string(forKey: Self.folderKey) ?? Self.defaultFolder).trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            self.init(folder: f,
                      noteClass: d.string(forKey: Self.classKey) ?? "",
                      tags: d.string(forKey: Self.tagsKey) ?? "",
                      downloadImages: d.object(forKey: Self.imagesKey) as? Bool ?? true,
                      templatePath: d.string(forKey: Self.templateKey) ?? "")
        }
    }

    /// The `class:` and `tags:` most clippings in the folder already use (folder indexes ignored).
    public static func conventions(frontmatters: [Frontmatter]) -> (noteClass: String?, tags: [String]?) {
        var classes: [String: Int] = [:], tagSets: [[String]: Int] = [:]
        for fm in frontmatters {
            let cls = fm["class"]?.display.trimmingCharacters(in: .whitespaces) ?? ""
            if cls.lowercased() == "index" || fm["type"]?.display.lowercased() == "index" { continue }
            if !cls.isEmpty { classes[cls, default: 0] += 1 }
            if let t = fm["tags"]?.strings.map({ $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) }).filter({ !$0.isEmpty }), !t.isEmpty {
                tagSets[t, default: 0] += 1
            }
        }
        let cls = classes.max { a, b in a.value == b.value ? a.key > b.key : a.value < b.value }?.key
        let tags = tagSets.max { a, b in a.value == b.value ? a.key.joined() > b.key.joined() : a.value < b.value }?.key
        return (cls, tags)
    }

    public static func tagList(_ raw: String) -> [String] {
        raw.components(separatedBy: CharacterSet(charactersIn: ", "))
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) }
            .filter { !$0.isEmpty }
    }

    // MARK: Rendering

    /// A YAML double-quoted scalar.
    public static func yaml(_ s: String) -> String {
        let one = s.replacingOccurrences(of: #"\s*\n\s*"#, with: " ", options: .regularExpression)
        return "\"" + one.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func tagYAML(_ tags: [String]) -> String {
        "[" + tags.map { t in t.range(of: #"^[\p{L}\p{N}_/\-]+$"#, options: .regularExpression) != nil ? t : yaml(t) }.joined(separator: ", ") + "]"
    }

    /// The clipping note. With no template: Obsidian Web Clipper-style frontmatter
    /// (title, source, author, published, created, description, tags, class), a `# Title`, and the
    /// article. A template note may use {{title}}, {{url}}, {{author}}, {{published}}, {{date}},
    /// {{time}}, {{description}}, {{site}}, {{tags}}, {{class}} and {{content}} (appended when absent).
    public static func note(page: Page, markdown: String, noteClass: String, tags: [String],
                            template: String? = nil, clipped: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd"; let day = f.string(from: clipped)
        f.dateFormat = "HH:mm"; let time = f.string(from: clipped)
        let published = normalizedDate(page.published)
        let body = stripLeadingTitle(markdown, title: page.title)

        if let template, !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let vars: [String: String] = [
                "title": page.title, "url": page.url, "source": page.url,
                "author": page.authors.joined(separator: ", "), "published": published ?? "",
                "date": day, "created": day, "time": time, "description": page.description ?? "",
                "site": page.site ?? "", "tags": tags.joined(separator: ", "), "class": noteClass, "content": body,
            ]
            var out = template
            let hadContent = template.contains("{{content}}")
            for (k, v) in vars where k != "content" { out = out.replacingOccurrences(of: "{{\(k)}}", with: v) }
            out = out.replacingOccurrences(of: "{{content}}", with: body)
            if !hadContent { out = out.trimmingCharacters(in: .newlines) + "\n\n" + body }
            return out.trimmingCharacters(in: .newlines) + "\n"
        }

        var lines = ["---", "title: \(yaml(page.title))", "source: \(yaml(page.url))"]
        lines.append(page.authors.isEmpty ? "author:" : "author: [" + page.authors.map(yaml).joined(separator: ", ") + "]")
        lines.append("published:" + (published.map { " " + $0 } ?? ""))
        lines.append("created: \(day)")
        if let d = page.description?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty { lines.append("description: \(yaml(d))") }
        else { lines.append("description:") }
        if let s = page.site?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { lines.append("site: \(yaml(s))") }
        if !tags.isEmpty { lines.append("tags: \(tagYAML(tags))") }
        if !noteClass.isEmpty { lines.append("class: \(noteClass)") }
        lines.append("---")
        lines.append("")
        lines.append("# \(page.title)")
        lines.append("")
        if !body.isEmpty { lines.append(body) }
        return lines.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
    }

    /// Drop the article's own `# Title` when it repeats the clipping's title.
    public static func stripLeadingTitle(_ md: String, title: String) -> String {
        let trimmed = md.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first,
              first.hasPrefix("#") else { return trimmed }
        let heading = first.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\\", with: "")
        func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        guard norm(heading) == norm(title), !norm(title).isEmpty else { return trimmed }
        return String(trimmed.dropFirst(first.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Bookmarklet

    /// A bookmarklet that sends the current page (and any selection) to Onyx.
    public static let bookmarklet: String = {
        let js = """
        (()=>{const m=(...n)=>{for(const k of n){const e=document.querySelector(`meta[name="${k}"],meta[property="${k}"],meta[itemprop="${k}"]`);if(e&&e.content)return e.content.trim()}return''};\
        const p=new URLSearchParams();p.set('url',location.href);p.set('title',m('og:title')||document.title);\
        const a=m('author','article:author','parsely-author','sailthru.author');if(a&&!/^https?:/.test(a))p.set('author',a);\
        const d=m('description','og:description');if(d)p.set('description',d);\
        const t=m('article:published_time','datePublished','date','parsely-pub-date');if(t)p.set('published',t);\
        const s=m('og:site_name');if(s)p.set('site',s);\
        const g=getSelection();if(g&&g.rangeCount&&!g.isCollapsed){const w=document.createElement('div');for(let i=0;i<g.rangeCount;i++)w.appendChild(g.getRangeAt(i).cloneContents());\
        w.querySelectorAll('img').forEach(i=>{if(i.currentSrc)i.setAttribute('src',i.currentSrc)});w.querySelectorAll('[src],[href]').forEach(e=>{['src','href'].forEach(k=>{if(e.hasAttribute(k))try{e.setAttribute(k,new URL(e.getAttribute(k),location.href).href)}catch(_){}})});\
        p.set('selection',new XMLSerializer().serializeToString(w))}\
        location.href='onyx://clip?'+p.toString().replace(/\\+/g,'%20')})()
        """
        // javascript: URLs are percent-decoded before they run, so encode everything but the plain characters.
        var safe = CharacterSet.alphanumerics
        safe.insert(charactersIn: "-_.!~*'()=,;:/?&@$")
        return "javascript:" + (js.addingPercentEncoding(withAllowedCharacters: safe) ?? js)
    }()

    /// The bookmarklet's readable source (what `bookmarklet` encodes).
    public static var bookmarkletSource: String { bookmarklet.dropFirst("javascript:".count).removingPercentEncoding ?? "" }
}
