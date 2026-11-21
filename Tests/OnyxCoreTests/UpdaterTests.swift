import XCTest
import Foundation
import Darwin
@testable import OnyxCore

final class UpdaterTests: XCTestCase {
    func testSemverParse() {
        XCTAssertEqual(Semver.parse("v0.1.0"), Semver(0, 1, 0))
        XCTAssertEqual(Semver.parse("0.1.0"), Semver(0, 1, 0))
        XCTAssertEqual(Semver.parse("V1.2.3"), Semver(1, 2, 3))
        XCTAssertEqual(Semver.parse("  v0.1.10 \n"), Semver(0, 1, 10))
        XCTAssertNil(Semver.parse("latest"))
        XCTAssertNil(Semver.parse("v1"))
        XCTAssertNil(Semver.parse("1.2"))
        XCTAssertNil(Semver.parse("1.2.3-beta"))
        XCTAssertNil(Semver.parse("v0.1.0.1"))
        XCTAssertNil(Semver.parse(""))
        XCTAssertNil(Semver.parse("abc"))
    }

    func testSemverOrder() {
        XCTAssertLessThan(Semver(0, 1, 0), Semver(0, 1, 1))
        XCTAssertLessThan(Semver(0, 1, 9), Semver(0, 1, 10))
        XCTAssertLessThan(Semver(0, 1, 9), Semver(0, 2, 0))
        XCTAssertLessThan(Semver(0, 9, 9), Semver(1, 0, 0))
        XCTAssertEqual(Semver.parse("v0.1.0"), Semver.parse("0.1.0"))
        XCTAssertFalse(Semver(0, 1, 1) < Semver(0, 1, 1))
        XCTAssertFalse(Semver(0, 1, 0) > Semver(0, 1, 1))
        XCTAssertGreaterThan(Semver(0, 1, 1), Semver(0, 1, 0))
        XCTAssertEqual(Semver(1, 2, 3).description, "1.2.3")
        XCTAssertEqual(Semver(1, 2, 3).tagged, "v1.2.3")
    }

    func testPickAsset() {
        let v = Semver(0, 1, 1)
        let names = [
            (name: "Onyx-0.1.1-macOS.zip", url: "https://example.com/Onyx-0.1.1-macOS.zip"),
            (name: "Onyx-0.1.1.zip", url: "https://example.com/alt.zip"),
            (name: "notes.txt", url: "https://example.com/notes.txt"),
        ]
        XCTAssertEqual(Updater.pickAsset(names: names, version: v)?.name, "Onyx-0.1.1-macOS.zip")
        let onlyGeneric = [(name: "Onyx-latest.zip", url: "https://example.com/latest.zip")]
        XCTAssertEqual(Updater.pickAsset(names: onlyGeneric, version: v)?.name, "Onyx-latest.zip")
        let macosFirst = [
            (name: "Onyx-nightly-macOS.zip", url: "https://example.com/nightly.zip"),
            (name: "Onyx-nightly.zip", url: "https://example.com/plain.zip"),
        ]
        XCTAssertEqual(Updater.pickAsset(names: macosFirst, version: v)?.name, "Onyx-nightly-macOS.zip")
        XCTAssertNil(Updater.pickAsset(names: [(name: "README.md", url: "https://example.com/r")], version: v))
    }

    func testParseReleaseJSON() throws {
        let json = """
        {
          "tag_name": "v0.1.1",
          "name": "Onyx 0.1.1",
          "body": "Spacing and split panes.",
          "html_url": "https://github.com/kennethreitz/onyx/releases/tag/v0.1.1",
          "assets": [
            {
              "name": "Onyx-0.1.1-macOS.zip",
              "browser_download_url": "https://github.com/kennethreitz/onyx/releases/download/v0.1.1/Onyx-0.1.1-macOS.zip"
            }
          ]
        }
        """.data(using: .utf8)!
        let r = try Updater.parseRelease(json)
        XCTAssertEqual(r.tag, "v0.1.1")
        XCTAssertEqual(r.version, Semver(0, 1, 1))
        XCTAssertEqual(r.name, "Onyx 0.1.1")
        XCTAssertEqual(r.body, "Spacing and split panes.")
        XCTAssertEqual(r.assetName, "Onyx-0.1.1-macOS.zip")
        XCTAssertEqual(r.assetURL.absoluteString, "https://github.com/kennethreitz/onyx/releases/download/v0.1.1/Onyx-0.1.1-macOS.zip")
    }

    func testParseReleaseRejectsDraftPrereleaseAndBadTag() {
        func json(_ extra: String) -> Data {
            """
            {"tag_name":"v0.1.1","assets":[{"name":"Onyx-0.1.1-macOS.zip","browser_download_url":"https://ex/a.zip"}]\(extra)}
            """.data(using: .utf8)!
        }
        XCTAssertThrowsError(try Updater.parseRelease(json(",\"draft\":true"))) { err in
            XCTAssertEqual(err as? UpdateError, .malformedRelease)
        }
        XCTAssertThrowsError(try Updater.parseRelease(json(",\"prerelease\":true"))) { err in
            XCTAssertEqual(err as? UpdateError, .malformedRelease)
        }
        let badTag = """
        {"tag_name":"nightly","assets":[{"name":"Onyx-0.1.1-macOS.zip","browser_download_url":"https://ex/a.zip"}]}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try Updater.parseRelease(badTag)) { err in
            XCTAssertEqual(err as? UpdateError, .malformedRelease)
        }
        let noAsset = """
        {"tag_name":"v0.1.1","assets":[{"name":"notes.txt","browser_download_url":"https://ex/n.txt"}]}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try Updater.parseRelease(noAsset)) { err in
            XCTAssertEqual(err as? UpdateError, .noAsset)
        }
    }

    func testDecisionAndSkip() async throws {
        let root = try Scratch.make()
        defer { Scratch.clean(root) }
        let (proc, port) = try Scratch.serve(root: root, release: Scratch.releaseJSON(version: "0.1.1", port: 0, zipName: "Onyx-0.1.1-macOS.zip"))
        defer { proc.terminate(); _ = proc.wait(timeout: 2) }
        // rewrite JSON with the real port
        try Scratch.writeRelease(root: root, version: "0.1.1", port: port, zipName: "Onyx-0.1.1-macOS.zip")
        try Scratch.waitFor(url: URL(string: "http://127.0.0.1:\(port)/latest.json")!)

        let defaults = Scratch.isolatedDefaults()
        let dest = root.appendingPathComponent("Installed/Onyx.app")
        let updater = Updater(
            apiURL: URL(string: "http://127.0.0.1:\(port)/latest.json")!,
            currentVersion: Semver(0, 1, 0),
            bundleID: Updater.defaultBundleID,
            appURL: dest,
            defaults: defaults
        )
        let available = try await updater.evaluate(respectSkip: true)
        guard case .available(let rel) = available else { return XCTFail("expected available, got \(available)") }
        XCTAssertEqual(rel.version, Semver(0, 1, 1))

        let same = Updater(apiURL: updater.apiURL, currentVersion: Semver(0, 1, 1), bundleID: updater.bundleID,
                           appURL: dest, defaults: defaults)
        let upToDate = try await same.evaluate(respectSkip: true)
        XCTAssertEqual(upToDate, .upToDate)

        let newerRunning = Updater(apiURL: updater.apiURL, currentVersion: Semver(0, 2, 0), bundleID: updater.bundleID,
                                   appURL: dest, defaults: defaults)
        let olderRelease = try await newerRunning.evaluate(respectSkip: true)
        XCTAssertEqual(olderRelease, .upToDate)

        updater.skip(rel)
        let skipped = try await updater.evaluate(respectSkip: true)
        guard case .skipped(let skippedRel) = skipped else { return XCTFail("expected skipped, got \(skipped)") }
        XCTAssertEqual(skippedRel.tag, rel.tag)
        let manual = try await updater.evaluate(respectSkip: false)
        guard case .available = manual else { return XCTFail("manual check should still offer a skipped version") }

        // Isolated defaults must not touch the real suite.
        XCTAssertNil(UserDefaults.standard.string(forKey: UpdatePrefs.skippedVersion))
    }

    func testTranslocatedPath() {
        XCTAssertTrue(Updater.isTranslocated(URL(fileURLWithPath: "/private/var/folders/xx/AppTranslocation/A1B2/d/Onyx.app")))
        XCTAssertFalse(Updater.isTranslocated(URL(fileURLWithPath: "/Applications/Onyx.app")))
        XCTAssertFalse(Updater.isTranslocated(URL(fileURLWithPath: "/Users/kennethreitz/repos/onyx/build/Onyx.app")))
    }

    func testInstallFromLocalRelease() async throws {
        let root = try Scratch.make()
        defer { Scratch.clean(root) }

        let dest = root.appendingPathComponent("Installed/Onyx.app")
        try Scratch.writeFakeApp(at: dest, version: "0.1.0", marker: "old", bundleID: Updater.defaultBundleID)

        let incoming = root.appendingPathComponent("New/Onyx.app")
        try Scratch.writeFakeApp(at: incoming, version: "0.1.1", marker: "new", bundleID: Updater.defaultBundleID)
        try Scratch.setQuarantine(incoming)
        let zip = root.appendingPathComponent("Onyx-0.1.1-macOS.zip")
        try Scratch.zip(app: incoming, to: zip)

        let (proc, port) = try Scratch.serve(root: root, release: nil)
        defer { proc.terminate(); _ = proc.wait(timeout: 2) }
        try Scratch.writeRelease(root: root, version: "0.1.1", port: port, zipName: "Onyx-0.1.1-macOS.zip")
        try Scratch.waitFor(url: URL(string: "http://127.0.0.1:\(port)/latest.json")!)

        let defaults = Scratch.isolatedDefaults()
        let updater = Updater(
            apiURL: URL(string: "http://127.0.0.1:\(port)/latest.json")!,
            currentVersion: Semver(0, 1, 0),
            bundleID: Updater.defaultBundleID,
            appURL: dest,
            defaults: defaults
        )
        let decision = try await updater.evaluate(respectSkip: true)
        guard case .available(let rel) = decision else { return XCTFail("expected available, got \(decision)") }
        try await updater.install(rel)

        XCTAssertEqual(try Scratch.marker(at: dest), "new")
        XCTAssertEqual(Scratch.shortVersion(at: dest), "0.1.1")
        XCTAssertEqual(Bundle(url: dest)?.bundleIdentifier, Updater.defaultBundleID)
        XCTAssertFalse(Scratch.hasQuarantine(dest))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
        // The outgoing app should have been moved aside, not left as a sibling .old bundle.
        let siblings = try FileManager.default.contentsOfDirectory(at: dest.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        XCTAssertEqual(siblings.filter { $0.lastPathComponent.hasPrefix("Onyx.old-") }.count, 0)
        XCTAssertEqual(siblings.filter { $0.lastPathComponent.hasPrefix("Onyx.next-") }.count, 0)
    }

    func testInstallRejectsWrongBundleIDAndLeavesOriginal() async throws {
        let root = try Scratch.make()
        defer { Scratch.clean(root) }
        let dest = root.appendingPathComponent("Installed/Onyx.app")
        try Scratch.writeFakeApp(at: dest, version: "0.1.0", marker: "old", bundleID: Updater.defaultBundleID)
        let incoming = root.appendingPathComponent("Evil/Onyx.app")
        try Scratch.writeFakeApp(at: incoming, version: "0.1.1", marker: "evil", bundleID: "com.example.not-onyx")
        let zip = root.appendingPathComponent("Onyx-0.1.1-macOS.zip")
        try Scratch.zip(app: incoming, to: zip)

        let updater = Updater(
            apiURL: URL(string: "http://127.0.0.1/unused")!,
            currentVersion: Semver(0, 1, 0),
            bundleID: Updater.defaultBundleID,
            appURL: dest,
            defaults: Scratch.isolatedDefaults()
        )
        XCTAssertThrowsError(try updater.install(fromZip: zip)) { err in
            guard let e = err as? UpdateError, case .bundleMismatch(let found, let expected) = e else {
                return XCTFail("expected bundleMismatch, got \(err)")
            }
            XCTAssertEqual(found, "com.example.not-onyx")
            XCTAssertEqual(expected, Updater.defaultBundleID)
        }
        XCTAssertEqual(try Scratch.marker(at: dest), "old")
        XCTAssertEqual(Scratch.shortVersion(at: dest), "0.1.0")
    }

    func testInstallRejectsSameOrOlderVersion() throws {
        let root = try Scratch.make()
        defer { Scratch.clean(root) }
        let dest = root.appendingPathComponent("Installed/Onyx.app")
        try Scratch.writeFakeApp(at: dest, version: "0.1.1", marker: "current", bundleID: Updater.defaultBundleID)
        let incoming = root.appendingPathComponent("New/Onyx.app")
        try Scratch.writeFakeApp(at: incoming, version: "0.1.1", marker: "same", bundleID: Updater.defaultBundleID)
        let zip = root.appendingPathComponent("same.zip")
        try Scratch.zip(app: incoming, to: zip)
        let updater = Updater(
            apiURL: URL(string: "http://127.0.0.1/unused")!,
            currentVersion: Semver(0, 1, 1),
            bundleID: Updater.defaultBundleID,
            appURL: dest,
            defaults: Scratch.isolatedDefaults()
        )
        XCTAssertThrowsError(try updater.install(fromZip: zip)) { err in
            XCTAssertEqual(err as? UpdateError, .notNewer)
        }
        XCTAssertEqual(try Scratch.marker(at: dest), "current")
    }
}

/// Temporary apps, zips, and a loopback GitHub-API stand-in. Everything lives under /tmp, never the real Onyx.app.
private enum Scratch {
    static func make() throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("onyx-update-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: u.appendingPathComponent("Installed"), withIntermediateDirectories: true)
        return u
    }

    static func clean(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func isolatedDefaults() -> UserDefaults {
        let name = "onyx-update-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    static func writeFakeApp(at app: URL, version: String, marker: String, bundleID: String) throws {
        let fm = FileManager.default
        let macOS = app.appendingPathComponent("Contents/MacOS")
        let res = app.appendingPathComponent("Contents/Resources")
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fm.createDirectory(at: res, withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>CFBundleName</key><string>Onyx</string>
          <key>CFBundleIdentifier</key><string>\(bundleID)</string>
          <key>CFBundleExecutable</key><string>Onyx</string>
          <key>CFBundlePackageType</key><string>APPL</string>
          <key>CFBundleShortVersionString</key><string>\(version)</string>
          <key>CFBundleVersion</key><string>\(version)</string>
        </dict>
        </plist>
        """
        try plist.write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true, encoding: .utf8)
        let exe = macOS.appendingPathComponent("Onyx")
        try "#!/bin/sh\necho onyx-fake\n".write(to: exe, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
        try marker.write(to: res.appendingPathComponent("marker.txt"), atomically: true, encoding: .utf8)
    }

    static func marker(at app: URL) throws -> String {
        try String(contentsOf: app.appendingPathComponent("Contents/Resources/marker.txt"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func shortVersion(at app: URL) -> String? {
        Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    static func zip(app: URL, to zip: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", "--keepParent", app.path, zip.path]
        try p.run()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0, "ditto failed to zip \(app.path)")
    }

    static func setQuarantine(_ url: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        p.arguments = ["-w", "com.apple.quarantine", "0081;00000000;UpdaterTests;", url.path]
        try p.run()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0)
    }

    static func hasQuarantine(_ url: URL) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        p.arguments = ["-p", "com.apple.quarantine", url.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    static func releaseJSON(version: String, port: Int, zipName: String) -> String {
        """
        {
          "tag_name": "v\(version)",
          "name": "v\(version)",
          "body": "Test release \(version).",
          "html_url": "http://127.0.0.1:\(port)/release",
          "assets": [
            {
              "name": "\(zipName)",
              "browser_download_url": "http://127.0.0.1:\(port)/\(zipName)",
              "content_type": "application/zip"
            }
          ]
        }
        """
    }

    static func writeRelease(root: URL, version: String, port: Int, zipName: String) throws {
        try releaseJSON(version: version, port: port, zipName: zipName)
            .write(to: root.appendingPathComponent("latest.json"), atomically: true, encoding: .utf8)
    }

    static func serve(root: URL, release: String?) throws -> (Process, Int) {
        if let release {
            try release.write(to: root.appendingPathComponent("latest.json"), atomically: true, encoding: .utf8)
        }
        let port = try freePort()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = ["-m", "http.server", "\(port)", "--bind", "127.0.0.1", "--directory", root.path]
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        return (p, port)
    }

    static func waitFor(url: URL, tries: Int = 40) throws {
        var last: Error?
        for _ in 0..<tries {
            do {
                _ = try Data(contentsOf: url)
                return
            } catch {
                last = error
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        throw last ?? URLError(.cannotConnectToHost)
    }

    static func freePort() throws -> Int {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { throw URLError(.cannotCreateFile) }
        defer { close(sock) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        addr.sin_port = 0
        let bindRes = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bindRes == 0 else { throw URLError(.cannotConnectToHost) }
        var got = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameRes = withUnsafeMutablePointer(to: &got) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(sock, $0, &len) }
        }
        guard nameRes == 0 else { throw URLError(.cannotConnectToHost) }
        return Int(UInt16(bigEndian: got.sin_port))
    }
}

private extension Process {
    func wait(timeout seconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if isRunning { terminate() }
        waitUntilExit()
        return !isRunning
    }
}
