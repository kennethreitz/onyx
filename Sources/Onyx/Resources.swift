import AppKit
import CoreText

/// Finds Onyx's bundled resources: Contents/Resources/OnyxResources in the
/// built .app, or the repo's Resources/ folder when run with `swift run`.
enum AppResources {
    static let root: URL = {
        if let r = Bundle.main.resourceURL?.appendingPathComponent("OnyxResources"), FileManager.default.fileExists(atPath: r.path) { return r }
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")
        return repo
    }()
    static var web: URL { root.appendingPathComponent("web") }
    static var fonts: URL { root.appendingPathComponent("fonts") }

    static func registerFonts() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: fonts, includingPropertiesForKeys: nil) else { return }
        let urls = files.filter { $0.pathExtension == "woff2" }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, false, nil)
    }
}
