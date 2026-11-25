import Foundation
import os

/// Signing in to Obsidian, shared by the Mac and iOS apps. Idempotent: a token we already hold is checked and
/// reused; a stale one is signed out and cleared first; "Already logged in" is retried once with a clean
/// state; and a Keychain failure after the server said yes never loses the token for this session.
public struct SyncSignIn: Sendable {
    public enum Outcome: Equatable, Sendable {
        /// Signed in. `persisted` is false when the token couldn't be stored (it's kept in memory only).
        case signedIn(token: String, email: String, persisted: Bool)
        /// The account has 2FA: ask for the code and call again with it.
        case needsCode
    }

    public let api: ObsidianAPI
    public let store: any SecretStore
    public let log: @Sendable (String) -> Void

    public init(api: ObsidianAPI, store: any SecretStore, log: @escaping @Sendable (String) -> Void = SyncSignIn.defaultLog) {
        self.api = api; self.store = store; self.log = log
    }

    static let logger = Logger(subsystem: "org.kennethreitz.onyx", category: "sync")
    public static let defaultLog: @Sendable (String) -> Void = { msg in logger.notice("\(msg, privacy: .public)") }

    /// - Parameter heldToken: a token from an earlier attempt this session (e.g. one the Keychain refused).
    public func signIn(email: String, password: String, code: String?, heldToken: String? = nil) async throws -> Outcome {
        // 1. A token we already have: reuse it if the server still accepts it (as `ob login` does).
        if let existing = heldToken ?? store.token {
            do {
                let info = try await api.userInfo(token: existing)
                log("sign-in: reusing the existing session")
                let persisted = store.token == existing || persist(existing)
                return .signedIn(token: existing, email: info.email ?? email, persisted: persisted)
            } catch {
                log("sign-in: existing token rejected (\(Self.detail(error))); signing out and clearing it")
                try? await api.signOut(token: existing)
                store.remove("token")
            }
        }
        // 2. Sign in; on "Already logged in", retry once from a clean slate.
        var retried = false
        while true {
            do {
                let r = try await api.signIn(email: email, password: password, mfa: code ?? "")
                guard let t = r.token, !t.isEmpty else { throw ObsidianAPI.APIError(message: "No token in the sign-in response") }
                return .signedIn(token: t, email: r.email ?? email, persisted: persist(t))
            } catch where code == nil && ObsidianAPI.needsMFA(error) {
                return .needsCode
            } catch where ObsidianAPI.isAlreadyLoggedIn(error) && !retried {
                retried = true
                log("sign-in: server says already logged in; clearing local state and retrying once")
                store.remove("token")
                continue
            }
        }
    }

    /// Store the token; on failure keep going (the caller holds it in memory) and log why.
    private func persist(_ token: String) -> Bool {
        do { try store.set("token", Data(token.utf8)); return true }
        catch { log("sign-in: couldn't store the token (\(Self.detail(error))); keeping it for this session only"); return false }
    }

    /// Full details for the log (never shown to the user).
    public static func detail(_ error: Error) -> String {
        let ns = error as NSError
        return "\(String(reflecting: error)) [\(ns.domain) \(ns.code)]"
    }
}

/// Human-readable text for sync and sign-in errors (no raw NSError domains). Details go to the log.
public enum SyncErrorText {
    public static func describe(_ error: Error, log: @Sendable (String) -> Void = SyncSignIn.defaultLog) -> String {
        log("error: \(SyncSignIn.detail(error))")
        switch error {
        case let e as ObsidianAPI.APIError:
            if ObsidianAPI.isAlreadyLoggedIn(e) { return "Obsidian says this device is already signed in. Try again; Onyx will start a fresh session." }
            if e.message.contains("2FA code is incorrect") { return "That 2FA code didn’t work. Check your authenticator and try again." }
            return e.message   // the server's own sentence, e.g. "Login failed, please double check your email and password."
        case let e as ObsidianAPI.HTTPError:
            switch e.status {
            case 401, 403: return "Obsidian didn’t accept this session. Sign out and sign in again."
            case 429: return "Obsidian is rate-limiting sign-ins. Wait a minute and try again."
            case 500...599: return "Obsidian’s server had a problem (HTTP \(e.status)). Try again in a moment."
            default: return "Obsidian’s server refused the request (HTTP \(e.status))."
            }
        case let e as KeychainError:
            return keychainText(e.status)
        case let e as URLError:
            switch e.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: return "You’re offline. Connect to the internet and try again."
            case .timedOut: return "Obsidian’s server took too long to answer. Try again."
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed: return "Couldn’t reach Obsidian’s server. Check your connection, VPN, or firewall."
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid,
                 .serverCertificateHasUnknownRoot, .clientCertificateRejected, .appTransportSecurityRequiresSecureConnection:
                return "Couldn’t make a secure connection to Obsidian’s server."
            case .cancelled: return "Cancelled."
            default: return "Network problem talking to Obsidian (\(e.code.rawValue))."
            }
        case is DecodingError:
            return "Obsidian’s server sent a reply Onyx didn’t understand. Try again, or check for an Onyx update."
        default:
            let ns = error as NSError
            if ns.domain == NSOSStatusErrorDomain { return keychainText(OSStatus(ns.code)) }
            if ns.domain == NSURLErrorDomain { return describe(URLError(URLError.Code(rawValue: ns.code)), log: { _ in }) }
            if ns.domain.hasPrefix("OnyxSync") || ns.domain.hasPrefix("OnyxCore") {   // our own errors read well
                let s = String(describing: error)
                if !s.contains("Domain=") && !s.contains("error -") { return s }
            }
            return "Something went wrong (\(ns.domain.split(separator: ".").last.map(String.init) ?? ns.domain) \(ns.code)). Details are in the log."
        }
    }

    static func keychainText(_ status: OSStatus) -> String {
        switch status {
        case -34018: return "This build of Onyx can’t use the Keychain (missing entitlement). Onyx keeps the sign-in in a protected file instead; try again."
        case -25308: return "The Keychain is locked. Unlock your device and try again."
        case -128: return "Keychain access was cancelled."
        case -25293, -25294: return "The Keychain refused access. Check Keychain Access for Onyx’s entries (md.onyx.sync)."
        default: return "The Keychain couldn’t save Onyx’s sign-in (error \(status))."
        }
    }
}
