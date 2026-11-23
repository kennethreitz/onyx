import AVFoundation
import SwiftUI
import OnyxCore

enum SpeechPrefs {
    static let voice = "onyx.speechVoice"   // AVSpeechSynthesisVoice identifier; empty = system default
    static let rate = "onyx.speechRate"

    static var voiceIdentifier: String { UserDefaults.standard.string(forKey: voice) ?? "" }
    static var rateValue: Float {
        if let v = UserDefaults.standard.object(forKey: rate) as? Double { return Float(v) }
        return AVSpeechUtteranceDefaultSpeechRate
    }
}

/// Reads a note aloud with the Mac's system voices.
@MainActor
@Observable
final class SpeechReader: NSObject, AVSpeechSynthesizerDelegate {
    enum State: Equatable { case idle, speaking, paused }

    var state: State = .idle
    var isActive: Bool { state != .idle }

    private let synth = AVSpeechSynthesizer()
    private var lastUtterance: AVSpeechUtterance?

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ text: String) {
        synth.stopSpeaking(at: .immediate)
        lastUtterance = nil
        let prose = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prose.isEmpty else { state = .idle; return }
        state = .speaking
        for chunk in Self.chunks(prose) {
            let u = AVSpeechUtterance(string: chunk)
            let id = SpeechPrefs.voiceIdentifier
            if !id.isEmpty { u.voice = AVSpeechSynthesisVoice(identifier: id) }
            u.rate = SpeechPrefs.rateValue
            lastUtterance = u
            synth.speak(u)
        }
    }

    func togglePause() {
        switch state {
        case .speaking:
            if synth.pauseSpeaking(at: .word) { state = .paused }
        case .paused:
            if synth.continueSpeaking() { state = .speaking }
        case .idle:
            break
        }
    }

    func stop() {
        guard state != .idle || synth.isSpeaking || synth.isPaused else { return }
        lastUtterance = nil
        synth.stopSpeaking(at: .immediate)
        state = .idle
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard lastUtterance === utterance else { return }
            lastUtterance = nil
            state = .idle
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard lastUtterance === utterance else { return }
            lastUtterance = nil
            state = .idle
        }
    }

    /// Prefer breaking a long note at a paragraph, then a sentence, so the
    /// synthesizer isn't handed one enormous utterance.
    static func chunks(_ text: String, max: Int = 4000) -> [String] {
        if text.count <= max { return [text] }
        var parts: [String] = []
        var rest = text[...]
        while !rest.isEmpty {
            if rest.count <= max {
                parts.append(String(rest))
                break
            }
            let window = rest.prefix(max)
            let cut: String.Index
            if let para = window.range(of: "\n\n", options: .backwards)?.lowerBound, para > rest.startIndex {
                cut = para
            } else if let sent = window.rangeOfCharacter(from: CharacterSet(charactersIn: ".?!"), options: .backwards),
                      sent.upperBound > rest.index(rest.startIndex, offsetBy: max / 3) {
                cut = sent.upperBound
            } else {
                cut = window.endIndex
            }
            parts.append(String(rest[..<cut]).trimmingCharacters(in: .whitespacesAndNewlines))
            rest = rest[cut...].drop(while: { $0 == "\n" || $0 == " " })
        }
        return parts.filter { !$0.isEmpty }
    }

    static func voices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().sorted {
            if $0.language != $1.language { return $0.language < $1.language }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func languageName(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }
}

/// The footer's quiet "Reading" chip, with pause and stop. The label and
/// speaker icon keep a fixed width so pause/stop don't slide when the
/// state flips between Reading and Paused, or when play.fill replaces pause.fill.
struct SpeechBadge: View {
    var speech: SpeechReader
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: speech.state == .paused ? "pause.fill" : "speaker.wave.2.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.muted)
                .frame(width: 22, height: 22)
            ZStack(alignment: .leading) {
                Text("Reading").hidden().accessibilityHidden(true)
                Text("Paused").hidden().accessibilityHidden(true)
                Text(speech.state == .paused ? "Paused" : "Reading")
                    .foregroundStyle(Color.muted)
            }
            .font(.system(size: 11.5))
            FooterButton(symbol: speech.state == .paused ? "play.fill" : "pause.fill",
                         help: speech.state == .paused ? "Resume reading" : "Pause reading") {
                speech.togglePause()
            }
            FooterButton(symbol: "stop.fill", help: "Stop reading") { speech.stop() }
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(speech.state == .paused ? "Paused reading" : "Reading aloud")
    }
}
