import XCTest
@testable import OnyxCore

final class AudioNoteTests: XCTestCase {
    func testFileName() {
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 21; c.hour = 13; c.minute = 5; c.second = 12
        c.timeZone = TimeZone(identifier: "America/New_York")
        let d = Calendar(identifier: .gregorian).date(from: c)!
        XCTAssertEqual(AudioNote.fileName(date: d, timeZone: TimeZone(identifier: "America/New_York")!),
                       "Recording 2026-11-21 13-05-12.m4a")
    }

    func testAttachmentFolder() {
        XCTAssertEqual(AudioNote.attachmentFolder(setting: nil, notePath: "A/B/n.md"), "")
        XCTAssertEqual(AudioNote.attachmentFolder(setting: "/", notePath: "A/n.md"), "")
        XCTAssertEqual(AudioNote.attachmentFolder(setting: "./", notePath: "A/B/n.md"), "A/B")
        XCTAssertEqual(AudioNote.attachmentFolder(setting: "./", notePath: "n.md"), "")
        XCTAssertEqual(AudioNote.attachmentFolder(setting: "./assets", notePath: "A/n.md"), "A/assets")
        XCTAssertEqual(AudioNote.attachmentFolder(setting: "./assets", notePath: "n.md"), "assets")
        XCTAssertEqual(AudioNote.attachmentFolder(setting: "Attachments/", notePath: "A/n.md"), "Attachments")
    }

    func testUniquePath() {
        let taken: Set = ["X/r.m4a", "X/r 1.m4a"]
        XCTAssertEqual(AudioNote.uniquePath(folder: "X", name: "r.m4a") { taken.contains($0) }, "X/r 2.m4a")
        XCTAssertEqual(AudioNote.uniquePath(folder: "", name: "r.m4a") { _ in false }, "r.m4a")
    }

    func testEmbedInsertion() {
        XCTAssertEqual(AudioNote.embedInsertion(in: "", at: 0, fileName: "r.m4a"), "![[r.m4a]]\n")
        XCTAssertEqual(AudioNote.embedInsertion(in: "Hello", at: 5, fileName: "r.m4a"), "\n![[r.m4a]]\n")
        XCTAssertEqual(AudioNote.embedInsertion(in: "Hello\n", at: 6, fileName: "r.m4a"), "![[r.m4a]]\n")
        XCTAssertEqual(AudioNote.embedInsertion(in: "Hello\nWorld", at: 6, fileName: "r.m4a"), "![[r.m4a]]\n")
        XCTAssertEqual(AudioNote.embedInsertion(in: "Hello\n\nWorld", at: 6, fileName: "r.m4a"), "![[r.m4a]]")
    }

    func testTranscriptInsertion() {
        let t = "Intro\n![[r.m4a]]\nNext paragraph"
        XCTAssertEqual(AudioNote.insertingTranscript(into: t, fileName: "r.m4a", transcript: "Hi there.\n\nSecond."),
                       "Intro\n![[r.m4a]]\n\n> [!transcript] Transcript\n> Hi there.\n>\n> Second.\n\nNext paragraph")
        XCTAssertEqual(AudioNote.insertingTranscript(into: "![[r.m4a]]", fileName: "r.m4a", transcript: "Hi"),
                       "![[r.m4a]]\n\n> [!transcript] Transcript\n> Hi\n")
        XCTAssertEqual(AudioNote.insertingTranscript(into: "![[r.m4a]]\n", fileName: "r.m4a", transcript: "Hi"),
                       "![[r.m4a]]\n\n> [!transcript] Transcript\n> Hi\n")
        XCTAssertNil(AudioNote.insertingTranscript(into: "gone", fileName: "r.m4a", transcript: "Hi"))
        XCTAssertTrue(AudioNote.transcriptBlock("  ").contains("no speech recognized"))
    }

    func testElapsedAndSegments() {
        XCTAssertEqual(AudioNote.elapsed(65), "1:05")
        XCTAssertEqual(AudioNote.elapsed(3723), "1:02:03")
        XCTAssertEqual(AudioNote.joinSegments([("One.", 0, 1), ("Two.", 1.5, 2), ("Three.", 5, 6)]), "One. Two.\n\nThree.")
    }

    func testByteRange() {
        XCTAssertEqual(AudioNote.byteRange("bytes=0-1", length: 10), 0..<2)
        XCTAssertEqual(AudioNote.byteRange("bytes=4-", length: 10), 4..<10)
        XCTAssertEqual(AudioNote.byteRange("bytes=-3", length: 10), 7..<10)
        XCTAssertEqual(AudioNote.byteRange("bytes=0-99", length: 10), 0..<10)
        XCTAssertNil(AudioNote.byteRange("bytes=20-", length: 10))
        XCTAssertNil(AudioNote.byteRange(nil, length: 10))
    }
}
