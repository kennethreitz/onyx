import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Coordinate and outline helpers for clickable PDF links: mapping a laid-out
/// document rectangle (origin top-left) onto paginated PDF page space (origin
/// bottom-left), building a bookmark tree, and matching heading tokens.
///
/// The mapping is a uniform scale of `contentWidth` onto the printable width, then
/// a simple slice into pages of the printable height. WebKit may still push a
/// block to the next page (`page-break-inside: avoid`), so a heading can land
/// slightly early or late; table-of-contents rows drawn in Core Text do not
/// use this path and are exact.
public enum PDFLinkMap {

    public struct Geometry: Equatable, Sendable {
        public var paperWidth: CGFloat
        public var paperHeight: CGFloat
        public var top: CGFloat
        public var bottom: CGFloat
        public var left: CGFloat
        public var right: CGFloat

        public var printableWidth: CGFloat { paperWidth - left - right }
        public var printableHeight: CGFloat { paperHeight - top - bottom }

        public init(paperWidth: CGFloat, paperHeight: CGFloat, top: CGFloat, bottom: CGFloat,
                    left: CGFloat, right: CGFloat) {
            self.paperWidth = paperWidth; self.paperHeight = paperHeight
            self.top = top; self.bottom = bottom; self.left = left; self.right = right
        }
    }

    /// A rectangle in PDF user space (origin bottom-left) on a 1-based page.
    public struct PageRect: Equatable, Sendable {
        public var page: Int
        public var rect: CGRect
        public init(page: Int, rect: CGRect) { self.page = page; self.rect = rect }
    }

    public struct Jump: Equatable, Sendable {
        public var page: Int
        public var rect: CGRect
        public var destPage: Int
        public var destY: CGFloat
        public init(page: Int, rect: CGRect, destPage: Int, destY: CGFloat) {
            self.page = page; self.rect = rect; self.destPage = destPage; self.destY = destY
        }
    }

    public struct OutlineNode: Equatable, Sendable {
        public var title: String
        public var page: Int
        public var y: CGFloat?
        public var children: [OutlineNode]
        public init(title: String, page: Int, y: CGFloat? = nil, children: [OutlineNode] = []) {
            self.title = title; self.page = page; self.y = y; self.children = children
        }
    }

    public struct Box: Equatable, Sendable {
        public var x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat
        public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
        public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
            self.x = x; self.y = y; self.width = width; self.height = height
        }
    }

    public struct HeadingBox: Equatable, Sendable {
        public var text: String
        public var level: Int
        public var box: Box
        public init(text: String, level: Int, box: Box) {
            self.text = text; self.level = level; self.box = box
        }
    }

    public struct LinkBox: Equatable, Sendable {
        public var heading: String
        /// Empty when the link is in-note (`[[#Heading]]` or `#heading`).
        public var target: String
        public var box: Box
        public init(heading: String, target: String, box: Box) {
            self.heading = heading; self.target = target; self.box = box
        }
    }

    public struct AnchorSet: Equatable, Sendable {
        public var contentWidth: CGFloat
        public var headings: [HeadingBox]
        public var links: [LinkBox]
        public init(contentWidth: CGFloat, headings: [HeadingBox] = [], links: [LinkBox] = []) {
            self.contentWidth = contentWidth; self.headings = headings; self.links = links
        }

        /// Parse the object returned by `Onyx.printAnchors()`.
        public init?(json: Any?) {
            guard let d = json as? [String: Any], let w = PDFLinkMap.number(d["contentWidth"]), w > 0 else { return nil }
            contentWidth = w
            headings = (d["headings"] as? [Any] ?? []).compactMap { raw in
                guard let h = raw as? [String: Any], let text = h["text"] as? String else { return nil }
                guard let box = PDFLinkMap.box(h) else { return nil }
                let level = Int(PDFLinkMap.number(h["level"]) ?? 1)
                return HeadingBox(text: text, level: level, box: box)
            }
            links = (d["links"] as? [Any] ?? []).compactMap { raw in
                guard let l = raw as? [String: Any], let heading = l["heading"] as? String, !heading.isEmpty else { return nil }
                guard let box = PDFLinkMap.box(l) else { return nil }
                return LinkBox(heading: heading, target: (l["target"] as? String) ?? "", box: box)
            }
        }
    }

    /// Clickable area for a TOC row whose title is drawn on baseline `y` (PDF space)
    /// from `x` across `width`. `ascent` / `descent` pad the baseline into a box.
    public static func tocRowRect(x: CGFloat, y: CGFloat, width: CGFloat,
                                  ascent: CGFloat = 11, descent: CGFloat = 4) -> CGRect {
        CGRect(x: x, y: y - descent, width: max(0, width), height: ascent + descent)
    }

    /// Map a document rectangle (origin top-left, y downward, same units as
    /// `contentWidth`) onto one or more PDF pages. A rectangle that crosses a
    /// page break is split. Pages are 1-based. Results past `pageCount` are dropped.
    public static func mapRect(_ rect: CGRect, contentWidth: CGFloat, geometry: Geometry,
                               pageCount: Int? = nil) -> [PageRect] {
        guard contentWidth > 0, geometry.printableWidth > 0, geometry.printableHeight > 0,
              rect.width > 0, rect.height > 0 else { return [] }
        let scale = geometry.printableWidth / contentWidth
        let top = rect.origin.y * scale
        let bottom = (rect.origin.y + rect.height) * scale
        let x = geometry.left + rect.origin.x * scale
        let w = rect.width * scale
        let pageH = geometry.printableHeight
        var page = max(1, Int(floor(top / pageH)) + 1)
        let lastPage = max(page, Int(floor((max(bottom - 0.01, top)) / pageH)) + 1)
        var out: [PageRect] = []
        while page <= lastPage {
            if let pageCount, page > pageCount { break }
            let pageTop = CGFloat(page - 1) * pageH
            let sliceTop = max(top, pageTop)
            let sliceBottom = min(bottom, pageTop + pageH)
            if sliceBottom > sliceTop {
                let yFromTop = sliceTop - pageTop
                let h = sliceBottom - sliceTop
                let pdfY = geometry.paperHeight - geometry.top - yFromTop - h
                out.append(PageRect(page: page, rect: CGRect(x: x, y: pdfY, width: w, height: h)))
            }
            page += 1
        }
        return out
    }

    /// Map a document point (top-left origin) to a PDF destination (1-based page,
    /// y from the bottom of the paper).
    public static func mapPoint(x: CGFloat, y: CGFloat, contentWidth: CGFloat,
                                geometry: Geometry, pageCount: Int? = nil) -> (page: Int, point: CGPoint)? {
        guard contentWidth > 0, geometry.printableWidth > 0, geometry.printableHeight > 0 else { return nil }
        let scale = geometry.printableWidth / contentWidth
        let yFromContentTop = y * scale
        let pageH = geometry.printableHeight
        let page = max(1, Int(floor(yFromContentTop / pageH)) + 1)
        if let pageCount, page > pageCount { return nil }
        let yOnPage = yFromContentTop - CGFloat(page - 1) * pageH
        let pdfY = geometry.paperHeight - geometry.top - yOnPage
        let pdfX = geometry.left + x * scale
        return (page, CGPoint(x: pdfX, y: pdfY))
    }

    /// Nest a depth-annotated list into an outline tree. The first item's depth
    /// is treated as the top level, so a list that starts at heading level 2
    /// still becomes a root.
    public static func nestOutline(_ items: [(title: String, page: Int, depth: Int, y: CGFloat?)]) -> [OutlineNode] {
        var rest = items
        func take(minDepth: Int) -> [OutlineNode] {
            var out: [OutlineNode] = []
            while let first = rest.first {
                if first.depth < minDepth { break }
                rest.removeFirst()
                let children = take(minDepth: first.depth + 1)
                out.append(OutlineNode(title: first.title, page: first.page, y: first.y, children: children))
            }
            return out
        }
        return take(minDepth: items.first?.depth ?? 0)
    }

    /// Case-insensitive heading match, the same rule the reader uses to jump.
    /// A leading `#` or `^` on the token is ignored.
    public static func matchHeading(_ token: String, in headings: [HeadingBox]) -> Int? {
        let key = normalize(token)
        guard !key.isEmpty else { return nil }
        return headings.firstIndex { normalize($0.text) == key }
    }

    public static func normalize(_ token: String) -> String {
        var s = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.hasPrefix("^") { s.removeFirst() }
        return s.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Destinations for a note's headings, already shifted by `pageOffset`
    /// (the folio of the note's first page minus one).
    public static func destinations(in anchors: AnchorSet, geometry: Geometry,
                                    pageCount: Int, pageOffset: Int = 0) -> [String: (page: Int, y: CGFloat)] {
        var out: [String: (page: Int, y: CGFloat)] = [:]
        for h in anchors.headings {
            guard let p = mapPoint(x: h.box.x, y: h.box.y, contentWidth: anchors.contentWidth,
                                   geometry: geometry, pageCount: pageCount) else { continue }
            let key = normalize(h.text)
            if out[key] == nil { out[key] = (p.page + pageOffset, p.point.y) }
        }
        return out
    }

    /// Link rectangles in a note that resolve to a heading destination.
    /// `resolve(heading, target)` returns the final PDF page and y; `target` is
    /// empty for an in-note link.
    public static func jumps(in anchors: AnchorSet, geometry: Geometry, pageCount: Int,
                             pageOffset: Int = 0,
                             resolve: (String, String) -> (page: Int, y: CGFloat)?) -> [Jump] {
        var out: [Jump] = []
        for l in anchors.links {
            guard let dest = resolve(l.heading, l.target) else { continue }
            for pr in mapRect(l.box.cgRect, contentWidth: anchors.contentWidth,
                              geometry: geometry, pageCount: pageCount) {
                out.append(Jump(page: pr.page + pageOffset, rect: pr.rect,
                                destPage: dest.page, destY: dest.y))
            }
        }
        return out
    }

    /// An outline of a note's headings, already shifted by `pageOffset`.
    public static func headingOutline(in anchors: AnchorSet, geometry: Geometry,
                                      pageCount: Int, pageOffset: Int = 0) -> [OutlineNode] {
        var items: [(title: String, page: Int, depth: Int, y: CGFloat?)] = []
        for h in anchors.headings {
            guard let p = mapPoint(x: h.box.x, y: h.box.y, contentWidth: anchors.contentWidth,
                                   geometry: geometry, pageCount: pageCount) else { continue }
            items.append((h.text, p.page + pageOffset, h.level, p.point.y))
        }
        return nestOutline(items)
    }

    /// Attach `children[page]` under every node whose `page` is in the dictionary,
    /// walking existing children first.
    public static func graft(_ nodes: [OutlineNode], children: [Int: [OutlineNode]]) -> [OutlineNode] {
        nodes.map { n in
            var n = n
            n.children = graft(n.children, children: children) + (children[n.page] ?? [])
            return n
        }
    }

    // MARK: JSON

    static func number(_ any: Any?) -> CGFloat? {
        if let n = any as? NSNumber { return CGFloat(truncating: n) }
        if let d = any as? Double { return CGFloat(d) }
        if let i = any as? Int { return CGFloat(i) }
        if let s = any as? String, let d = Double(s) { return CGFloat(d) }
        return nil
    }

    static func box(_ d: [String: Any]) -> Box? {
        guard let x = number(d["x"]), let y = number(d["y"]),
              let w = number(d["width"]), let h = number(d["height"]),
              w > 0, h > 0 else { return nil }
        return Box(x: x, y: y, width: w, height: h)
    }
}
