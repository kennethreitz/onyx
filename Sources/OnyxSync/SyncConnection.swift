import Foundation

/// A file record as the sync server announces it (server `push` messages, `history`, `deleted`),
/// with `path`/`hash` already decrypted.
public struct ServerFile: Sendable, Equatable {
    public var uid: Int
    public var path: String
    public var hash: String
    public var size: Int
    public var ctime: Int
    public var mtime: Int
    public var folder: Bool
    public var deleted: Bool
    public var device: String?
    public var user: Int?
    /// True when this echo is for the push we just made (Obsidian's `justPushed` matching).
    public var wasJustPushed = false
}

public enum SyncEvent: Sendable {
    /// Sent once after `init` when the server has streamed the backlog (`{"op":"ready","version":N}`).
    case ready(version: Int)
    case push(ServerFile)
    case disconnected(String)
}

public enum SyncConnectionError: Error, Equatable {
    case hostNotAllowed(String)
    case authFailed(String)
    case unexpectedHandshake(String)
    case server(String)
    case disconnected
    case timeout
    case badResponse(String)
}

/// JSON object box (JSONSerialization output is not Sendable).
public struct JSONObject: @unchecked Sendable { public let dict: [String: Any]; subscript(_ k: String) -> Any? { dict[k] } }

/// Obsidian Sync websocket client: one in-flight request at a time (Obsidian's queue), JSON text frames
/// for control and raw binary frames for file pieces. Mirrors class `BA` in Obsidian 1.15.1 `app.js`.
public actor SyncConnection {
    public static let pieceSize = 2 * 1024 * 1024
    public nonisolated let events: AsyncStream<SyncEvent>
    private let eventSink: AsyncStream<SyncEvent>.Continuation
    private let crypto: any SyncEncryptionProvider
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var reader: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var lastMessage = Date()
    private var pendingResponse: CheckedContinuation<JSONObject, Error>?
    private var pendingData: CheckedContinuation<Data, Error>?
    private var dataQueue: [Data] = []
    private var serial: Task<Void, Never>?
    private var justPushed: (path: String, folder: Bool, deleted: Bool, mtime: Int, hash: String)?
    public private(set) var perFileMax = 199 * 1024 * 1024
    public private(set) var userID: Int?
    var requestTimeout: TimeInterval = 60

    private let userAgent: String?

    public init(crypto: any SyncEncryptionProvider, session: URLSession = .shared, userAgent: String? = ObsidianAPI.defaultUserAgent) {
        self.crypto = crypto; self.session = session; self.userAgent = userAgent
        (events, eventSink) = AsyncStream.makeStream(of: SyncEvent.self, bufferingPolicy: .unbounded)
    }

    /// `wss://host` for real hosts, `ws://` for 127.0.0.1/localhost (Obsidian's dev-server rule).
    /// Like Obsidian, refuse anything that isn't `*.obsidian.md` unless `allowLocal` and it's loopback.
    public static func url(forHost host: String, allowLocal: Bool = false) throws -> URL {
        let bare = host.replacingOccurrences(of: "^wss?://", with: "", options: .regularExpression)
        let local = bare.hasPrefix("127.0.0.1") || bare.hasPrefix("localhost")
        guard let url = URL(string: (local ? "ws://" : "wss://") + bare), let h = url.host else { throw SyncConnectionError.hostNotAllowed(host) }
        if local { guard allowLocal else { throw SyncConnectionError.hostNotAllowed(host) } }
        else if !h.hasSuffix(".obsidian.md") { throw SyncConnectionError.hostNotAllowed(host) }
        return url
    }

    /// Opens the socket and sends `init`. `version` is the last server uid seen (0 for a fresh vault),
    /// `initial` true on first sync of this device. Returns when the server answers `res: ok`;
    /// the backlog then arrives as `.push` events followed by `.ready`.
    public func connect(url: URL, token: String, vaultID: String, version: Int, initial: Bool, device: String) async throws {
        var req = URLRequest(url: url)
        if let userAgent { req.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
        let t = session.webSocketTask(with: req)
        t.maximumMessageSize = 64 * 1024 * 1024
        task = t
        t.resume()
        try await sendJSON(["op": "init", "token": token, "id": vaultID, "keyhash": crypto.keyHash, "version": version,
                            "initial": initial, "device": device, "encryption_version": crypto.encryptionVersion])
        // Handshake: skip pongs; first real frame must be {res:"ok"}.
        while true {
            let msg = try await t.receive()
            guard case .string(let s) = msg else { throw SyncConnectionError.unexpectedHandshake("Server returned binary") }
            guard let obj = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any] else { throw SyncConnectionError.unexpectedHandshake(s) }
            if obj["op"] as? String == "pong" { continue }
            if obj["status"] as? String == "err" || obj["res"] as? String == "err" { throw SyncConnectionError.authFailed(obj["msg"] as? String ?? s) }
            guard obj["res"] as? String == "ok" else { throw SyncConnectionError.unexpectedHandshake(s) }
            if let m = obj["perFileMax"] as? Int, m >= 0 { perFileMax = m }
            userID = obj["userId"] as? Int
            break
        }
        lastMessage = Date()
        reader = Task { [weak self] in await self?.readLoop() }
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                await self?.beat()
            }
        }
    }

    public var isOpen: Bool { task != nil }

    public func disconnect(reason: String = "Disconnected") {
        guard task != nil else { return }
        task?.cancel(with: .normalClosure, reason: nil); task = nil
        reader?.cancel(); heartbeat?.cancel()
        pendingResponse?.resume(throwing: SyncConnectionError.disconnected); pendingResponse = nil
        pendingData?.resume(throwing: SyncConnectionError.disconnected); pendingData = nil
        eventSink.yield(.disconnected(reason))
    }

    // MARK: - Operations

    /// Download one version by server uid. nil if that version is a deletion.
    public func pull(uid: Int) async throws -> Data? {
        try await serially { c in
            c.dataQueue.removeAll()
            let r = try await c.request(["op": "pull", "uid": uid])
            if r["deleted"] as? Bool == true { return nil }
            let size = r["size"] as? Int ?? 0, pieces = r["pieces"] as? Int ?? 0
            var buf = Data(capacity: size)
            for _ in 0..<pieces { buf.append(try await c.nextData()) }
            return buf.isEmpty ? buf : Data(try c.crypto.decrypt(Array(buf)))
        }
    }

    /// Upload a file, create a folder, or record a deletion. `relatedPath` is the previous path on rename.
    /// For files, `data` is plaintext; hash/size/pieces are computed here.
    public func push(path: String, relatedPath: String? = nil, folder: Bool = false, deleted: Bool = false,
                     ctime: Int = 0, mtime: Int = 0, data: Data? = nil) async throws {
        try await serially { c in
            let encPath = try c.crypto.encodeString(path)
            let encRelated: Any = try relatedPath.map { try c.crypto.encodeString($0) } ?? NSNull()
            let ext = folder ? "" : Self.fileExtension(path)
            if folder || deleted {
                c.justPushed = (encPath, folder, deleted, 0, "")
                _ = try await c.request(["op": "push", "path": encPath, "relatedpath": encRelated, "extension": ext,
                                            "hash": "", "ctime": 0, "mtime": 0, "folder": folder, "deleted": deleted])
                return
            }
            let plain = data ?? Data()
            // Obsidian always sends the (deterministically encrypted) SHA-256 of the plaintext for files,
            // including empty ones; "" only for folders and deletions.
            let encHash = try c.crypto.encodeString(ObsidianCrypto.contentHash(plain))
            let body: [UInt8] = plain.isEmpty ? [] : try c.crypto.encrypt(Array(plain))
            let pieces = (body.count + Self.pieceSize - 1) / Self.pieceSize
            c.justPushed = (encPath, false, false, mtime, encHash)
            let r = try await c.request(["op": "push", "path": encPath, "relatedpath": encRelated, "extension": ext,
                                            "hash": encHash, "ctime": ctime, "mtime": mtime, "folder": false, "deleted": false,
                                            "size": body.count, "pieces": pieces])
            if r["res"] as? String == "ok" { c.justPushed = nil; return }   // server already has this content
            for i in 0..<pieces {
                let lo = i * Self.pieceSize, hi = min(lo + Self.pieceSize, body.count)
                _ = try await c.sendBinaryAndAwait(Data(body[lo..<hi]))
            }
            c.justPushed = nil
        }
    }

    public func size() async throws -> JSONObject { try await serially { c in try await c.request(["op": "size"]) } }
    public func usernames() async throws -> JSONObject { try await serially { c in try await c.request(["op": "usernames"]) } }
    public func restore(uid: Int) async throws -> JSONObject { try await serially { c in try await c.request(["op": "restore", "uid": uid]) } }

    /// Version history of one path. `last` is the uid to page back from (nil = newest).
    public func history(path: String, last: Int? = nil) async throws -> (items: [ServerFile], raw: JSONObject) {
        try await serially { c in
            let r = try await c.request(["op": "history", "path": try c.crypto.encodeString(path), "last": last as Any? ?? NSNull()])
            let items = try (r["items"] as? [[String: Any]] ?? []).map { try c.decodeFile($0) }
            return (items, r)
        }
    }

    /// Deleted files on the server (renames suppressed, as Obsidian asks).
    public func deleted() async throws -> [ServerFile] {
        try await serially { c in
            let r = try await c.request(["op": "deleted", "suppressrenames": true])
            return try (r["items"] as? [[String: Any]] ?? []).map { try c.decodeFile($0) }
        }
    }

    // MARK: - Plumbing

    static func fileExtension(_ path: String) -> String {
        let base = path.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? path
        guard let dot = base.lastIndex(of: "."), dot != base.startIndex, base.index(after: dot) != base.endIndex else { return "" }
        return base[base.index(after: dot)...].lowercased()
    }

    func decodeFile(_ d: [String: Any]) throws -> ServerFile {
        let encPath = d["path"] as? String ?? ""
        let encHash = d["hash"] as? String ?? ""
        return ServerFile(uid: d["uid"] as? Int ?? 0,
                          path: encPath.isEmpty ? "" : try crypto.decodeString(encPath),
                          hash: encHash.isEmpty ? "" : try crypto.decodeString(encHash),
                          size: d["size"] as? Int ?? 0, ctime: d["ctime"] as? Int ?? 0, mtime: d["mtime"] as? Int ?? 0,
                          folder: d["folder"] as? Bool ?? false, deleted: d["deleted"] as? Bool ?? false,
                          device: d["device"] as? String, user: d["user"] as? Int)
    }

    /// Runs `op` after every previously queued operation finishes (Obsidian's one-request-at-a-time queue).
    private func serially<T: Sendable>(_ op: @escaping @Sendable (isolated SyncConnection) async throws -> T) async throws -> T {
        let prev = serial
        let t = Task { () async throws -> T in
            await prev?.value
            return try await op(self)
        }
        serial = Task { _ = try? await t.value }
        return try await t.value
    }

    private func request(_ body: [String: Any]) async throws -> JSONObject {
        guard task != nil else { throw SyncConnectionError.disconnected }
        let timeout = requestTimeout
        let r: JSONObject = try await withCheckedThrowingContinuation { c in
            pendingResponse = c
            Task {
                do { try await self.sendJSON(body) } catch { self.failResponse(error) }
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self.timeoutIfStill(c)
            }
        }
        if let err = r["err"] { throw SyncConnectionError.server("\(err)") }
        return r
    }

    private func sendBinaryAndAwait(_ d: Data) async throws -> JSONObject {
        try await withCheckedThrowingContinuation { c in
            pendingResponse = c
            Task {
                do { try await self.task?.send(.data(d)) } catch { self.failResponse(error) }
            }
        }
    }

    private func failResponse(_ e: Error) { pendingResponse?.resume(throwing: e); pendingResponse = nil }
    private func timeoutIfStill(_ c: CheckedContinuation<JSONObject, Error>) {
        // Continuations aren't Equatable; only time out if nothing has answered since.
        if pendingResponse != nil, Date().timeIntervalSince(lastMessage) >= requestTimeout {
            pendingResponse?.resume(throwing: SyncConnectionError.timeout); pendingResponse = nil
            disconnect(reason: "Timeout")
        }
    }

    private func nextData() async throws -> Data {
        if !dataQueue.isEmpty { return dataQueue.removeFirst() }
        return try await withCheckedThrowingContinuation { pendingData = $0 }
    }

    private func sendJSON(_ obj: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: obj)
        try await task?.send(.string(String(decoding: data, as: UTF8.self)))
    }

    private func beat() async {
        let idle = Date().timeIntervalSince(lastMessage)
        if idle > 120 { disconnect(reason: "Heartbeat timeout"); return }
        if idle > 10 { try? await sendJSON(["op": "ping"]) }
    }

    private func readLoop() async {
        while let t = task, !Task.isCancelled {
            do {
                let msg = try await t.receive()
                handle(msg)
            } catch {
                disconnect(reason: error.localizedDescription); return
            }
        }
    }

    private func handle(_ msg: URLSessionWebSocketTask.Message) {
        lastMessage = Date()
        switch msg {
        case .data(let d):
            if let c = pendingData { pendingData = nil; c.resume(returning: d) } else { dataQueue.append(d) }
        case .string(let s):
            guard let obj = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any] else { disconnect(reason: "Bad JSON"); return }
            switch obj["op"] as? String {
            case "pong": return
            case "ready": eventSink.yield(.ready(version: obj["version"] as? Int ?? 0))
            case "push":
                do {
                    var f = try decodeFile(obj)
                    if let j = justPushed, j.path == obj["path"] as? String, j.folder == f.folder, j.deleted == f.deleted,
                       j.mtime == f.mtime, j.hash == (obj["hash"] as? String ?? "") { justPushed = nil; f.wasJustPushed = true }
                    eventSink.yield(.push(f))
                } catch { eventSink.yield(.disconnected("Undecryptable push: \(error)")) }
            default:
                if let c = pendingResponse { pendingResponse = nil; c.resume(returning: JSONObject(dict: obj)) }
            }
        @unknown default: break
        }
    }
}
