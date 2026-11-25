import XCTest
@testable import OnyxCore

final class TypesetSettingsTests: XCTestCase {
    func testNormalizedFace() {
        XCTAssertEqual(TypesetSettings.normalizedFace(nil), "lm")
        XCTAssertEqual(TypesetSettings.normalizedFace("lm"), "lm")
        XCTAssertEqual(TypesetSettings.normalizedFace("et"), "et")
        XCTAssertEqual(TypesetSettings.normalizedFace("od"), "od")
        XCTAssertEqual(TypesetSettings.normalizedFace("comic"), "lm")
    }

    func testOptionsClampOpenDyslexicDropCapAndPreview() {
        let o = TypesetSettings.options(on: true, onum: true, hyphens: true, smallCaps: true,
                                        justify: false, face: "od", opening: "dropcap")
        XCTAssertEqual(o["face"] as? String, "od")
        XCTAssertEqual(o["opening"] as? String, "smallcaps")
        let preview = TypesetSettings.options(on: true, onum: true, hyphens: true, smallCaps: true,
                                              justify: false, face: "et", opening: "dropcap", preview: true)
        XCTAssertEqual(preview["opening"] as? String, "none")
        XCTAssertEqual(preview["face"] as? String, "et")
    }

    func testMigrateLegacyToggle() {
        let d = UserDefaults(suiteName: "onyx.tests.typeset.\(UUID().uuidString)")!
        d.set(true, forKey: TypesetSettings.Key.openDyslexicLegacy)
        TypesetSettings.migrateOpenDyslexic(in: d)
        XCTAssertEqual(d.string(forKey: TypesetSettings.Key.face), "od")
        XCTAssertTrue(d.bool(forKey: TypesetSettings.Key.on))
        XCTAssertNil(d.object(forKey: TypesetSettings.Key.openDyslexicLegacy))
    }
}
