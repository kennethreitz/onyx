import AppKit
import OnyxCore

/// A compact, row-sized image for a ⌘-drag in the file tree: icon, name, and a
/// count badge when more than one item is moving. Drawn at the screen's scale
/// so the preview stays sharp on Retina, and under the app appearance so it
/// isn't a black slab in light or dark.
enum TreeDragPreview {
    static let rowHeight: CGFloat = 24
    static let maxWidth: CGFloat = 220

    static func displayName(path: String) -> String { InlineRename.fieldValue(path: path) }

    static func symbol(path: String, isFolder: Bool) -> String {
        if isFolder { return "folder" }
        if path.isCanvasPath { return "rectangle.on.rectangle" }
        if path.isBasePath { return "tablecells" }
        return "doc"
    }

    static func image(paths: [String], isFolder: (String) -> Bool,
                      appearance: NSAppearance = NSApp.effectiveAppearance,
                      scale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2) -> NSImage {
        let path = paths[0]
        return render(
            name: displayName(path: path),
            symbol: symbol(path: path, isFolder: isFolder(path)),
            isFolder: isFolder(path),
            count: paths.count,
            appearance: appearance,
            scale: max(scale, 1)
        )
    }

    static func render(name: String, symbol: String, isFolder: Bool, count: Int,
                       appearance: NSAppearance, scale: CGFloat) -> NSImage {
        let font = NSFont.systemFont(ofSize: 12.5, weight: isFolder ? .medium : .regular)
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingMiddle
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: Theme.ink,
            .paragraphStyle: para,
        ]
        let text = NSAttributedString(string: name, attributes: attrs)
        let iconSize: CGFloat = 13
        let padX: CGFloat = 7
        let gap: CGFloat = 5
        let badge = count > 1 ? "\(count)" : nil
        let badgeFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
        let badgeText = badge.map { NSAttributedString(string: $0, attributes: [
            .font: badgeFont, .foregroundColor: Theme.paper,
        ]) }
        let badgeW: CGFloat = badgeText.map { max(16, ceil($0.size().width) + 8) } ?? 0
        let badgeGap: CGFloat = badge == nil ? 0 : 6
        let textMax = max(24, maxWidth - padX - iconSize - gap - padX - badgeW - badgeGap)
        let textW = min(ceil(text.size().width), textMax)
        let width = padX + iconSize + gap + textW + (badge == nil ? padX : badgeGap + badgeW + padX)
        let stack: CGFloat = count > 1 ? 3 : 0
        let canvas = NSSize(width: width + stack, height: rowHeight + stack)

        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(ceil(canvas.width * scale)),
            pixelsHigh: Int(ceil(canvas.height * scale)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        rep.size = canvas

        let image = NSImage(size: canvas)
        image.addRepresentation(rep)
        image.isTemplate = false
        image.backgroundColor = .clear

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return image }
        ctx.imageInterpolation = .high
        NSGraphicsContext.current = ctx

        appearance.performAsCurrentDrawingAppearance {
            NSColor.clear.setFill()
            NSRect(origin: .zero, size: canvas).fill()

            let card = NSRect(x: 0, y: 0, width: width, height: rowHeight)
            if count > 1 {
                drawCard(card.offsetBy(dx: stack, dy: stack), alpha: 0.55)
            }
            drawCard(card, alpha: 0.92)

            let iconY = card.minY + (card.height - iconSize) / 2
            let iconRect = NSRect(x: card.minX + padX, y: iconY, width: iconSize, height: iconSize)
            if let base = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
                    .applying(NSImage.SymbolConfiguration(hierarchicalColor: Theme.ink.withAlphaComponent(isFolder ? 0.9 : 0.75)))
                let icon = base.withSymbolConfiguration(config) ?? base
                icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }

            let textH = text.size().height
            let textRect = NSRect(
                x: iconRect.maxX + gap,
                y: card.minY + (card.height - textH) / 2,
                width: textW,
                height: textH
            )
            text.draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])

            if let badgeText {
                let bw = badgeW, bh: CGFloat = 16
                let br = NSRect(x: card.maxX - padX - bw, y: card.minY + (card.height - bh) / 2, width: bw, height: bh)
                Theme.ink.withAlphaComponent(0.85).setFill()
                NSBezierPath(roundedRect: br, xRadius: bh / 2, yRadius: bh / 2).fill()
                let tw = badgeText.size()
                badgeText.draw(at: NSPoint(x: br.midX - tw.width / 2, y: br.midY - tw.height / 2))
            }
        }
        return image
    }

    private static func drawCard(_ rect: NSRect, alpha: CGFloat) {
        let bg = Theme.secondary.withAlphaComponent(alpha)
        bg.setFill()
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        path.fill()
        Theme.border.withAlphaComponent(0.9).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }
}
