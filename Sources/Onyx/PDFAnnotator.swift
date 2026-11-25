import AppKit
import PDFKit
import OnyxCore

/// Adds GoTo link annotations and a document outline (bookmarks) to a finished PDF.
enum PDFAnnotator {
    static func geometry(_ page: NotePrinter.Page) -> PDFLinkMap.Geometry {
        PDFLinkMap.Geometry(paperWidth: page.paper.width, paperHeight: page.paper.height,
                            top: page.top, bottom: page.bottom, left: page.left, right: page.right)
    }

    static func apply(to url: URL, jumps: [PDFLinkMap.Jump], outline: [PDFLinkMap.OutlineNode]) throws {
        guard !jumps.isEmpty || !outline.isEmpty else { return }
        guard let doc = PDFDocument(url: url) else { throw CocoaError(.fileReadCorruptFile) }
        for j in jumps {
            guard let src = doc.page(at: j.page - 1), let dst = doc.page(at: j.destPage - 1) else { continue }
            let a = PDFAnnotation(bounds: j.rect, forType: .link, withProperties: nil)
            a.action = PDFActionGoTo(destination: PDFDestination(page: dst, at: CGPoint(x: 0, y: j.destY)))
            let border = PDFBorder()
            border.lineWidth = 0
            a.border = border
            a.color = .clear
            src.addAnnotation(a)
        }
        if !outline.isEmpty {
            let root = PDFOutline()
            add(outline, to: root, in: doc)
            doc.outlineRoot = root
        }
        guard doc.write(to: url) else { throw CocoaError(.fileWriteUnknown) }
    }

    private static func add(_ nodes: [PDFLinkMap.OutlineNode], to parent: PDFOutline, in doc: PDFDocument) {
        for (i, n) in nodes.enumerated() {
            let child = PDFOutline()
            child.label = n.title
            if n.page >= 1, n.page <= doc.pageCount, let p = doc.page(at: n.page - 1) {
                let y = n.y ?? p.bounds(for: .mediaBox).maxY
                child.destination = PDFDestination(page: p, at: CGPoint(x: 0, y: y))
            }
            parent.insertChild(child, at: i)
            add(n.children, to: child, in: doc)
        }
    }
}
