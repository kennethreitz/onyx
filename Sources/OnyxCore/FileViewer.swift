import Foundation

/// What the in-pane file viewer shows for an attachment (anything in the vault that isn't a note,
/// canvas or base): images, audio, video and PDFs get a real viewer; everything else a file card.
public enum AttachmentKind: String, Sendable, CaseIterable {
    case image, audio, video, pdf, other

    public static let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg", "avif", "heic", "heif", "bmp", "tif", "tiff", "ico"]
    public static let audioExts: Set<String> = ["mp3", "m4a", "m4b", "aac", "wav", "aif", "aiff", "caf", "flac", "ogg", "oga", "opus", "3gp"]
    public static let videoExts: Set<String> = ["mp4", "m4v", "mov", "webm", "mkv", "ogv", "avi"]

    public static func of(_ path: String) -> AttachmentKind {
        let ext = (path as NSString).pathExtension.lowercased()
        if imageExts.contains(ext) { return .image }
        if audioExts.contains(ext) { return .audio }
        if videoExts.contains(ext) { return .video }
        if ext == "pdf" { return .pdf }
        return .other
    }

    /// Formats AVFoundation plays on macOS. Ogg/Opus, WebM, MKV and AVI usually don't; the viewer
    /// still tries (the asset's own `isPlayable` has the last word) and falls back to a file card.
    public static let nativeMediaExts: Set<String> = ["mp3", "m4a", "m4b", "aac", "wav", "aif", "aiff", "caf", "flac", "3gp", "mp4", "m4v", "mov"]
    public static func likelyPlayable(_ path: String) -> Bool {
        nativeMediaExts.contains((path as NSString).pathExtension.lowercased())
    }

    public var label: String {
        switch self {
        case .image: "Image"
        case .audio: "Audio"
        case .video: "Video"
        case .pdf: "PDF"
        case .other: "File"
        }
    }
    public var symbol: String {
        switch self {
        case .image: "photo"
        case .audio: "waveform"
        case .video: "film"
        case .pdf: "doc.richtext"
        case .other: "doc"
        }
    }
}

public extension String {
    /// A vault path that opens in Onyx's file viewer rather than the editor, a canvas or a base.
    var opensInFileView: Bool {
        let l = lowercased()
        return !l.hasSuffix(".md") && !l.hasSuffix(".canvas") && !l.hasSuffix(".base") && !isEmpty
    }
}

/// Pure pieces of the audio player: time labels, skipping, speeds, the waveform, the transcript.
public enum AudioPlayback {
    public static let speeds: [Double] = [0.75, 1, 1.25, 1.5, 1.75, 2]
    public static let skipSeconds: Double = 15

    /// The next speed in the cycle (wrapping), from whatever the current speed is nearest.
    public static func nextSpeed(after s: Double) -> Double {
        let i = speeds.firstIndex { abs($0 - s) < 0.01 } ?? speeds.firstIndex(of: 1)!
        return speeds[(i + 1) % speeds.count]
    }
    /// "1×", "1.25×", "0.75×".
    public static func speedLabel(_ s: Double) -> String {
        var t = String(format: "%.2f", s)
        while t.hasSuffix("0") { t.removeLast() }
        if t.hasSuffix(".") { t.removeLast() }
        return t + "×"
    }

    /// A new position `by` seconds from `time`, kept inside 0…duration (duration ≤ 0 = unknown).
    public static func skip(_ time: Double, by: Double, duration: Double) -> Double {
        let t = time + by
        if duration > 0 { return min(max(0, t), duration) }
        return max(0, t)
    }

    /// Elapsed ("1:05") and remaining ("-2:10") labels.
    public static func labels(time: Double, duration: Double) -> (elapsed: String, remaining: String) {
        let t = time.isFinite ? max(0, time) : 0
        guard duration.isFinite, duration > 0 else { return (AudioNote.elapsed(t), "--:--") }
        let left = max(0, duration.rounded(.down) - t.rounded(.down))
        return (AudioNote.elapsed(min(t, duration)), "-" + AudioNote.elapsed(left))
    }

    /// Peak amplitude per bin, normalized so the loudest bin is 1. Fewer samples than bins
    /// gives one bin per sample.
    public static func waveform(_ samples: [Float], bins: Int) -> [Float] {
        guard bins > 0, !samples.isEmpty else { return [] }
        let n = min(bins, samples.count)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let a = i * samples.count / n, b = max(a + 1, (i + 1) * samples.count / n)
            var peak: Float = 0
            for j in a..<b { peak = max(peak, abs(samples[j])) }
            out[i] = peak
        }
        let top = out.max() ?? 0
        return top > 0 ? out.map { $0 / top } : out
    }

    /// The transcript Record Audio left under an embed of `fileName` (a `> [!transcript]` callout
    /// on the lines after `![[…fileName…]]`), as plain text. nil when the note has none.
    public static func transcript(forEmbedOf fileName: String, in text: String) -> String? {
        let name = fileName.lowercased()
        let lines = text.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let l = lines[i].lowercased()
            if embeds(l, name) {
                var j = i + 1
                while j < lines.count, lines[j].trimmingCharacters(in: .whitespaces).isEmpty { j += 1 }
                if j < lines.count, lines[j].trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("> [!transcript]") {
                    var body: [String] = []
                    j += 1
                    while j < lines.count {
                        let t = lines[j].trimmingCharacters(in: .whitespaces)
                        guard t.hasPrefix(">") else { break }
                        var s = String(t.dropFirst())
                        if s.hasPrefix(" ") { s.removeFirst() }
                        body.append(s)
                        j += 1
                    }
                    let joined = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    if joined == "*(no speech recognized)*" { return "" }
                    return joined
                }
            }
            i += 1
        }
        return nil
    }

    private static func embeds(_ line: String, _ name: String) -> Bool {
        var rest = Substring(line)
        while let r = rest.range(of: "![[") {
            let after = rest[r.upperBound...]
            guard let close = after.range(of: "]]") else { return false }
            var target = String(after[..<close.lowerBound])
            if let bar = target.firstIndex(of: "|") { target = String(target[..<bar]) }
            target = target.trimmingCharacters(in: .whitespaces)
            if target == name || target.hasSuffix("/" + name) { return true }
            rest = after[close.upperBound...]
        }
        return false
    }
}

/// The local target of a Markdown link `[text](target)` under a character offset, for ⌘-click
/// in the editor (URLs are left to the URL detector). Percent-decoded, `./` and `#heading` removed.
public enum MarkdownLinkHit {
    public static func target(in line: String, at offset: Int) -> String? {
        let ns = line as NSString
        guard let re = try? NSRegularExpression(pattern: #"!?\[[^\]\n]*\]\(([^)\n]+)\)"#) else { return nil }
        for m in re.matches(in: line, range: NSRange(location: 0, length: ns.length))
        where NSLocationInRange(offset, m.range) || NSMaxRange(m.range) == offset {
            var t = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            if let sp = t.range(of: " \"") { t = String(t[..<sp.lowerBound]) }   // [x](y "title")
            if t.hasPrefix("<"), t.hasSuffix(">") { t = String(t.dropFirst().dropLast()) }
            if t.range(of: #"^[a-zA-Z][a-zA-Z0-9+.-]*:"#, options: .regularExpression) != nil { return nil }
            if let h = t.firstIndex(of: "#") { t = String(t[..<h]) }
            if t.hasPrefix("./") { t.removeFirst(2) }
            t = t.removingPercentEncoding ?? t
            return t.isEmpty ? nil : t
        }
        return nil
    }
}
