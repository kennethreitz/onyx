import XCTest
@testable import OnyxCore

final class SingleInstanceTests: XCTestCase {
    let packaged = "org.kennethreitz.onyx"

    func testPackagedLaunchTakesOverByDefault() {
        XCTAssertTrue(SingleInstance.shouldTakeOver(environment: [:], bundleIdentifier: packaged))
        XCTAssertFalse(SingleInstance.allowsMultiple(environment: [:]))
    }

    func testAllowMultipleEnvironmentSkipsTakeover() {
        XCTAssertFalse(SingleInstance.shouldTakeOver(
            environment: ["ONYX_ALLOW_MULTIPLE": "1"], bundleIdentifier: packaged))
        XCTAssertTrue(SingleInstance.allowsMultiple(environment: ["ONYX_ALLOW_MULTIPLE": "1"]))
        XCTAssertTrue(SingleInstance.allowsMultiple(environment: ["ONYX_ALLOW_MULTIPLE": "true"]))
        XCTAssertTrue(SingleInstance.allowsMultiple(environment: ["ONYX_ALLOW_MULTIPLE": "YES"]))
        XCTAssertFalse(SingleInstance.allowsMultiple(environment: ["ONYX_ALLOW_MULTIPLE": "0"]))
        XCTAssertFalse(SingleInstance.allowsMultiple(environment: ["ONYX_ALLOW_MULTIPLE": "false"]))
        XCTAssertFalse(SingleInstance.allowsMultiple(environment: ["ONYX_ALLOW_MULTIPLE": "no"]))
        XCTAssertFalse(SingleInstance.allowsMultiple(environment: ["ONYX_ALLOW_MULTIPLE": ""]))
        XCTAssertTrue(SingleInstance.shouldTakeOver(
            environment: ["ONYX_ALLOW_MULTIPLE": "0"], bundleIdentifier: packaged))
    }

    func testHiddenDefaultSkipsTakeover() {
        XCTAssertFalse(SingleInstance.shouldTakeOver(
            environment: [:], defaultsAllowMultiple: true, bundleIdentifier: packaged))
        XCTAssertTrue(SingleInstance.allowsMultiple(environment: [:], defaultsAllowMultiple: true))
        // The env var's "off" values do not override a hidden default of true.
        XCTAssertTrue(SingleInstance.allowsMultiple(
            environment: ["ONYX_ALLOW_MULTIPLE": "0"], defaultsAllowMultiple: true))
    }

    func testEachTestHookSkipsTakeover() {
        for key in SingleInstance.testHookKeys {
            XCTAssertFalse(
                SingleInstance.shouldTakeOver(environment: [key: "1"], bundleIdentifier: packaged),
                "\(key) should skip takeover so a test launch cannot quit a running Onyx")
        }
        XCTAssertEqual(Set(SingleInstance.testHookKeys), [
            "ONYX_NO_DEFAULT_VAULT",
            "ONYX_SHOT_QUIET",
            "ONYX_TYPE_TEST",
            "ONYX_KEY_SELFTEST",
            "ONYX_SCROLL_TEST",
            "ONYX_OPEN_SETTINGS",
            "ONYX_DUMP_MENUS",
            "ONYX_BASES_EDIT",
        ])
    }

    func testUnpackagedBinaryNeverTakesOver() {
        XCTAssertFalse(SingleInstance.shouldTakeOver(environment: [:], bundleIdentifier: nil))
        XCTAssertFalse(SingleInstance.shouldTakeOver(environment: [:], bundleIdentifier: ""))
        XCTAssertFalse(SingleInstance.shouldTakeOver(environment: [:], bundleIdentifier: "  "))
        XCTAssertNil(SingleInstance.bundleIdentifierForTakeover(nil))
        XCTAssertNil(SingleInstance.bundleIdentifierForTakeover(""))
        XCTAssertEqual(SingleInstance.bundleIdentifierForTakeover(packaged), packaged)
        XCTAssertEqual(SingleInstance.bundleIdentifierForTakeover("  org.kennethreitz.onyx\n"), packaged)
    }

    func testQuitTimeoutCoversGitFinishForQuit() {
        // GitSync.finishForQuit waits up to 8s; a shorter handover wait races with those writes.
        XCTAssertGreaterThanOrEqual(SingleInstance.quitTimeout, 8)
        XCTAssertGreaterThanOrEqual(SingleInstance.quitTimeout, 10)
    }

    func testNeverForceTerminatesAStillAliveProcess() {
        XCTAssertFalse(SingleInstance.forceTerminateIfStillAlive)
    }
}
