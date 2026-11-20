import XCTest
@testable import OnyxSync

/// Captures requests instead of hitting the network.
final class CaptureProtocol: URLProtocol {
    struct Seen { let method: String; let url: String; let headers: [String: String]; let body: Data? }
    nonisolated(unsafe) static var seen: [Seen] = []
    nonisolated(unsafe) static var responses: [String] = []   // JSON bodies for successive POSTs

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody
        if body == nil, let s = request.httpBodyStream {
            s.open(); defer { s.close() }
            var d = Data(); var buf = [UInt8](repeating: 0, count: 4096)
            while s.hasBytesAvailable { let n = s.read(&buf, maxLength: buf.count); if n <= 0 { break }; d.append(buf, count: n) }
            body = d
        }
        let method = request.httpMethod ?? "GET"
        Self.seen.append(Seen(method: method, url: request.url!.absoluteString, headers: request.allHTTPHeaderFields ?? [:], body: body))
        let json = method == "POST" && !Self.responses.isEmpty ? Self.responses.removeFirst() : "{}"
        let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class SignInRequestTests: XCTestCase {
    func makeAPI() -> ObsidianAPI {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [CaptureProtocol.self]
        CaptureProtocol.seen = []
        return ObsidianAPI(session: URLSession(configuration: cfg))
    }

    /// Must match obsidian-headless 0.0.14 cli.js:
    /// `z("/user/signin",{email,password,mfa},{preflight:!0,headers:{Origin:"https://obsidian.md"}})`
    /// with `User-Agent: obsidian-headless/0.0.14`, an OPTIONS preflight, then a JSON POST.
    func testSignInMatchesOfficialHeadlessClient() async throws {
        let api = makeAPI()
        CaptureProtocol.responses = [#"{"token":"tok","email":"k@example.com","name":"K"}"#]
        // Deliberately awkward values: must go out byte-for-byte (no trim, no lowercasing, no NFKC).
        let email = " Kenneth@Example.com "
        let password = "pä$$/wörd ｗｉｄｅ \\\"quote\" "   // fullwidth + slash + quotes + trailing space
        let r = try await api.signIn(email: email, password: password, mfa: "")
        XCTAssertEqual(r.token, "tok")

        let seen = CaptureProtocol.seen
        XCTAssertEqual(seen.map(\.method), ["OPTIONS", "POST"])
        XCTAssertEqual(Set(seen.map(\.url)), ["https://api.obsidian.md/user/signin"])
        for s in seen {
            XCTAssertEqual(s.headers["Origin"], "https://obsidian.md")
            XCTAssertEqual(s.headers["User-Agent"], "obsidian-headless/0.0.14")
        }
        XCTAssertNil(seen[0].headers["Content-Type"], "CLI sets Content-Type only on the POST")
        let post = seen[1]
        XCTAssertEqual(post.headers["Content-Type"], "application/json")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(post.body)) as? [String: String])
        XCTAssertEqual(body, ["email": email, "password": password, "mfa": ""])
        XCTAssertFalse(String(decoding: post.body!, as: UTF8.self).contains("\\/"), "no escaped slashes, like JSON.stringify")
    }

    func testTwoStepMFAErrorDetection() async throws {
        let api = makeAPI()
        CaptureProtocol.responses = [#"{"error":"Please enter your 2FA code"}"#]
        do { _ = try await api.signIn(email: "a", password: "b"); XCTFail("expected error") }
        catch { XCTAssertTrue(ObsidianAPI.needsMFA(error)) }
        XCTAssertFalse(ObsidianAPI.needsMFA(ObsidianAPI.APIError(message: "2FA code is incorrect")))
        XCTAssertFalse(ObsidianAPI.needsMFA(ObsidianAPI.APIError(message: "Login failed, please double check your email and password.")))
    }

    func testOtherCallsDoNotPreflight() async throws {
        let api = makeAPI()
        CaptureProtocol.responses = [#"{"vaults":[],"shared":[],"limit":10}"#]
        _ = try await api.listVaults(token: "t")
        XCTAssertEqual(CaptureProtocol.seen.map(\.method), ["POST"])
        XCTAssertNil(CaptureProtocol.seen[0].headers["Origin"])
    }
}
