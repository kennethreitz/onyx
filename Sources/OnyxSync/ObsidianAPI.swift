import Foundation

/// Obsidian account/vault REST API (`https://api.obsidian.md`). Every call is a JSON POST; a 2xx body
/// containing an `"error"` key is a failure. Endpoints/fields transcribed from Obsidian 1.15.1 `app.js`.
public struct ObsidianAPI: Sendable {
    public struct APIError: Error, CustomStringConvertible { public let message: String; public var description: String { message } }
    public struct HTTPError: Error { public let status: Int }

    public var baseURL: URL
    /// Sent on every request. Obsidian's official headless CLI sends `obsidian-headless/<version>` (set once at
    /// startup via `Jr(...)`); the Electron desktop app sends Chromium's. nil leaves URLSession's default.
    public var userAgent: String?
    public var session: URLSession

    /// The User-Agent of the official `obsidian-headless` 0.0.14 CLI, the client whose signin we mirror.
    public static let headlessUserAgent = "obsidian-headless/0.0.14"
    /// `obsidian-headless` signs in with `{preflight: true, headers: {Origin: "https://obsidian.md"}}`.
    public static let signInOrigin = "https://obsidian.md"

    public init(baseURL: URL = URL(string: "https://api.obsidian.md")!, userAgent: String? = ObsidianAPI.headlessUserAgent,
                session: URLSession = .shared) {
        self.baseURL = baseURL; self.userAgent = userAgent; self.session = session
    }

    /// Thrown by `signIn` when the account has 2FA and no (or an empty) code was sent: the server's error
    /// mentions "2FA code" (but not "2FA code is incorrect"). Prompt for the code and call `signIn` again.
    public static func needsMFA(_ error: Error) -> Bool {
        guard let e = error as? APIError else { return false }
        return e.message.contains("2FA code") && !e.message.contains("2FA code is incorrect")
    }

    public struct SignIn: Decodable, Sendable { public let token: String?; public let email: String?; public let name: String?; public let license: String? }

    public struct RemoteVault: Decodable, Sendable {
        public let id: String
        public let name: String
        public let host: String
        public let salt: String?
        /// Present only for "standard" (managed) encryption; end-to-end vaults omit it and the user types it.
        public let password: String?
        public let encryption_version: Int?
        public let share_uid: String?
        public var isShared: Bool { share_uid?.isEmpty == false }
    }

    public struct VaultList: Decodable, Sendable { public let vaults: [RemoteVault]; public let shared: [RemoteVault]?; public let limit: Int? }
    public struct Region: Decodable, Sendable { public let name: String; public let value: String }
    public struct Regions: Decodable, Sendable { public let regions: [Region] }

    /// Exactly what `obsidian-headless` sends (cli.js `As`): an OPTIONS preflight, then a POST with
    /// `Origin: https://obsidian.md`, `Content-Type: application/json` and body `{email, password, mfa}`.
    /// Values are sent verbatim: no trimming, case-folding or Unicode normalisation. The CLI first sends
    /// `mfa: ""`, and only when the server answers with a "2FA code" error prompts and retries with the code
    /// (see `needsMFA`).
    public func signIn(email: String, password: String, mfa: String = "") async throws -> SignIn {
        try await post("/user/signin", ["email": email, "password": password, "mfa": mfa],
                       preflight: true, headers: ["Origin": Self.signInOrigin])
    }
    public func signOut(token: String) async throws { let _: Empty = try await post("/user/signout", ["token": token]) }
    public func listVaults(token: String, supportedEncryptionVersion: Int = ObsidianCrypto.currentEncryptionVersion) async throws -> VaultList {
        try await post("/vault/list", ["token": token, "supported_encryption_version": supportedEncryptionVersion])
    }
    public func regions(token: String, host: String? = nil) async throws -> Regions {
        var body: [String: Any] = ["token": token]; if let host { body["host"] = host }
        return try await post("/vault/regions", body)
    }
    /// End-to-end: pass `keyhash` and `salt`. Standard (managed) encryption: pass nil for both.
    /// Region "" = automatic.
    public func createVault(token: String, name: String, keyhash: String?, salt: String?, region: String = "",
                            encryptionVersion: Int = ObsidianCrypto.currentEncryptionVersion) async throws -> RemoteVault {
        try await post("/vault/create", ["token": token, "name": name, "keyhash": keyhash as Any? ?? NSNull(),
                                         "salt": salt as Any? ?? NSNull(), "region": region, "encryption_version": encryptionVersion])
    }
    public func deleteVault(token: String, vaultID: String) async throws { let _: Empty = try await post("/vault/delete", ["token": token, "vault_uid": vaultID]) }
    /// Validates the derived key (server compares keyhash) before connecting.
    public func access(token: String, vaultID: String, keyhash: String, host: String, encryptionVersion: Int) async throws {
        let _: Empty = try await post("/vault/access", ["token": token, "vault_uid": vaultID, "keyhash": keyhash,
                                                         "host": host, "encryption_version": encryptionVersion])
    }

    struct Empty: Decodable {}

    /// Mirrors obsidian-headless `z(path, body, {preflight, headers})`.
    func post<T: Decodable>(_ path: String, _ body: [String: Any], preflight: Bool = false, headers: [String: String] = [:]) async throws -> T {
        let url = baseURL.appendingPathComponent(String(path.dropFirst()))
        var common = headers
        if let userAgent { common["User-Agent"] = userAgent }
        if preflight {
            var opt = URLRequest(url: url)
            opt.httpMethod = "OPTIONS"
            for (k, v) in common { opt.setValue(v, forHTTPHeaderField: k) }
            _ = try await session.data(for: opt)   // result ignored, as in the CLI
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        for (k, v) in common { req.setValue(v, forHTTPHeaderField: k) }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.withoutEscapingSlashes])
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw HTTPError(status: http.statusCode) }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let err = obj["error"] {
            throw APIError(message: "\(err)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
