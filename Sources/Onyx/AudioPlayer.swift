import AppKit
import SwiftUI
import AVFoundation
import OnyxCore

/// AVPlayer behind the audio view: position, duration, play state, speed (remembered), volume.
@MainActor @Observable final class AudioPlayerModel {
    static let speedKey = "onyx.audio.speed"
    let url: URL
    @ObservationIgnored let player: AVPlayer
    var time: Double = 0
    var duration: Double = 0
    var playing = false
    var speed: Double = UserDefaults.standard.object(forKey: AudioPlayerModel.speedKey) as? Double ?? 1
    var volume: Float = 1 { didSet { player.volume = volume } }
    var waveform: [Float] = []
    var scrubbing = false
    @ObservationIgnored private var tick: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    init(url: URL) {
        self.url = url
        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .timeDomain   // speech stays natural at 1.5×/2×
        player = AVPlayer(playerItem: item)
        tick = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, !self.scrubbing else { return }
                self.time = t.seconds.isFinite ? t.seconds : 0
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.playing = false; if let d = self?.duration { self?.time = d } }
        }
    }

    /// nil when AVFoundation can play it; otherwise why not.
    func prepare() async -> Bool {
        let asset = AVURLAsset(url: url)
        let playable = (try? await asset.load(.isPlayable)) ?? false
        let d = (try? await asset.load(.duration))?.seconds ?? 0
        duration = d.isFinite ? d : 0
        guard playable else { return false }
        if duration > 0, duration < 3 * 3600 {
            let u = url
            let peaks = await Task.detached(priority: .utility) { AudioPlayerModel.peaks(u) }.value
            waveform = AudioPlayback.waveform(peaks, bins: 480)
        }
        return true
    }

    func toggle() { playing ? pause() : play() }
    func play() {
        if duration > 0, time >= duration - 0.05 { seek(0) }
        player.playImmediately(atRate: Float(speed))
        playing = true
    }
    func pause() { player.pause(); playing = false }
    func seek(_ t: Double) {
        let t = AudioPlayback.skip(t, by: 0, duration: duration)
        time = t
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    func skip(_ by: Double) { seek(AudioPlayback.skip(time, by: by, duration: duration)) }
    func setSpeed(_ s: Double) {
        speed = s
        UserDefaults.standard.set(s, forKey: Self.speedKey)
        if playing { player.rate = Float(s) }
    }
    func stop() {
        pause()
        if let tick { player.removeTimeObserver(tick) }
        tick = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }

    /// Peak amplitude every ~20 ms, decoded at 8 kHz mono (cheap, and plenty for a 480-bar waveform).
    nonisolated static func peaks(_ url: URL) -> [Float] {
        let asset = AVURLAsset(url: url)
        let sem = DispatchSemaphore(value: 0)
        var track: AVAssetTrack?
        asset.loadTracks(withMediaType: .audio) { t, _ in track = t?.first; sem.signal() }
        sem.wait()
        guard let track, let reader = try? AVAssetReader(asset: asset) else { return [] }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 8000, AVNumberOfChannelsKey: 1,
        ])
        guard reader.canAdd(out) else { return [] }
        reader.add(out)
        guard reader.startReading() else { return [] }
        var peaks: [Float] = []
        var peak: Int16 = 0, count = 0
        while let sb = out.copyNextSampleBuffer() {
            guard let bb = CMSampleBufferGetDataBuffer(sb) else { continue }
            let len = CMBlockBufferGetDataLength(bb)
            var data = [Int16](repeating: 0, count: len / 2)
            data.withUnsafeMutableBytes { _ = CMBlockBufferCopyDataBytes(bb, atOffset: 0, dataLength: len, destination: $0.baseAddress!) }
            for s in data {
                let a = s == Int16.min ? Int16.max : abs(s)
                if a > peak { peak = a }
                count += 1
                if count == 160 { peaks.append(Float(peak) / 32767); peak = 0; count = 0 }
            }
        }
        if count > 0 { peaks.append(Float(peak) / 32767) }
        return peaks
    }
}

/// The audio file view: a big waveform scrubber, transport, speed, volume, and the transcript
/// Record Audio wrote under the embed, when there is one.
struct AudioPlayerView: View {
    var ws: Workspace
    let path: String
    let url: URL
    var focused: Bool
    @Binding var unsupported: Bool
    @Binding var meta: String
    @State private var model: AudioPlayerModel?
    @State private var keys: Any?
    @State private var transcript: (text: String, note: String)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(Theme.serif(22)).foregroundStyle(Color.ink).lineLimit(2)
                if let m = model {
                    WaveformScrubber(model: m).frame(height: 72)
                    HStack {
                        Text(AudioPlayback.labels(time: m.time, duration: m.duration).elapsed)
                        Spacer()
                        Text(AudioPlayback.labels(time: m.time, duration: m.duration).remaining)
                    }
                    .font(.system(size: TypeScale.small).monospacedDigit()).foregroundStyle(Color.muted)
                    transport(m)
                } else {
                    ProgressView().controlSize(.small)
                }
                if let t = transcript { transcriptView(t) }
            }
            .padding(.horizontal, Space.xxl).padding(.vertical, 40)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .task(id: url) { await load() }
        .onChange(of: focused) { _, f in f ? installKeys() : removeKeys() }
        .onDisappear { model?.stop(); removeKeys() }   // leaving the file stops playback
    }

    func transport(_ m: AudioPlayerModel) -> some View {
        HStack(spacing: Space.l) {
            Spacer()
            TransportButton(symbol: "gobackward.15", size: 17, help: "Back 15 seconds  ←") { m.skip(-AudioPlayback.skipSeconds) }
            TransportButton(symbol: m.playing ? "pause.fill" : "play.fill", size: 22, help: m.playing ? "Pause  Space" : "Play  Space", prominent: true) { m.toggle() }
            TransportButton(symbol: "goforward.15", size: 17, help: "Forward 15 seconds  →") { m.skip(AudioPlayback.skipSeconds) }
            Spacer()
        }
        .overlay(alignment: .leading) {
            Menu {
                ForEach(AudioPlayback.speeds, id: \.self) { s in
                    Button { m.setSpeed(s) } label: { Text(AudioPlayback.speedLabel(s)) + Text(abs(s - m.speed) < 0.01 ? "  ✓" : "") }
                }
            } label: {
                Text(AudioPlayback.speedLabel(m.speed)).font(.system(size: TypeScale.body).monospacedDigit()).foregroundStyle(Color.muted)
            } primaryAction: { m.setSpeed(AudioPlayback.nextSpeed(after: m.speed)) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Playback speed (click to cycle)")
        }
        .overlay(alignment: .trailing) {
            HStack(spacing: Space.xs) {
                Image(systemName: m.volume == 0 ? "speaker.slash" : "speaker.wave.2").font(.system(size: 10)).foregroundStyle(Color.faint)
                Slider(value: Binding(get: { Double(m.volume) }, set: { m.volume = Float($0) }), in: 0...1).controlSize(.mini).frame(width: 80)
            }
        }
    }

    func transcriptView(_ t: (text: String, note: String)) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Text("TRANSCRIPT").font(.system(size: TypeScale.label)).tracking(0.8).foregroundStyle(Color.faint)
                Spacer()
                Button { ws.openNote(t.note) } label: {
                    Text("from " + ((t.note as NSString).lastPathComponent as NSString).deletingPathExtension + " ↗")
                        .font(.system(size: TypeScale.caption)).foregroundStyle(Color.faint)
                }.buttonStyle(.plain)
            }
            Text(t.text.isEmpty ? "No speech recognized." : t.text)
                .font(Theme.serif(15, italic: t.text.isEmpty)).foregroundStyle(t.text.isEmpty ? Color.muted : Color.ink)
                .lineSpacing(4).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Space.m)
    }

    func load() async {
        model?.stop()
        let m = AudioPlayerModel(url: url)
        model = m
        transcript = findTranscript()
        if focused { installKeys() }
        let ok = await m.prepare()
        guard model === m else { return }
        if !ok { m.stop(); unsupported = true; return }
        meta = m.duration > 0 ? AudioNote.elapsed(m.duration) : ""
    }

    /// The `> [!transcript]` callout under an embed of this file, in a note that links here.
    func findTranscript() -> (text: String, note: String)? {
        guard let snap = ws.snapshot else { return nil }
        let name = url.lastPathComponent
        var sources = Array(Set(snap.backlinks(to: path).map(\.source))).sorted()
        if sources.isEmpty { sources = snap.notes.values.filter { $0.content.contains(name) }.map(\.path).sorted() }
        for s in sources {
            if let c = snap.notes[s]?.content, let t = AudioPlayback.transcript(forEmbedOf: name, in: c) { return (t, s) }
        }
        return nil
    }

    /// Space plays/pauses, ←/→ skip 15 s, while this pane has focus and nothing is typing.
    func installKeys() {
        guard keys == nil else { return }
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            guard let m = model, ws.overlay == .none, ws.currentPath == path, focused,
                  e.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  !(e.window?.firstResponder is NSText) else { return e }
            switch e.keyCode {
            case 49: m.toggle(); return nil
            case 123: m.skip(-AudioPlayback.skipSeconds); return nil
            case 124: m.skip(AudioPlayback.skipSeconds); return nil
            default: return e
            }
        }
    }
    func removeKeys() { if let k = keys { NSEvent.removeMonitor(k) }; keys = nil }
}

struct TransportButton: View {
    var symbol: String
    var size: CGFloat
    var help: String
    var prominent = false
    var action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(prominent || hover ? Color.ink : Color.muted)
                .frame(width: prominent ? 48 : 36, height: prominent ? 48 : 36)
                .background(Color.ink.opacity(prominent ? (hover ? 0.09 : 0.06) : (hover ? 0.06 : 0)), in: Circle())
                .contentShape(Circle())
                .animation(Motion.hover, value: hover)
        }
        .buttonStyle(.plain).help(help).onHover { hover = $0 }
    }
}

/// The waveform doubles as the scrubber: click or drag anywhere to seek. Without a waveform
/// (unknown duration, very long files) it's a hairline track.
struct WaveformScrubber: View {
    var model: AudioPlayerModel
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let progress = model.duration > 0 ? min(1, max(0, model.time / model.duration)) : 0
            Canvas { ctx, size in
                let bars = model.waveform
                if bars.isEmpty {
                    let y = size.height / 2
                    ctx.fill(Path(CGRect(x: 0, y: y - 1, width: size.width, height: 2)), with: .color(Color.hairline))
                    ctx.fill(Path(CGRect(x: 0, y: y - 1, width: size.width * progress, height: 2)), with: .color(Color.ink))
                } else {
                    let step = size.width / CGFloat(bars.count)
                    let bw = max(1, step * 0.6)
                    for (i, v) in bars.enumerated() {
                        let x = CGFloat(i) * step
                        let bh = max(2, CGFloat(v) * size.height)
                        let r = CGRect(x: x, y: (size.height - bh) / 2, width: bw, height: bh)
                        let played = (x + bw / 2) / size.width <= progress
                        ctx.fill(Path(roundedRect: r, cornerRadius: bw / 2), with: .color(played ? Color.ink : Color.faint.opacity(0.45)))
                    }
                }
                ctx.fill(Path(CGRect(x: size.width * progress - 0.75, y: 0, width: 1.5, height: size.height)), with: .color(Color.cursorBlue))
            }
            .frame(width: w, height: h)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    guard model.duration > 0 else { return }
                    model.scrubbing = true
                    model.time = Double(min(max(0, g.location.x / w), 1)) * model.duration
                }
                .onEnded { g in
                    guard model.duration > 0 else { return }
                    model.scrubbing = false
                    model.seek(Double(min(max(0, g.location.x / w), 1)) * model.duration)
                })
        }
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue(AudioPlayback.labels(time: model.time, duration: model.duration).elapsed)
    }
}
