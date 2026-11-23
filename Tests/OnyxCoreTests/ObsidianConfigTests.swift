import XCTest
@testable import OnyxCore

final class ObsidianConfigTests: XCTestCase {
    let kenneth = """
    {
      "alwaysUpdateLinks": true,
      "promptDelete": false,
      "defaultViewMode": "preview",
      "livePreview": false,
      "userIgnoreFilters": [
        ".scripts"
      ],
      "pluginThing": {"z": 1, "a": [1, 2], "url": "https://x/y"}
    }
    """

    func testRoundTripKeepsUnknownKeysOrderAndText() throws {
        let out = try XCTUnwrap(ObsidianConfig.updatedText(original: kenneth, changes: ["attachmentFolderPath": "./assets"]))
        XCTAssertEqual(out, """
        {
          "alwaysUpdateLinks": true,
          "promptDelete": false,
          "defaultViewMode": "preview",
          "livePreview": false,
          "userIgnoreFilters": [
            ".scripts"
          ],
          "pluginThing": {"z": 1, "a": [1, 2], "url": "https://x/y"},
          "attachmentFolderPath": "./assets"
        }
        """)
        let parsed = try XCTUnwrap(ObsidianConfig.parse(Data(out.utf8)))
        XCTAssertEqual(parsed["attachmentFolderPath"] as? String, "./assets")
        XCTAssertEqual(parsed["userIgnoreFilters"] as? [String], [".scripts"])
    }

    func testChangeInPlaceAndRemove() throws {
        let out = try XCTUnwrap(ObsidianConfig.updatedText(original: kenneth, changes: ["promptDelete": true, "livePreview": nil]))
        XCTAssertTrue(out.contains("\"promptDelete\": true,\n  \"defaultViewMode\""))
        XCTAssertFalse(out.contains("livePreview"))
        XCTAssertNotNil(ObsidianConfig.parse(Data(out.utf8)))
    }

    func testNoWriteWhenUnchanged() throws {
        XCTAssertNil(try ObsidianConfig.updatedText(original: kenneth, changes: ["defaultViewMode": "preview", "alwaysUpdateLinks": true, "missing": nil]))
        XCTAssertNil(try ObsidianConfig.updatedText(original: kenneth, changes: ["userIgnoreFilters": [".scripts"]]))
        XCTAssertNotNil(try ObsidianConfig.updatedText(original: kenneth, changes: ["alwaysUpdateLinks": false]))
    }

    func testCreatesAndRefusesInvalid() throws {
        XCTAssertEqual(try ObsidianConfig.updatedText(original: nil, changes: ["folder": "Daily", "autorun": false]),
                       "{\n  \"autorun\": false,\n  \"folder\": \"Daily\"\n}")
        XCTAssertThrowsError(try ObsidianConfig.updatedText(original: "[1,2]", changes: ["a": 1]))
        XCTAssertThrowsError(try ObsidianConfig.updatedText(original: "{ \"a\": ", changes: ["a": 1]))
        let nested = try XCTUnwrap(ObsidianConfig.updatedText(original: "{}", changes: ["userIgnoreFilters": ["A/", "B \"q\""]]))
        XCTAssertEqual(nested, "{\n  \"userIgnoreFilters\": [\n    \"A/\",\n    \"B \\\"q\\\"\"\n  ]\n}")
    }

    func testAtomicFileUpdate() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("onyx-config-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(".obsidian/daily-notes.json")
        XCTAssertTrue(try ObsidianConfig.update(url, changes: ["folder": "Journal"]))
        XCTAssertFalse(try ObsidianConfig.update(url, changes: ["folder": "Journal"]))
        XCTAssertTrue(try ObsidianConfig.update(url, changes: ["autorun": true]))
        let d = DailyNotes.Settings(json: ObsidianConfig.parse(try Data(contentsOf: url)))
        XCTAssertEqual(d, DailyNotes.Settings(format: "YYYY-MM-DD", folder: "Journal", template: "", autorun: true))
    }

    func testAttachmentLocation() {
        for (s, k) in [(nil, AttachmentLocation.vaultRoot), ("/", .vaultRoot), ("./", .sameFolder),
                       ("./assets", .subfolder("assets")), ("Attachments/", .folder("Attachments"))] as [(String?, AttachmentLocation)] {
            XCTAssertEqual(AttachmentLocation(setting: s), k)
        }
        XCTAssertEqual(AttachmentLocation.subfolder("assets").setting, "./assets")
        XCTAssertEqual(AttachmentLocation.folder("Files/Media").setting, "Files/Media")
        XCTAssertEqual(AttachmentLocation.vaultRoot.setting, "/")
        // the setting resolves the same way the drop code does
        XCTAssertEqual(AudioNote.attachmentFolder(setting: AttachmentLocation.subfolder("a").setting, notePath: "N/x.md"), "N/a")
    }

    func testNewNoteLocation() {
        XCTAssertEqual(NewNoteLocation.folder(location: nil, folderPath: nil, contextual: "Here"), "Here")
        XCTAssertEqual(NewNoteLocation.folder(location: "current", folderPath: "Inbox", contextual: "Here"), "Here")
        XCTAssertEqual(NewNoteLocation.folder(location: "root", folderPath: "Inbox", contextual: "Here"), "")
        XCTAssertEqual(NewNoteLocation.folder(location: "folder", folderPath: "/Inbox/", contextual: "Here"), "Inbox")
    }

    func testVaultPathCheck() {
        XCTAssertEqual(VaultPathCheck.check(""), .empty)
        XCTAssertEqual(VaultPathCheck.check("Daily"), .ok)
        XCTAssertEqual(VaultPathCheck.check("../Elsewhere"), .outsideVault)
        XCTAssertEqual(VaultPathCheck.check("~/x"), .outsideVault)
        XCTAssertEqual(VaultPathCheck.check("A:B"), .invalidCharacters)
    }

    func testMomentFormat() {
        let tz = TimeZone(identifier: "America/New_York")!
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 23; c.hour = 8; c.minute = 5
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let d = cal.date(from: c)!
        XCTAssertEqual(MomentFormat.format(d, "YYYY-MM-DD", timeZone: tz), "2026-11-23")
        XCTAssertEqual(MomentFormat.format(d, "dddd, MMMM Do YYYY", timeZone: tz), "Monday, November 23rd 2026")
        XCTAssertEqual(MomentFormat.format(d, "YYYY/MM/[Week] ww", timeZone: tz), "2026/11/Week 48")
        XCTAssertEqual(MomentFormat.format(d, "HH:mm", timeZone: tz), "08:05")
        XCTAssertEqual(MomentFormat.format(d, "h:mm A", timeZone: tz), "8:05 AM")
        XCTAssertEqual(MomentFormat.format(d, "ddd D MMM YY", timeZone: tz), "Mon 23 Nov 26")
        XCTAssertNotNil(MomentFormat.parse("2026-11-23", "YYYY-MM-DD", timeZone: tz))
        XCTAssertNil(MomentFormat.parse("2026-11-3", "YYYY-MM-DD", timeZone: tz))
        XCTAssertNil(MomentFormat.parse("Untitled", "YYYY-MM-DD", timeZone: tz))
        XCTAssertNotNil(MomentFormat.parse("2026/11/[x] 23", "YYYY/MM/[[x]] DD", timeZone: tz) ?? MomentFormat.parse("2026/11/23", "YYYY/MM/DD", timeZone: tz))
        XCTAssertNil(MomentFormat.icuPattern("MMMM Do"))
    }

    func testDailyPathsAndDates() {
        let s = DailyNotes.Settings(format: "YYYY/MM/YYYY-MM-DD", folder: "Journal")
        let d = DailyNotes.date(ofPath: "Journal/2026/11/2026-11-23.md", settings: s)
        XCTAssertNotNil(d)
        XCTAssertEqual(DailyNotes.path(for: d!, settings: s), "Journal/2026/11/2026-11-23.md")
        XCTAssertNil(DailyNotes.date(ofPath: "Other/2026-11-23.md", settings: s))
        let root = DailyNotes.Settings(folder: "")
        XCTAssertNotNil(DailyNotes.date(ofPath: "2026-11-23.md", settings: root))
        XCTAssertNil(DailyNotes.date(ofPath: "Notes/2026-11-23.md", settings: root))
        XCTAssertEqual(DailyNotes.Settings(json: ["format": "", "template": "Templates/Daily"]).format, "YYYY-MM-DD")
        XCTAssertEqual(DailyNotes.Settings(json: ["template": "Templates/Daily"]).templatePath, "Templates/Daily.md")
        XCTAssertNil(DailyNotes.Settings(json: ["template": ""]).templatePath)
    }

    func testTemplateExpansion() {
        let tz = TimeZone.current
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let d = cal.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 9))!
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 14, minute: 30))!
        let out = DailyNotes.expand(template: "# {{title}}\n{{date:dddd, MMMM D}} at {{time}} / {{ time:h A }} {{DATE}}",
                                    date: d, title: "2026-11-23", dateFormat: "YYYY-MM-DD", now: now)
        XCTAssertEqual(out, "# 2026-11-23\nMonday, November 23 at 14:30 / 2 PM 2026-11-23")
        XCTAssertEqual(DailyNotes.expand(template: "plain", date: d, title: "t", dateFormat: "YYYY"), "plain")
    }

    func testTemplateSettingsDefaults() {
        XCTAssertEqual(TemplateSettings(json: nil), TemplateSettings())
        XCTAssertEqual(TemplateSettings(json: ["folder": "Templates/", "dateFormat": "DD.MM.YYYY", "timeFormat": ""]),
                       TemplateSettings(folder: "Templates", dateFormat: "DD.MM.YYYY", timeFormat: "HH:mm"))
    }
}
