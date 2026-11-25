import XCTest
@testable import OnyxCore

final class BookmarksTests: XCTestCase {
    let sample = """
    {
      "items": [
        {
          "type": "file",
          "ctime": 1700000000000,
          "path": "Projects/Onyx.md"
        },
        {
          "type": "folder",
          "ctime": 1700000000001,
          "path": "Projects",
          "title": "Work"
        },
        {
          "type": "group",
          "ctime": 1700000000002,
          "title": "Reading",
          "color": "red",
          "items": [
            {
              "type": "file",
              "ctime": 1700000000003,
              "path": "Notes/Essay.md",
              "subpath": "#Intro",
              "pluginFlag": true
            },
            {
              "type": "search",
              "ctime": 1700000000004,
              "query": "tag:#later",
              "title": "Later"
            }
          ]
        },
        {
          "type": "url",
          "ctime": 1700000000005,
          "url": "https://example.com",
          "title": "Example"
        },
        {
          "type": "graph",
          "ctime": 1700000000006,
          "title": "Atlas",
          "options": {"search": "class:Index", "showTags": false}
        },
        {
          "type": "future-type",
          "ctime": 1700000000007,
          "mystery": {"keep": 1, "url": "https://x/y"}
        }
      ],
      "newTopLevel": 3
    }
    """

    func store(_ json: String? = nil) -> BookmarkStore {
        BookmarkStore.parse(data: Data((json ?? sample).utf8))!
    }

    func json(_ store: BookmarkStore) -> [String: Any] {
        store.jsonObject
    }

    func testParseKindsAndUnknownFields() {
        let s = store()
        XCTAssertEqual(s.items.count, 6)
        XCTAssertEqual(s.extras["newTopLevel"] as? Int, 3)
        XCTAssertEqual(s.items[0].type, "file")
        XCTAssertEqual(s.items[0].path, "Projects/Onyx.md")
        XCTAssertNil(s.items[0].subpath)
        XCTAssertEqual(s.items[1].type, "folder")
        XCTAssertEqual(s.items[1].title, "Work")
        XCTAssertEqual(s.items[1].displayTitle, "Work")
        let group = s.items[2]
        XCTAssertEqual(group.type, "group")
        XCTAssertEqual(group.title, "Reading")
        XCTAssertEqual(group.extras["color"] as? String, "red")
        XCTAssertEqual(group.items?.count, 2)
        let heading = group.items![0]
        XCTAssertEqual(heading.subpath, "#Intro")
        XCTAssertEqual(heading.displayTitle, "Essay › Intro")
        XCTAssertEqual(heading.extras["pluginFlag"] as? Bool, true)
        XCTAssertEqual(group.items![1].query, "tag:#later")
        XCTAssertEqual(s.items[3].url, "https://example.com")
        XCTAssertEqual(s.items[4].type, "graph")
        XCTAssertEqual(s.items[5].type, "future-type")
        XCTAssertEqual((s.items[5].extras["mystery"] as? [String: Any])?["keep"] as? Int, 1)
        XCTAssertTrue(s.containsFile(path: "Projects/Onyx.md"))
        XCTAssertTrue(s.containsFile(path: "Notes/Essay.md", subpath: "Intro"))
        XCTAssertFalse(s.containsFile(path: "Notes/Essay.md"))
        XCTAssertTrue(s.containsFolder(path: "Projects"))
    }

    func testRoundTripPreservesUnknownFieldsAndGroups() throws {
        let original = store()
        let data = try JSONSerialization.data(withJSONObject: original.jsonObject)
        let again = try XCTUnwrap(BookmarkStore.parse(data: data))
        XCTAssertEqual(again.items.count, 6)
        XCTAssertEqual(again.extras["newTopLevel"] as? Int, 3)
        XCTAssertEqual(again.items[2].extras["color"] as? String, "red")
        XCTAssertEqual(again.items[2].items?[0].extras["pluginFlag"] as? Bool, true)
        XCTAssertEqual(again.items[2].items?[0].subpath, "#Intro")
        XCTAssertEqual(again.items[5].type, "future-type")
        let mystery = again.items[5].extras["mystery"] as? [String: Any]
        XCTAssertEqual(mystery?["keep"] as? Int, 1)
        XCTAssertEqual(mystery?["url"] as? String, "https://x/y")
        let opts = again.items[4].options as? [String: Any]
        XCTAssertEqual(opts?["search"] as? String, "class:Index")
        XCTAssertEqual(opts?["showTags"] as? Bool, false)
        // rewriting items through ObsidianConfig keeps the unknown top-level key.
        // A no-op write (nil) means the round-trip was already semantically equal.
        let text = try ObsidianConfig.updatedText(original: sample, changes: ["items": again.itemsJSON]) ?? sample
        let reparsed = try XCTUnwrap(ObsidianConfig.parse(Data(text.utf8)))
        XCTAssertEqual(reparsed["newTopLevel"] as? Int, 3)
        let items = try XCTUnwrap(reparsed["items"] as? [[String: Any]])
        XCTAssertEqual(items.count, 6)
        XCTAssertEqual(items[2]["color"] as? String, "red")
        XCTAssertEqual(items[5]["type"] as? String, "future-type")
    }

    func testInvalidJSONIsRefused() {
        XCTAssertNil(BookmarkStore.parse(data: Data("{".utf8)))
        XCTAssertNil(BookmarkStore.parse(data: Data("[1,2]".utf8)))
        XCTAssertEqual(BookmarkStore.parse(data: nil)?.items.count, 0)
        XCTAssertEqual(BookmarkStore.parse(data: Data())?.items.count, 0)
    }

    func testToggleFileAndFolder() {
        var s = BookmarkStore()
        XCTAssertTrue(s.toggleFile(path: "A.md", now: 1))
        XCTAssertTrue(s.containsFile(path: "A.md"))
        XCTAssertEqual(s.items[0].ctime, 1)
        XCTAssertFalse(s.toggleFile(path: "A.md", now: 2))
        XCTAssertTrue(s.items.isEmpty)
        XCTAssertTrue(s.toggleFolder(path: "Projects", now: 3))
        XCTAssertTrue(s.containsFolder(path: "Projects"))
        XCTAssertFalse(s.toggleFolder(path: "Projects", now: 4))
        XCTAssertTrue(s.items.isEmpty)
        // heading is distinct from the note itself
        XCTAssertTrue(s.toggleFile(path: "A.md", subpath: "#H", now: 5))
        XCTAssertFalse(s.containsFile(path: "A.md"))
        XCTAssertTrue(s.containsFile(path: "A.md", subpath: "#H"))
        XCTAssertTrue(s.toggleFile(path: "A.md", now: 6))
        XCTAssertEqual(s.items.count, 2)
        XCTAssertFalse(s.toggleFile(path: "A.md", subpath: "H", now: 7))
        XCTAssertTrue(s.containsFile(path: "A.md"))
    }

    func testToggleRemovesFromGroup() {
        var s = store()
        XCTAssertFalse(s.toggleFile(path: "Notes/Essay.md", subpath: "#Intro", now: 9))
        XCTAssertEqual(s.items[2].items?.count, 1)
        XCTAssertEqual(s.items[2].items?[0].type, "search")
        XCTAssertEqual(s.items[2].extras["color"] as? String, "red")
    }

    func testMoveAndRefuseDropIntoSelf() {
        var s = store()
        let fileID = s.items[0].id
        let folderID = s.items[1].id
        let groupID = s.items[2].id
        let headingID = s.items[2].items![0].id
        let searchID = s.items[2].items![1].id
        s.move(id: folderID, parent: nil, before: fileID)
        XCTAssertEqual(s.items.map(\.type), ["folder", "file", "group", "url", "graph", "future-type"])
        s.move(id: fileID, parent: groupID, before: searchID)
        XCTAssertEqual(s.items.map(\.type), ["folder", "group", "url", "graph", "future-type"])
        // group was [heading, search]; file inserted before search
        XCTAssertEqual(s.items[1].items?.map(\.type), ["file", "file", "search"])
        XCTAssertEqual(s.items[1].items?[0].path, "Notes/Essay.md")
        XCTAssertEqual(s.items[1].items?[1].path, "Projects/Onyx.md")
        // cannot drop a group into one of its own descendants
        s.move(id: groupID, parent: headingID, before: nil)
        XCTAssertTrue(s.items.contains(where: { $0.id == groupID }))
        XCTAssertNil(s.item(id: headingID)?.items)
        XCTAssertEqual(s.item(id: groupID)?.type, "group")
    }

    func testRemapPathsFollowsFolderMoves() {
        var s = store()
        XCTAssertTrue(s.remapPaths(["Projects/Onyx.md": "Work/Onyx.md", "Projects": "Work", "Notes/Essay.md": "Notes/Essay.md"]))
        XCTAssertTrue(s.containsFile(path: "Work/Onyx.md"))
        XCTAssertTrue(s.containsFolder(path: "Work"))
        XCTAssertTrue(s.containsFile(path: "Notes/Essay.md", subpath: "#Intro"))
        // prefix: a folder bookmark under a moved parent
        var t = BookmarkStore(items: [.file(path: "A/B/C.md", subpath: "#H", ctime: 1), .folder(path: "A/B", ctime: 2)])
        XCTAssertTrue(t.remapPaths(["A": "Z"]))
        XCTAssertTrue(t.containsFile(path: "Z/B/C.md", subpath: "#H"))
        XCTAssertTrue(t.containsFolder(path: "Z/B"))
    }

    func testMigrateAppendsMissingUserDefaultPaths() {
        var s = store()
        XCTAssertTrue(BookmarkStore.migrate(paths: ["Projects/Onyx.md", "New.md", ""], into: &s, now: 42))
        XCTAssertTrue(s.containsFile(path: "New.md"))
        XCTAssertEqual(s.items.last?.ctime, 42)
        // already present, including the one we just added
        XCTAssertFalse(BookmarkStore.migrate(paths: ["Projects/Onyx.md", "New.md"], into: &s, now: 43))
        XCTAssertEqual(s.items.filter { $0.path == "New.md" }.count, 1)
    }

    func testSubpathNormalizeAndResolve() {
        XCTAssertEqual(BookmarkSubpath.normalize(nil), nil)
        XCTAssertEqual(BookmarkSubpath.normalize("  "), nil)
        XCTAssertEqual(BookmarkSubpath.normalize("#"), nil)
        XCTAssertEqual(BookmarkSubpath.normalize("Intro"), "#Intro")
        XCTAssertEqual(BookmarkSubpath.normalize("#Intro"), "#Intro")
        XCTAssertEqual(BookmarkSubpath.normalize("^abc"), "#^abc")
        XCTAssertEqual(BookmarkSubpath.headingName("#Intro"), "Intro")
        XCTAssertNil(BookmarkSubpath.headingName("#^abc"))
        XCTAssertEqual(BookmarkSubpath.blockID("#^abc"), "abc")
        XCTAssertNil(BookmarkSubpath.blockID("#Intro"))
        let text = """
        # Title

        A paragraph ^blk

        ## Next
        """
        let headings = NoteParser.parseHeadings(text)
        XCTAssertEqual(BookmarkSubpath.line(subpath: "#Title", text: text, headings: headings), 0)
        XCTAssertEqual(BookmarkSubpath.line(subpath: "next", text: text, headings: headings), 4)
        XCTAssertEqual(BookmarkSubpath.line(subpath: "#^blk", text: text, headings: headings), 2)
        XCTAssertNil(BookmarkSubpath.line(subpath: "#^nope", text: text, headings: headings))
    }

    func testWatchedConfigIncludesBookmarks() {
        XCTAssertTrue(ObsidianConfig.watchedFiles.contains("bookmarks.json"))
    }
}
