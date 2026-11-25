import XCTest
@testable import OnyxSync

/// A secret store whose writes always fail with the given OSStatus (e.g. -34018 in an unsigned simulator build).
final class FailingStore: SecretStore, @unchecked Sendable {
    let status: OSStatus
    init(_ status: OSStatus) { self.status = status }
    func get(_ account: String) -> Data? { nil }
    func set(_ account: String, _ value: Data) throws { throw KeychainError(status: status) }
    func remove(_ account: String) {}
}

/// Sign-in against the fake Obsidian REST host (CaptureProtocol): idempotent retries, "Already logged in",
/// stale tokens, and Keychain failures. No real account, Keychain, or network.
final class SyncSignInTests: XCTestCase {
    var tmp: URL!
    override func setUp() {
        tmp = URL(fileURLWithPath: "/tmp/onyx-signin-tests-\(UUID().uuidString)")
        CaptureProtocol.seen = []; CaptureProtocol.responses = []
    }
    override func tearDown() { try? FileManager.default.removeItem(at: tmp) }

    func api() -> ObsidianAPI {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [CaptureProtocol.self]
        return ObsidianAPI(baseURL: URL(string: "https://api.example.invalid")!, session: URLSession(configuration: cfg))
    }
    var posts: [String] { CaptureProtocol.seen.filter { $0.method == "POST" }.map { URL(string: $0.url)!.path } }
    let quiet: @Sendable (String) -> Void = { _ in }

    func testAlreadyLoggedInIsRetriedOnceFromACleanState() async throws {
        let store = MemoryStore()
        CaptureProtocol.responses = [#"{"error":"Already logged in"}"#, #"{"token":"fresh","email":"k@example.com"}"#]
        let r = try await SyncSignIn(api: api(), store: store, log: quiet).signIn(email: "k@example.com", password: "pw", code: nil)
        XCTAssertEqual(r, .signedIn(token: "fresh", email: "k@example.com", persisted: true))
        XCTAssertEqual(posts, ["/user/signin", "/user/signin"])
        XCTAssertEqual(store.token, "fresh")
    }

    func testAlreadyLoggedInTwiceBecomesAReadableError() async throws {
        CaptureProtocol.responses = [#"{"error":"Already logged in"}"#, #"{"error":"Already logged in"}"#]
        do {
            _ = try await SyncSignIn(api: api(), store: MemoryStore(), log: quiet).signIn(email: "k@example.com", password: "pw", code: nil)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(posts.count, 2, "retried exactly once")
            let text = SyncErrorText.describe(error, log: quiet)
            XCTAssertTrue(text.hasPrefix("Obsidian says this device is already signed in"), text)
        }
    }

    func testAWorkingStoredTokenIsReusedWithoutSigningInAgain() async throws {
        let store = MemoryStore(); try store.set("token", Data("held".utf8))
        CaptureProtocol.responses = [#"{"name":"K","email":"k@example.com"}"#]
        let r = try await SyncSignIn(api: api(), store: store, log: quiet).signIn(email: "k@example.com", password: "pw", code: nil)
        XCTAssertEqual(r, .signedIn(token: "held", email: "k@example.com", persisted: true))
        XCTAssertEqual(posts, ["/user/info"])
    }

    func testAStaleTokenIsSignedOutAndClearedFirst() async throws {
        let store = MemoryStore(); try store.set("token", Data("stale".utf8))
        CaptureProtocol.responses = [#"{"error":"Not logged in"}"#, "{}", #"{"token":"new","email":"k@example.com"}"#]
        let r = try await SyncSignIn(api: api(), store: store, log: quiet).signIn(email: "k@example.com", password: "pw", code: nil)
        XCTAssertEqual(r, .signedIn(token: "new", email: "k@example.com", persisted: true))
        XCTAssertEqual(posts, ["/user/info", "/user/signout", "/user/signin"])
        XCTAssertEqual(store.token, "new")
    }

    func testTwoFactorStillAsksForTheCode() async throws {
        CaptureProtocol.responses = [#"{"error":"Please enter your 2FA code"}"#]
        let r = try await SyncSignIn(api: api(), store: MemoryStore(), log: quiet).signIn(email: "k@example.com", password: "pw", code: nil)
        XCTAssertEqual(r, .needsCode)
    }

    func testMissingKeychainEntitlementFallsBackToAProtectedFile() async throws {
        let file = FileSecretStore(dir: tmp)
        var notes: [String] = []
        let lock = NSLock()
        let store = ResilientSecretStore(primary: FailingStore(-34018), fallback: file, onFallback: { m in lock.lock(); notes.append(m); lock.unlock() })
        CaptureProtocol.responses = [#"{"token":"tok","email":"k@example.com"}"#]
        let r = try await SyncSignIn(api: api(), store: store, log: quiet).signIn(email: "k@example.com", password: "pw", code: nil)
        XCTAssertEqual(r, .signedIn(token: "tok", email: "k@example.com", persisted: true))
        XCTAssertEqual(store.token, "tok")
        XCTAssertEqual(file.token, "tok")
        let perms = try FileManager.default.attributesOfItem(atPath: tmp.appendingPathComponent("token").path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
        XCTAssertEqual(notes.count, 1)
        store.remove("token")
        XCTAssertNil(store.token)
    }

    func testOtherKeychainFailuresAreThrownNotHidden() {
        let store = ResilientSecretStore(primary: FailingStore(-25308), fallback: FileSecretStore(dir: tmp))
        XCTAssertThrowsError(try store.set("token", Data("x".utf8))) { e in XCTAssertEqual(e as? KeychainError, KeychainError(status: -25308)) }
        XCTAssertNil(FileSecretStore(dir: tmp).token, "no file fallback for a locked Keychain")
    }

    /// The simulator bug: the server said yes, the Keychain said no. The token is kept for the session, and the
    /// next attempt reuses it instead of wedging on "Already logged in".
    func testKeychainFailureAfterSignInDoesNotWedgeTheNextAttempt() async throws {
        let store = FailingStore(-25308)
        CaptureProtocol.responses = [#"{"token":"tok","email":"k@example.com"}"#]
        let first = try await SyncSignIn(api: api(), store: store, log: quiet).signIn(email: "k@example.com", password: "pw", code: nil)
        XCTAssertEqual(first, .signedIn(token: "tok", email: "k@example.com", persisted: false))

        CaptureProtocol.seen = []
        CaptureProtocol.responses = [#"{"name":"K","email":"k@example.com"}"#]
        let again = try await SyncSignIn(api: api(), store: store, log: quiet).signIn(email: "k@example.com", password: "pw", code: nil, heldToken: "tok")
        XCTAssertEqual(again, .signedIn(token: "tok", email: "k@example.com", persisted: false))
        XCTAssertEqual(posts, ["/user/info"], "no second sign-in")
    }

    func testErrorTextNeverShowsRawDomains() {
        let errors: [Error] = [
            NSError(domain: NSOSStatusErrorDomain, code: -34018), KeychainError(status: -34018), KeychainError(status: -25308),
            URLError(.notConnectedToInternet), NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut),
            URLError(.secureConnectionFailed), URLError(.appTransportSecurityRequiresSecureConnection),
            ObsidianAPI.HTTPError(status: 503), ObsidianAPI.HTTPError(status: 401),
            DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "x")),
            NSError(domain: "com.example.Weird", code: 7, userInfo: [NSLocalizedDescriptionKey: "The operation couldn’t be completed. (com.example.Weird error 7.)"]),
        ]
        for e in errors {
            let t = SyncErrorText.describe(e, log: quiet)
            XCTAssertFalse(t.contains("Domain"), t)
            XCTAssertFalse(t.contains("NSOSStatusErrorDomain"), t)
            XCTAssertFalse(t.contains("couldn’t be completed"), t)
            XCTAssertFalse(t.isEmpty)
        }
        XCTAssertTrue(SyncErrorText.describe(KeychainError(status: -34018), log: quiet).contains("Keychain"))
        XCTAssertEqual(SyncErrorText.describe(ObsidianAPI.APIError(message: "Login failed, please double check your email and password."), log: quiet),
                       "Login failed, please double check your email and password.")
    }

    func testAPISessionKeepsNoCookies() {
        let c = ObsidianAPI.makeSession().configuration
        XCTAssertFalse(c.httpShouldSetCookies)
        XCTAssertNil(c.httpCookieStorage)
        XCTAssertEqual(c.httpCookieAcceptPolicy, .never)
    }
}
