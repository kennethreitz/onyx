import AVFoundation
import Speech
import SwiftUI
import OnyxCore

enum RecordingPrefs {
    static let autoTranscribe = "onyx.autoTranscribe"
    static var autoTranscribeOn: Bool { UserDefaults.standard.object(forKey: autoTranscribe) as? Bool ?? true }
}

enum RecordingError: LocalizedError {
    case micDenied, speechDenied, recognizerUnavailable, couldNotStart

    var errorDescription: String? {
        switch self {
        case .micDenied: "Onyx can’t use the microphone. Allow it in System Settings ▸ Privacy & Security ▸ Microphone."
        case .speechDenied: "Onyx can’t transcribe. Allow it in System Settings ▸ Privacy & Security ▸ Speech Recognition."
        case .recognizerUnavailable: "On-device speech recognition isn’t available for this language."
        case .couldNotStart: "Couldn’t start recording."
        }
    }
}

/// Records the microphone to an AAC .m4a with AVAudioRecorder.
@MainActor
@Observable
final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    enum State: Equatable { case idle, recording(since: Date), transcribing }

    struct Take { var url: URL; var rel: String; var note: String }

    var state: State = .idle
    var isRecording: Bool { if case .recording = state { return true }; return false }
    var isActive: Bool { state != .idle }

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var take: Take?

    static func requestMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    func start(_ t: Take) async throws {
        guard state == .idle else { return }
        guard await Self.requestMicrophone() else { throw RecordingError.micDenied }
        try FileManager.default.createDirectory(at: t.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let r = try AVAudioRecorder(url: t.url, settings: settings)
        r.delegate = self
        guard r.prepareToRecord(), r.record() else { throw RecordingError.couldNotStart }
        recorder = r
        take = t
        state = .recording(since: Date())
    }

    /// Stops and hands back the finished file (nil if nothing was recording).
    func stop() -> Take? {
        guard let r = recorder, let t = take else { return nil }
        r.stop()
        recorder = nil
        take = nil
        state = .idle
        return t
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            guard self.recorder === recorder else { return }
            self.recorder = nil; self.take = nil; self.state = .idle
        }
    }
}

/// On-device transcription of a finished recording. Prefers SpeechAnalyzer/SpeechTranscriber
/// (macOS 26+), else SFSpeechRecognizer with on-device recognition, fed in ~50 s chunks.
enum Transcriber {
    static func transcribe(_ url: URL, locale: Locale = .current) async throws -> String {
        #if compiler(>=6.2)
        if #available(macOS 26, *), SpeechTranscriber.isAvailable {
            do { return try await analyzer(url, locale: locale) } catch {
                NSLog("Onyx: SpeechAnalyzer failed (\(error)); falling back to SFSpeechRecognizer")
            }
        }
        #endif
        return try await recognizer(url, locale: locale)
    }

    #if compiler(>=6.2)
    @available(macOS 26, *)
    private static func analyzer(_ url: URL, locale: Locale) async throws -> String {
        var loc = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
        if loc == nil { loc = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) }
        guard let loc else { throw RecordingError.recognizerUnavailable }
        let transcriber = SpeechTranscriber(locale: loc, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
        if let install = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await install.downloadAndInstall()   // first use per language fetches the on-device model
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collect = Task { () -> [(text: String, start: Double, end: Double)] in
            var segs: [(text: String, start: Double, end: Double)] = []
            for try await r in transcriber.results {
                segs.append((String(r.text.characters), r.range.start.seconds, r.range.end.seconds))
            }
            return segs
        }
        let file = try AVAudioFile(forReading: url)
        if let last = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return AudioNote.joinSegments(try await collect.value)
    }
    #endif

    private static func recognizer(_ url: URL, locale: Locale) async throws -> String {
        let status = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard status == .authorized else { throw RecordingError.speechDenied }
        guard let rec = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(), rec.isAvailable else {
            throw RecordingError.recognizerUnavailable
        }
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let chunkSeconds = 50.0
        let chunkFrames = AVAudioFramePosition(format.sampleRate * chunkSeconds)
        var segs: [(text: String, start: Double, end: Double)] = []
        var start = 0.0
        while file.framePosition < file.length {
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = false
            req.addsPunctuation = true
            if rec.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
            let stop = min(file.length, file.framePosition + chunkFrames)
            while file.framePosition < stop {
                let n = AVAudioFrameCount(min(16_384, stop - file.framePosition))
                guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n) else { break }
                try file.read(into: buf, frameCount: n)
                if buf.frameLength == 0 { break }
                req.append(buf)
            }
            req.endAudio()
            let text = try await recognize(rec, req)
            let end = Double(file.framePosition) / format.sampleRate
            segs.append((text, start, end))
            start = end
            if stop >= file.length { break }
        }
        return AudioNote.joinSegments(segs, pause: .infinity)
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock(); private var done = false
        func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
    }

    private static func recognize(_ rec: SFSpeechRecognizer, _ req: SFSpeechAudioBufferRecognitionRequest) async throws -> String {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<String, Error>) in
            let once = Once()
            rec.recognitionTask(with: req) { result, error in
                if let result, result.isFinal {
                    if once.claim() { c.resume(returning: result.bestTranscription.formattedString) }
                } else if let error {
                    // "No speech detected" for a silent chunk isn't a failure.
                    let ns = error as NSError
                    if once.claim() {
                        if ns.domain == "kAFAssistantErrorDomain" && (ns.code == 1110 || ns.code == 203) { c.resume(returning: "") }
                        else { c.resume(throwing: error) }
                    }
                }
            }
        }
    }
}

// MARK: Workspace

extension Workspace {
    func toggleRecording() {
        switch recorder.state {
        case .idle: startRecording()
        case .recording: stopRecording()
        case .transcribing: toast = "Still transcribing the last recording…"
        }
    }

    func startRecording() {
        guard let root, let note = currentPath, !isCanvas, !isBase, !isFile else {
            toast = "Open a note to record into"
            return
        }
        let folder = AudioNote.attachmentFolder(setting: obsidianAttachmentFolderSetting(), notePath: note)
        let rel = AudioNote.uniquePath(folder: folder, name: AudioNote.fileName(date: Date())) {
            FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path)
        }
        let url = root.appendingPathComponent(rel).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/"), !rel.contains("..") else {
            toast = "The attachment folder is outside the vault"
            return
        }
        speech.stop()
        Task { @MainActor in
            do { try await recorder.start(.init(url: url, rel: rel, note: note)) }
            catch { toast = error.localizedDescription }
        }
    }

    func stopRecording() {
        guard let take = recorder.stop() else { return }
        fileAdded(take.rel)
        let name = (take.rel as NSString).lastPathComponent
        let embedded = spliceNote(take.note, caret: true) { text, caret in
            let at = caret ?? (text as NSString).length
            return (at, AudioNote.embedInsertion(in: text, at: at, fileName: name))
        }
        if !embedded { toast = "Saved “\(name)”" }
        guard RecordingPrefs.autoTranscribeOn else { return }
        recorder.state = .transcribing
        Task { @MainActor in
            defer { if recorder.state == .transcribing { recorder.state = .idle } }
            do {
                let transcript = try await Transcriber.transcribe(take.url)
                let ok = spliceNote(take.note, caret: false) { text, _ in
                    AudioNote.transcriptInsertion(in: text, fileName: name, transcript: transcript)
                }
                if !ok { toast = "Transcribed, but “\(name)” is no longer in the note" }
            } catch {
                toast = "Transcription failed: \(error.localizedDescription)"
            }
        }
    }

    /// Insert into a note: through the live editor (undoable, keeps the caret) when it's showing it,
    /// into `text` when it's open in the reader, else on disk.
    @discardableResult
    private func spliceNote(_ path: String, caret: Bool, _ edit: (String, Int?) -> (offset: Int, insert: String)?) -> Bool {
        if path == currentPath {
            if mode == .edit, let tv = liveEditor, tv.window != nil, tv.isEditable, tv.string == text {
                let sel = tv.selectedRange()
                guard let (off, ins) = edit(tv.string, caret ? sel.location : nil) else { return false }
                let r = NSRange(location: off, length: 0)
                guard tv.shouldChangeText(in: r, replacementString: ins) else { return false }
                tv.replaceCharacters(in: r, with: ins)
                tv.didChangeText()
                let len = (ins as NSString).length
                if caret { tv.setSelectedRange(NSRange(location: off + len, length: 0)) }
                else if sel.location >= off { tv.setSelectedRange(NSRange(location: sel.location + len, length: sel.length)) }
                else { tv.setSelectedRange(sel) }
                return true
            }
            guard let (off, ins) = edit(text, nil) else { return false }
            text = (text as NSString).replacingCharacters(in: NSRange(location: off, length: 0), with: ins)
            renderToken += 1
            return true
        }
        guard let root, let disk = try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8),
              let (off, ins) = edit(disk, nil) else { return false }
        let new = (disk as NSString).replacingCharacters(in: NSRange(location: off, length: 0), with: ins)
        guard write(new, to: path, create: false) else { return false }
        noteUpdatedOnDisk(path, content: new)
        return true
    }
}

/// The footer's quiet recording chip: elapsed time and stop, then “Transcribing…”.
struct RecordingBadge: View {
    var recorder: AudioRecorder
    var stop: () -> Void
    var body: some View {
        HStack(spacing: 4) {
            switch recorder.state {
            case .recording(let since):
                Circle().fill(Color.danger).frame(width: 6, height: 6)
                TimelineView(.periodic(from: since, by: 1)) { ctx in
                    Text(AudioNote.elapsed(ctx.date.timeIntervalSince(since)))
                        .font(.system(size: 11.5).monospacedDigit())
                        .foregroundStyle(Color.muted)
                }
                FooterButton(symbol: "stop.fill", help: "Stop recording") { stop() }
            case .transcribing:
                ProgressView().controlSize(.mini).scaleEffect(0.8)
                Text("Transcribing…").font(.system(size: 11.5)).foregroundStyle(Color.muted)
            case .idle:
                EmptyView()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(recorder.state == .transcribing ? "Transcribing recording" : "Recording audio")
    }
}
