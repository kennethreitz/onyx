import XCTest
@testable import OnyxCore

final class FileViewerTests: XCTestCase {
    func testKinds() {
        XCTAssertEqual(AttachmentKind.of("a/b.PNG"), .image)
        XCTAssertEqual(AttachmentKind.of("x.gif"), .image)
        XCTAssertEqual(AttachmentKind.of("x.svg"), .image)
        XCTAssertEqual(AttachmentKind.of("Recording 1.m4a"), .audio)
        XCTAssertEqual(AttachmentKind.of("x.mp3"), .audio)
        XCTAssertEqual(AttachmentKind.of("x.flac"), .audio)
        XCTAssertEqual(AttachmentKind.of("x.mov"), .video)
        XCTAssertEqual(AttachmentKind.of("x.webm"), .video)
        XCTAssertEqual(AttachmentKind.of("doc.pdf"), .pdf)
        XCTAssertEqual(AttachmentKind.of("data.zip"), .other)
        XCTAssertEqual(AttachmentKind.of("noext"), .other)
        XCTAssertTrue(AttachmentKind.likelyPlayable("a.m4a"))
        XCTAssertFalse(AttachmentKind.likelyPlayable("a.ogg"))
    }

    func testOpensInFileView() {
        XCTAssertTrue("a/b.png".opensInFileView)
        XCTAssertTrue("a.zip".opensInFileView)
        XCTAssertFalse("a/b.md".opensInFileView)
        XCTAssertFalse("a.MD".opensInFileView)
        XCTAssertFalse("b.canvas".opensInFileView)
        XCTAssertFalse("c.base".opensInFileView)
        XCTAssertFalse("".opensInFileView)
    }

    func testSpeeds() {
        XCTAssertEqual(AudioPlayback.nextSpeed(after: 1), 1.25)
        XCTAssertEqual(AudioPlayback.nextSpeed(after: 2), 0.75)
        XCTAssertEqual(AudioPlayback.nextSpeed(after: 1.1), 1.25)   // unknown → from 1×
        XCTAssertEqual(AudioPlayback.speedLabel(1), "1×")
        XCTAssertEqual(AudioPlayback.speedLabel(1.25), "1.25×")
        XCTAssertEqual(AudioPlayback.speedLabel(1.5), "1.5×")
        XCTAssertEqual(AudioPlayback.speedLabel(0.75), "0.75×")
    }

    func testSkip() {
        XCTAssertEqual(AudioPlayback.skip(10, by: -15, duration: 100), 0)
        XCTAssertEqual(AudioPlayback.skip(90, by: 15, duration: 100), 100)
        XCTAssertEqual(AudioPlayback.skip(20, by: 15, duration: 100), 35)
        XCTAssertEqual(AudioPlayback.skip(20, by: 15, duration: 0), 35)
    }

    func testLabels() {
        let l = AudioPlayback.labels(time: 65, duration: 200)
        XCTAssertEqual(l.elapsed, "1:05")
        XCTAssertEqual(l.remaining, "-2:15")
        XCTAssertEqual(AudioPlayback.labels(time: 3, duration: .nan).remaining, "--:--")
        XCTAssertEqual(AudioPlayback.labels(time: 4000, duration: 3725).elapsed, "1:02:05")
        XCTAssertEqual(AudioPlayback.labels(time: .nan, duration: 10).elapsed, "0:00")
    }

    func testWaveform() {
        XCTAssertEqual(AudioPlayback.waveform([], bins: 10), [])
        XCTAssertEqual(AudioPlayback.waveform([0.5, -1, 0.25, 0.25], bins: 2), [1, 0.25])
        XCTAssertEqual(AudioPlayback.waveform([0, 0.5], bins: 8), [0, 1])
        XCTAssertEqual(AudioPlayback.waveform([0, 0, 0], bins: 2), [0, 0])
    }

    func testTranscript() {
        let note = """
        # Walk

        ![[Recording 2026-11-21 13-05-12.m4a]]
        > [!transcript] Transcript
        > First paragraph.
        >
        > Second one.

        After.
        """
        XCTAssertEqual(AudioPlayback.transcript(forEmbedOf: "Recording 2026-11-21 13-05-12.m4a", in: note), "First paragraph.\n\nSecond one.")
        XCTAssertEqual(AudioPlayback.transcript(forEmbedOf: "recording 2026-11-21 13-05-12.M4A", in: note), "First paragraph.\n\nSecond one.")
        XCTAssertNil(AudioPlayback.transcript(forEmbedOf: "other.m4a", in: note))
        XCTAssertEqual(AudioPlayback.transcript(forEmbedOf: "r.m4a", in: "![[Audio/r.m4a|x]]\n\n> [!transcript] Transcript\n> hi"), "hi")
        XCTAssertEqual(AudioPlayback.transcript(forEmbedOf: "r.m4a", in: "![[r.m4a]]\n> [!transcript] Transcript\n> *(no speech recognized)*"), "")
        XCTAssertNil(AudioPlayback.transcript(forEmbedOf: "r.m4a", in: "![[r.m4a]]\n> [!note] Not it\n> hi"))
        XCTAssertNil(AudioPlayback.transcript(forEmbedOf: "r.m4a", in: "![[r.m4a]]\nplain text\n> [!transcript] x\n> hi"))
    }

    func testMarkdownLinkHit() {
        let line = "see [the clip](Audio/my%20clip.mp3) and ![](./img.png) or [web](https://x.com)"
        XCTAssertEqual(MarkdownLinkHit.target(in: line, at: 8), "Audio/my clip.mp3")
        XCTAssertEqual(MarkdownLinkHit.target(in: line, at: 44), "img.png")
        XCTAssertNil(MarkdownLinkHit.target(in: line, at: 70))
        XCTAssertNil(MarkdownLinkHit.target(in: line, at: 1))
        XCTAssertEqual(MarkdownLinkHit.target(in: "[a](Note.md#Head)", at: 2), "Note.md")
        XCTAssertEqual(MarkdownLinkHit.target(in: "[a](<My File.pdf> \"t\")", at: 2), "My File.pdf")
    }
}
