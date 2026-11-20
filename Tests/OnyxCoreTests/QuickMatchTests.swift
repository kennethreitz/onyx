import XCTest
@testable import OnyxCore

final class QuickMatchTests: XCTestCase {
    let now = ISO8601DateFormatter().date(from: "2026-11-20T12:00:00Z")!

    func entry(_ path: String, aliases: [String] = [], daysOld: Double = 400) -> QuickEntry {
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let folder = (path as NSString).deletingLastPathComponent
        return QuickEntry(path: path, name: MatchKey(name), folder: MatchKey(folder), aliases: aliases.map(MatchKey.init),
                          mtime: now.addingTimeInterval(-daysOld * 86_400), dated: QuickIndex.date(in: name))
    }

    lazy var index = QuickIndex(entries: [
        entry("Knowledge/Hebrew Letters/Aleph.md"),
        entry("Knowledge/Hebrew Letters/Bet.md"),
        entry("Knowledge/Hebrew Letters/He.md"),
        entry("Knowledge/Hebrew Letters/Hebrew Letters.md", aliases: ["Alefbet"]),
        entry("Projects/Aleph Prototype.md"),
        entry("Writing/Drafts/Alephs and Beginnings.md"),
        entry("Writing/Help Lines.md"),
        entry("Writing/Essays/How I Lost 100 Pounds in Six Months.md"),
        entry("Writing/Résumé.md"),
        entry("Writing/Café Notes.md"),
        entry("Knowledge/JavaScript.md", aliases: ["JS"]),
        entry("Projects/Onyx/Onyx Plan.md", aliases: ["Onyx Roadmap"]),
        entry("Knowledge/Table of Correspondences.md"),
        entry("Writing/Essays/Don't Panic Douglas Adams and the Recursive Absurdity of Existence.md"),
        entry("Daily/2026-11-18.md", daysOld: 2),
        entry("Daily/2026-11-19.md", daysOld: 1),
        entry("Daily/2026-11-20.md", daysOld: 0),
        entry("Daily/2026-10-20.md", daysOld: 31),
    ])

    func top(_ q: String, recent: [String] = [], _ n: Int = 1) -> [String] {
        index.search(q, recent: recent, now: now).prefix(n).map(\.entry.path)
    }

    func testTiers() {
        func tier(_ q: String, _ s: String) -> MatchTier? { QuickMatch.match(QuickMatch.fold(q), in: MatchKey(s))?.tier }
        XCTAssertEqual(tier("aleph", "Aleph"), .exact)
        XCTAssertEqual(tier("ALEPH", "aleph"), .exact)
        XCTAssertEqual(tier("ale", "Aleph"), .prefix)
        XCTAssertEqual(tier("hl", "Hebrew Letters"), .boundary)       // initials
        XCTAssertEqual(tier("heblet", "Hebrew Letters"), .boundary)   // word prefixes
        XCTAssertEqual(tier("let", "Hebrew Letters"), .boundary)      // a later word's prefix
        XCTAssertEqual(tier("js", "JavaScript"), .boundary)           // camelCase
        XCTAssertEqual(tier("brew", "Hebrew"), .substring)
        XCTAssertEqual(tier("hbrw", "Hebrew"), .subsequence)
        XCTAssertNil(tier("zz", "Hebrew"))
        XCTAssertNil(tier("onyx", "Don't Panic Douglas Adams and the Recursive Absurdity of Existence")) // sprinkled letters
    }

    func testOrderingAcrossTiers() {
        let s = { (q: String, c: String) in Fuzzy.score(q, c) ?? Int.min }
        XCTAssertGreaterThan(s("aleph", "Aleph"), s("aleph", "Aleph Prototype"))          // exact > prefix
        XCTAssertGreaterThan(s("ale", "Aleph Prototype"), s("ale", "Table Legs"))         // prefix > boundary
        XCTAssertGreaterThan(s("hl", "Help Lines"), s("hl", "Ethel"))                     // boundary > substring
        XCTAssertGreaterThan(s("brew", "Hebrew"), s("brew", "Bark Crew"))                 // substring > scattered
        XCTAssertGreaterThan(s("brew", "Bare Rewrite"), s("brew", "Hebrews"))             // word prefixes (B·REW) > mid-word
    }

    func testDiacritics() {
        XCTAssertEqual(top("resume"), ["Writing/Résumé.md"])
        XCTAssertEqual(top("CAFE"), ["Writing/Café Notes.md"])
        XCTAssertEqual(top("café"), ["Writing/Café Notes.md"])
        // highlights line up with the original characters
        let h = index.search("resume", now: now)[0]
        XCTAssertEqual(h.nameHits, [0, 1, 2, 3, 4, 5])
    }

    func testMultiTokenAndFolders() {
        XCTAssertEqual(top("hebrew aleph"), ["Knowledge/Hebrew Letters/Aleph.md"])
        XCTAssertEqual(top("aleph hebrew"), ["Knowledge/Hebrew Letters/Aleph.md"])        // any order
        XCTAssertEqual(top("hebrew/aleph"), ["Knowledge/Hebrew Letters/Aleph.md"])
        XCTAssertEqual(top("drafts aleph"), ["Writing/Drafts/Alephs and Beginnings.md"])
        XCTAssertTrue(index.search("hebrew zzz", now: now).isEmpty)                       // every token must match
        let h = index.search("hebrew aleph", now: now)[0]
        XCTAssertEqual(h.nameHits, [0, 1, 2, 3, 4])
        XCTAssertEqual(h.folderHits, Array(10..<16))                                       // "Hebrew" in Knowledge/Hebrew Letters
        XCTAssertEqual(top("onyx plan"), ["Projects/Onyx/Onyx Plan.md"])
        XCTAssertEqual(index.search("onyx plan", now: now).count, 1)                      // no sprinkled-letter junk
    }

    func testRanking() {
        XCTAssertEqual(top("aleph", 3), ["Knowledge/Hebrew Letters/Aleph.md", "Projects/Aleph Prototype.md", "Writing/Drafts/Alephs and Beginnings.md"])
        XCTAssertEqual(top("he"), ["Knowledge/Hebrew Letters/He.md"])                    // exact short title beats longer prefixes
        let hl = top("hl", 3)
        XCTAssertTrue(hl.contains("Writing/Help Lines.md") && hl.contains("Knowledge/Hebrew Letters/Hebrew Letters.md"))
        XCTAssertFalse(hl.contains("Writing/Essays/How I Lost 100 Pounds in Six Months.md") && hl.first == "Writing/Essays/How I Lost 100 Pounds in Six Months.md")
    }

    func testAliases() {
        let a = index.search("alefbet", now: now)
        XCTAssertEqual(a.first?.entry.path, "Knowledge/Hebrew Letters/Hebrew Letters.md")
        XCTAssertEqual(a.first?.alias, "Alefbet")
        XCTAssertEqual(top("onyx roadmap"), ["Projects/Onyx/Onyx Plan.md"])
        XCTAssertEqual(top("js"), ["Knowledge/JavaScript.md"])
        // a title match outranks the same-quality alias match
        XCTAssertGreaterThan(Fuzzy.score("aleph", "Aleph")!, 0)
    }

    func testRecencyAndDates() {
        XCTAssertEqual(top("2026-11", 3), ["Daily/2026-11-20.md", "Daily/2026-11-19.md", "Daily/2026-11-18.md"])
        XCTAssertEqual(top("daily 11 20"), ["Daily/2026-11-20.md"])
        XCTAssertEqual(top("20"), ["Daily/2026-11-20.md"])                                  // whole word beats a partial "2026"
        // recently opened lifts a note within its tier...
        XCTAssertEqual(top("aleph p", recent: ["Writing/Drafts/Alephs and Beginnings.md"]), ["Projects/Aleph Prototype.md"])
        XCTAssertEqual(top("ale", recent: ["Writing/Drafts/Alephs and Beginnings.md"]), ["Writing/Drafts/Alephs and Beginnings.md"])
        // ...but never over an exact match
        XCTAssertEqual(top("aleph", recent: ["Projects/Aleph Prototype.md"]), ["Knowledge/Hebrew Letters/Aleph.md"])
    }

    func testExactDetectionForCreate() {
        XCTAssertTrue(index.hasExact("aleph"))
        XCTAssertTrue(index.hasExact("RESUME"))
        XCTAssertTrue(index.hasExact("Projects/Onyx/Onyx Plan"))
        XCTAssertTrue(index.hasExact("Projects/Onyx/Onyx Plan.md"))
        XCTAssertFalse(index.hasExact("Aleph Notes"))
        XCTAssertFalse(index.hasExact("Projects/Aleph"))
    }

    func testPerformance() {
        var entries: [QuickEntry] = []
        let words = ["alpha", "beta", "gamma", "delta", "hebrew", "letters", "notes", "journal", "project", "café", "onyx", "plan"]
        for i in 0..<5000 {
            let name = "\(words[i % 12].capitalized) \(words[(i / 12) % 12]) \(i)"
            entries.append(QuickEntry(path: "F\(i % 40)/Sub \(i % 7)/\(name).md", name: MatchKey(name), folder: MatchKey("F\(i % 40)/Sub \(i % 7)"),
                                      aliases: [], mtime: now, dated: nil))
        }
        let big = QuickIndex(entries: entries)
        let t0 = Date()
        for q in ["h", "he", "heb", "hebr", "hebre", "hebrew", "hebrew l", "hebrew le", "hebrew let"] { _ = big.search(q, now: now) }
        let perKey = Date().timeIntervalSince(t0) / 9
        print("quickmatch: \(Int(perKey * 1000))ms per keystroke over 5000 notes")
        XCTAssertLessThan(perKey, 0.25)
    }
}
