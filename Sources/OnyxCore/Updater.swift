import Foundation

/// Semantic version `MAJOR.MINOR.PATCH`, as used in GitHub tags (`v0.1.1`) and `CFBundleShortVersionString`.
public struct Semver: Comparable, Equatable, Hashable, CustomStringConvertible {
    public var major, minor, patch: Int

    public init(_ major: Int, _ minor: Int, _ patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Accepts `1.2.3` or `v1.2.3`. Pre-release suffixes and other shapes return nil.
    public static func parse(_ raw: String) -> Semver? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.first == "v" || s.first == "V" { s.removeFirst() }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]),
              major >= 0, minor >= 0, patch >= 0
        else { return nil }
        return Semver(major, minor, patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }
    public var tagged: String { "v\(description)" }

    public static func < (l: Semver, r: Semver) -> Bool {
        if l.major != r.major { return l.major < r.major }
        if l.minor != r.minor { return l.minor < r.minor }
        return l.patch < r.patch
    }
}

public enum UpdatePrefs {
    public static let automatic = "onyx.updates.automatic"
    public static let skippedVersion = "onyx.updates.skippedVersion"
    public static let lastCheck = "onyx.updates.lastCheck"

    public static func automaticEnabled(_ d: UserDefaults = .standard) -> Bool {
        d.object(forKey: automatic) as? Bool ?? true
    }
}

public struct GitHubRelease: Equatable {
    public var tag: String
    public var version: Semver
    public var name: String
    public var body: String
    public var htmlURL: URL?
    public var assetName: String
    public var assetURL: URL

    public init(tag: String, version: Semver, name: String, body: String, htmlURL: URL?, assetName: String, assetURL: URL) {
        self.tag = tag
        self.version = version
        self.name = name
        self.body = body
        self.htmlURL = htmlURL
        self.assetName = assetName
        self.assetURL = assetURL
    }
}

public enum UpdateDecision: Equatable {
    case upToDate
    case available(GitHubRelease)
    case skipped(GitHubRelease)
    case noAsset
}

public enum UpdateError: Error, Equatable, LocalizedError {
    case badURL
    case httpStatus(Int)
    case malformedRelease
    case noAsset
    case bundleMismatch(found: String?, expected: String)
    case notNewer
    case translocated
    case unsupportedPlatform
    case notAnApp
    case notWritable
    case dittoFailed(Int32)
    case downloadFailed
    case missingExecutable

    public var errorDescription: String? {
        switch self {
        case .badURL: return "The update address is not valid."
        case .httpStatus(let c): return "GitHub returned status \(c)."
        case .malformedRelease: return "The release information was not readable."
        case .noAsset: return "That release has no macOS download."
        case .bundleMismatch: return "The download is not an Onyx app (bundle id did not match)."
        case .notNewer: return "The download is not newer than the app that’s running."
        case .translocated: return "Onyx is running from a temporary copy (for example, opened from Downloads). Move it to Applications and open it from there, then update."
        case .unsupportedPlatform: return "Installing a macOS update is not available on this platform."
        case .notAnApp: return "The download did not contain an Onyx app."
        case .notWritable: return "Onyx can’t replace this app. Check that you have permission to write to it."
        case .dittoFailed: return "The update archive could not be unpacked."
        case .downloadFailed: return "The update could not be downloaded."
        case .missingExecutable: return "The download is missing its executable."
        }
    }
}

/// Looks up the latest GitHub Release and can replace a local `.app` with its macOS zip.
/// No Sparkle, no appcast: the API URL is `https://api.github.com/repos/kennethreitz/onyx/releases/latest`
/// unless `ONYX_UPDATE_API_URL` points somewhere else (tests use a local server).
public final class Updater {
    public static let defaultAPI = URL(string: "https://api.github.com/repos/kennethreitz/onyx/releases/latest")!
    public static let defaultBundleID = "org.kennethreitz.onyx"

    public var apiURL: URL
    public var currentVersion: Semver
    public var bundleID: String
    public var appURL: URL
    public var userAgent: String
    public var session: URLSession
    public var defaults: UserDefaults

    public init(apiURL: URL, currentVersion: Semver, bundleID: String, appURL: URL,
                userAgent: String? = nil, session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.apiURL = apiURL
        self.currentVersion = currentVersion
        self.bundleID = bundleID
        self.appURL = appURL
        self.userAgent = userAgent ?? "Onyx/\(currentVersion) (https://github.com/kennethreitz/onyx)"
        self.session = session
        self.defaults = defaults
    }

    /// Built from the running bundle. Env overrides: `ONYX_UPDATE_API_URL`, `ONYX_UPDATE_VERSION`, `ONYX_UPDATE_APP`.
    /// Returns nil when the short version can’t be parsed or the running binary isn’t inside an `.app`
    /// (and no `ONYX_UPDATE_APP` was given) — `swift run` and other unpackaged builds are left alone.
    public static func live() -> Updater? {
        let env = ProcessInfo.processInfo.environment
        let api = env["ONYX_UPDATE_API_URL"].flatMap(URL.init(string:)) ?? defaultAPI
        let verStr = env["ONYX_UPDATE_VERSION"]
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        guard let ver = verStr.flatMap(Semver.parse) else { return nil }
        let app: URL
        if let p = env["ONYX_UPDATE_APP"], !p.isEmpty {
            app = URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
        } else {
            app = Bundle.main.bundleURL
            guard app.pathExtension == "app" else { return nil }
        }
        let id = Bundle.main.bundleIdentifier ?? defaultBundleID
        return Updater(apiURL: api, currentVersion: ver, bundleID: id, appURL: app)
    }

    public static func isTranslocated(_ url: URL) -> Bool {
        url.standardizedFileURL.path.contains("/AppTranslocation/")
    }

    /// Prefer `Onyx-<ver>-macOS.zip`, then any `Onyx-*-macOS.zip`, then any `Onyx-*.zip`.
    public static func pickAsset(names: [(name: String, url: String)], version: Semver) -> (name: String, url: URL)? {
        func url(_ s: String) -> URL? { URL(string: s) }
        let zips = names.filter { $0.name.lowercased().hasSuffix(".zip") }
        let exact = "Onyx-\(version)-macOS.zip"
        if let a = zips.first(where: { $0.name == exact }), let u = url(a.url) { return (a.name, u) }
        if let a = zips.first(where: { $0.name.hasPrefix("Onyx-") && $0.name.hasSuffix("-macOS.zip") }), let u = url(a.url) {
            return (a.name, u)
        }
        if let a = zips.first(where: { $0.name.hasPrefix("Onyx-") }), let u = url(a.url) { return (a.name, u) }
        if let a = zips.first, let u = url(a.url) { return (a.name, u) }
        return nil
    }

    public func fetchLatest() async throws -> GitHubRelease {
        var req = URLRequest(url: apiURL)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.timeoutInterval = 30
        let (data, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard code == 200 else { throw UpdateError.httpStatus(code) }
        defaults.set(Date().timeIntervalSince1970, forKey: UpdatePrefs.lastCheck)
        return try Self.parseRelease(data)
    }

    public static func parseRelease(_ data: Data) throws -> GitHubRelease {
        let obj = try JSONDecoder().decode(GHRelease.self, from: data)
        if obj.draft == true || obj.prerelease == true { throw UpdateError.malformedRelease }
        guard let version = Semver.parse(obj.tag_name) else { throw UpdateError.malformedRelease }
        let assets = (obj.assets ?? []).map { (name: $0.name, url: $0.browser_download_url) }
        guard let asset = pickAsset(names: assets, version: version) else { throw UpdateError.noAsset }
        return GitHubRelease(
            tag: obj.tag_name,
            version: version,
            name: obj.name?.isEmpty == false ? obj.name! : obj.tag_name,
            body: obj.body ?? "",
            htmlURL: obj.html_url.flatMap(URL.init(string:)),
            assetName: asset.name,
            assetURL: asset.url
        )
    }

    public func evaluate(respectSkip: Bool) async throws -> UpdateDecision {
        let release: GitHubRelease
        do {
            release = try await fetchLatest()
        } catch UpdateError.noAsset {
            return .noAsset
        }
        if release.version <= currentVersion { return .upToDate }
        if respectSkip {
            let skipped = defaults.string(forKey: UpdatePrefs.skippedVersion)
            if skipped == release.tag || skipped == release.version.description { return .skipped(release) }
        }
        return .available(release)
    }

    public func skip(_ release: GitHubRelease) {
        defaults.set(release.tag, forKey: UpdatePrefs.skippedVersion)
    }

    /// Download the zip, unpack it with ditto, verify the bundle, and replace `appURL`. Does not relaunch.
    public func install(_ release: GitHubRelease, progress: ((String) -> Void)? = nil) async throws {
        #if !os(macOS)
        throw UpdateError.unsupportedPlatform
        #else
        if Self.isTranslocated(appURL) { throw UpdateError.translocated }
        try assertWritable()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("onyx-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        progress?("Downloading…")
        let zip = try await download(release.assetURL, to: dir.appendingPathComponent(release.assetName))
        progress?("Installing…")
        try install(fromZip: zip)
        #endif
    }

    /// Unpack a local zip (the same format as the GitHub asset) and replace `appURL`.
    public func install(fromZip zip: URL) throws {
        #if !os(macOS)
        throw UpdateError.unsupportedPlatform
        #else
        if Self.isTranslocated(appURL) { throw UpdateError.translocated }
        try assertWritable()
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("onyx-unpack-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let status = try run("/usr/bin/ditto", ["-x", "-k", zip.path, dir.path])
        guard status == 0 else { throw UpdateError.dittoFailed(status) }
        guard let incoming = findApp(in: dir) else { throw UpdateError.notAnApp }
        try verify(incoming)
        try stripQuarantine(incoming)
        try replaceApp(new: incoming, dest: appURL)
        #endif
    }

    func assertWritable() throws {
        let fm = FileManager.default
        let dest = appURL
        let parent = dest.deletingLastPathComponent()
        let parentOK = fm.isWritableFile(atPath: parent.path)
        let destOK = !fm.fileExists(atPath: dest.path) || fm.isWritableFile(atPath: dest.path)
        guard parentOK, destOK else { throw UpdateError.notWritable }
    }

    func download(_ url: URL, to dest: URL) async throws -> URL {
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 120
        let (location, response) = try await session.download(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else { throw UpdateError.httpStatus(code) }
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.moveItem(at: location, to: dest)
        return dest
    }

    func verify(_ app: URL) throws {
        guard app.pathExtension == "app", let bundle = Bundle(url: app) else { throw UpdateError.notAnApp }
        let found = bundle.bundleIdentifier
        guard found == bundleID else { throw UpdateError.bundleMismatch(found: found, expected: bundleID) }
        guard let exe = bundle.executableURL, FileManager.default.isExecutableFile(atPath: exe.path) else {
            throw UpdateError.missingExecutable
        }
        let verStr = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard let ver = verStr.flatMap(Semver.parse), ver > currentVersion else { throw UpdateError.notNewer }
    }

    func findApp(in root: URL) -> URL? {
        let fm = FileManager.default
        if root.pathExtension == "app" { return root }
        let kids = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        if let direct = kids.first(where: { $0.pathExtension == "app" }) { return direct }
        for item in kids where item.hasDirectoryPath && item.pathExtension != "app" {
            if let found = findApp(in: item) { return found }
        }
        return nil
    }

    func stripQuarantine(_ url: URL) throws {
        // xattr returns non-zero when the attribute is already absent; that's fine.
        _ = try run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", url.path])
    }

    /// Move the running app aside, then move the new one into its place, staging onto the destination volume first.
    func replaceApp(new: URL, dest: URL) throws {
        let fm = FileManager.default
        let token = UUID().uuidString
        let parent = dest.deletingLastPathComponent()
        let staging = parent.appendingPathComponent("Onyx.next-\(token).app")
        let outgoing = parent.appendingPathComponent("Onyx.old-\(token).app")
        if deviceID(new) == deviceID(parent), deviceID(new) != nil {
            try fm.moveItem(at: new, to: staging)
        } else {
            try fm.copyItem(at: new, to: staging)
        }
        try stripQuarantine(staging)
        if fm.fileExists(atPath: dest.path) {
            try fm.moveItem(at: dest, to: outgoing)
        }
        do {
            try fm.moveItem(at: staging, to: dest)
        } catch {
            if fm.fileExists(atPath: outgoing.path) { try? fm.moveItem(at: outgoing, to: dest) }
            try? fm.removeItem(at: staging)
            throw error
        }
        if fm.fileExists(atPath: outgoing.path) {
            _ = try? fm.trashItem(at: outgoing, resultingItemURL: nil)
            if fm.fileExists(atPath: outgoing.path) { try? fm.removeItem(at: outgoing) }
        }
    }

    func deviceID(_ url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.systemNumber] as? NSNumber)?.intValue
    }

    @discardableResult
    func run(_ path: String, _ args: [String]) throws -> Int32 {
        #if os(macOS)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        return p.terminationStatus
        #else
        throw UpdateError.unsupportedPlatform
        #endif
    }

    private struct GHRelease: Decodable {
        var tag_name: String
        var name: String?
        var body: String?
        var html_url: String?
        var draft: Bool?
        var prerelease: Bool?
        var assets: [GHAsset]?
    }
    private struct GHAsset: Decodable {
        var name: String
        var browser_download_url: String
    }
}
