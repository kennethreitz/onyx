import Foundation

/// Pure helpers for Record Audio: file naming, where the recording lands (Obsidian's
/// "Default location for new attachments"), and how the embed and transcript are spliced into a note.
public enum AudioNote {
    /// `Recording 2026-11-21 13-05-12.m4a` (Obsidian's own recorder uses this shape, minus the dashes in the time).
    public static func fileName(date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return "Recording \(f.string(from: date)).m4a"
    }

    /// The vault-relative folder for a new attachment, from Obsidian's `attachmentFolderPath`:
    /// missing, "" or "/" → vault root; "./" → the note's folder; "./sub" → a subfolder of the note's folder;
    /// anything else → that vault folder.
    public static func attachmentFolder(setting: String?, notePath: String?) -> String {
        let noteFolder = notePath.map { ($0 as NSString).deletingLastPathComponent } ?? ""
        var s = (setting ?? "").trimmingCharacters(in: .whitespaces)
        if s.isEmpty || s == "/" { return "" }
        if s == "." || s == "./" { return noteFolder }
        if s.hasPrefix("./") {
            s.removeFirst(2)
            s = s.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return noteFolder.isEmpty ? s : noteFolder + "/" + s
        }
        return s.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// `folder/name`, adding " 1", " 2"… before the extension until `exists` says no.
    public static func uniquePath(folder: String, name: String, exists: (String) -> Bool) -> String {
        func join(_ n: String) -> String { folder.isEmpty ? n : folder + "/" + n }
        var candidate = join(name)
        guard exists(candidate) else { return candidate }
        let stem = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var i = 1
        repeat {
            candidate = join("\(stem) \(i)" + (ext.isEmpty ? "" : ".\(ext)"))
            i += 1
        } while exists(candidate)
        return candidate
    }

    public static func embed(_ fileName: String) -> String { "![[\(fileName)]]" }

    /// The embed as its own line at `offset` (UTF-16), with newlines added only where the
    /// neighbours need them. Returns the inserted string so a text view can apply it with undo.
    public static func embedInsertion(in text: String, at offset: Int, fileName: String) -> String {
        let ns = text as NSString
        let at = max(0, min(offset, ns.length))
        let before = at > 0 ? ns.substring(with: NSRange(location: at - 1, length: 1)) : "\n"
        let after = at < ns.length ? ns.substring(with: NSRange(location: at, length: 1)) : ""
        var s = ""
        if before != "\n" { s += "\n" }
        s += embed(fileName)
        if after.isEmpty || after != "\n" { s += "\n" }
        return s
    }

    /// The transcript as an Obsidian callout (renders as a quote anywhere else).
    public static func transcriptBlock(_ transcript: String) -> String {
        let body = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = ["> [!transcript] Transcript"]
        if body.isEmpty {
            lines.append("> *(no speech recognized)*")
        } else {
            for line in body.components(separatedBy: .newlines) { lines.append(line.isEmpty ? ">" : "> " + line) }
        }
        return lines.joined(separator: "\n")
    }

    /// Where the transcript goes: right after the line holding the embed (found by text, so edits made
    /// while transcribing don't matter). Returns (UTF-16 offset, string to insert), or nil if the embed is gone.
    public static func transcriptInsertion(in text: String, fileName: String, transcript: String) -> (offset: Int, insert: String)? {
        let ns = text as NSString
        let r = ns.range(of: embed(fileName))
        guard r.location != NSNotFound else { return nil }
        let line = ns.lineRange(for: r)
        let end = NSMaxRange(line)
        let block = transcriptBlock(transcript)
        let endsWithNewline = end > line.location && ns.substring(with: NSRange(location: end - 1, length: 1)) == "\n"
        guard endsWithNewline else { return (end, "\n\n" + block + "\n") }
        // A blank line after the callout, so the next paragraph isn't pulled into the quote.
        let nextIsBlank = end >= ns.length || ns.substring(with: NSRange(location: end, length: 1)) == "\n"
        return (end, "\n" + block + "\n" + (nextIsBlank ? "" : "\n"))
    }

    /// Apply `transcriptInsertion` to a string (for notes that aren't open).
    public static func insertingTranscript(into text: String, fileName: String, transcript: String) -> String? {
        guard let (off, ins) = transcriptInsertion(in: text, fileName: fileName, transcript: transcript) else { return nil }
        return (text as NSString).replacingCharacters(in: NSRange(location: off, length: 0), with: ins)
    }

    /// "1:05", "12:00", "1:02:03".
    public static func elapsed(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// Join recognizer segments into paragraphs: a new paragraph after a long pause.
    public static func joinSegments(_ segments: [(text: String, start: Double, end: Double)], pause: Double = 2.0) -> String {
        var out = ""
        var lastEnd: Double? = nil
        for seg in segments {
            let t = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            if let le = lastEnd { out += (seg.start - le >= pause) ? "\n\n" : " " }
            out += t
            lastEnd = seg.end
        }
        return out
    }

    /// Parse an HTTP `Range: bytes=a-b` header against a body length. nil = serve the whole body.
    public static func byteRange(_ header: String?, length: Int) -> Range<Int>? {
        guard let h = header?.trimmingCharacters(in: .whitespaces), h.hasPrefix("bytes="), length > 0 else { return nil }
        let spec = h.dropFirst(6).split(separator: ",").first.map(String.init) ?? ""
        let parts = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return nil }
        if parts[0].isEmpty {   // suffix: last n bytes
            guard let n = Int(parts[1]), n > 0 else { return nil }
            return max(0, length - n)..<length
        }
        guard let a = Int(parts[0]), a < length else { return nil }
        let b = parts[1].isEmpty ? length - 1 : min(Int(parts[1]) ?? (length - 1), length - 1)
        guard b >= a else { return nil }
        return a..<(b + 1)
    }
}
