import Network
import XCTest
@testable import OnyxSync

/// A tiny in-memory stand-in for an Obsidian Sync host, speaking the wire protocol as mapped in
/// docs/obsidian-sync-protocol.md. It only ever sees ciphertext paths/hashes/content, like the real server.
final class MockSyncServer: @unchecked Sendable {
    struct Record { var uid: Int; var path: String; var hash: String; var size: Int; var ctime: Int; var mtime: Int; var folder: Bool; var deleted: Bool; var data: Data }
    let listener: NWListener
    let q = DispatchQueue(label: "mock-sync")
    let keyhash: String
    var records: [Record] = []
    var uid = 0
    var log: [[String: Any]] = []
    var conns: [NWConnection] = []
    var port: UInt16 { listener.port!.rawValue }

    init(keyhash: String) throws {
        self.keyhash = keyhash
        let params = NWParameters.tcp
        let ws = NWProtocolWebSocket.Options(); ws.autoReplyPing = true
        ws.maximumMessageSize = 64 * 1024 * 1024
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        listener = try NWListener(using: params, on: .any)
        listener.newConnectionHandler = { [unowned self] c in self.accept(c) }
    }

    func start() async throws {
        let ready = expectationlessReady()
        listener.start(queue: q)
        try await ready()
    }

    private func expectationlessReady() -> () async throws -> Void {
        var cont: CheckedContinuation<Void, Error>?
        var done = false
        listener.stateUpdateHandler = { st in
            if case .ready = st, !done { done = true; cont?.resume() }
            if case .failed(let e) = st, !done { done = true; cont?.resume(throwing: e) }
        }
        return { [q] in
            try await withCheckedThrowingContinuation { c in q.async { if done { c.resume() } else { cont = c } } }
        }
    }

    func stop() { listener.cancel(); conns.forEach { $0.cancel() } }

    private func accept(_ c: NWConnection) {
        conns.append(c)
        var pendingUpload: (meta: [String: Any], pieces: Int, got: Data)?
        func send(_ obj: [String: Any]) {
            let d = try! JSONSerialization.data(withJSONObject: obj)
            let ctx = NWConnection.ContentContext(identifier: "t", metadata: [NWProtocolWebSocket.Metadata(opcode: .text)])
            c.send(content: d, contentContext: ctx, isComplete: true, completion: .idempotent)
        }
        func sendBinary(_ d: Data) {
            let ctx = NWConnection.ContentContext(identifier: "b", metadata: [NWProtocolWebSocket.Metadata(opcode: .binary)])
            c.send(content: d, contentContext: ctx, isComplete: true, completion: .idempotent)
        }
        func announce(_ r: Record) {
            send(["op": "push", "uid": r.uid, "path": r.path, "hash": r.hash, "size": r.size, "ctime": r.ctime, "mtime": r.mtime,
                  "folder": r.folder, "deleted": r.deleted, "device": "mock", "user": 7])
        }
        func store(_ m: [String: Any], data: Data) {
            uid += 1
            let r = Record(uid: uid, path: m["path"] as! String, hash: m["hash"] as? String ?? "", size: data.count,
                           ctime: m["ctime"] as? Int ?? 0, mtime: m["mtime"] as? Int ?? 0, folder: m["folder"] as? Bool ?? false,
                           deleted: m["deleted"] as? Bool ?? false, data: data)
            records.append(r); announce(r)
        }
        func receive() {
            c.receiveMessage { [unowned self] data, ctx, _, err in
                guard err == nil, let data else { return }
                let meta = ctx?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
                if meta?.opcode == .binary, var up = pendingUpload {
                    up.got.append(data); up.pieces -= 1
                    if up.pieces == 0 { pendingUpload = nil; send(["res": "ok"]); store(up.meta, data: up.got) }
                    else { pendingUpload = up; send(["res": "next"]) }
                } else if let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    log.append(m)
                    switch m["op"] as? String {
                    case "init":
                        guard m["keyhash"] as? String == keyhash else { send(["res": "err", "msg": "Invalid encryption key"]); return receive() }
                        send(["res": "ok", "perFileMax": 5_000_000, "userId": 7])
                        let since = m["version"] as? Int ?? 0
                        for r in latest() where r.uid > since { announce(r) }
                        send(["op": "ready", "version": uid])
                    case "ping": send(["op": "pong"])
                    case "push":
                        if m["folder"] as? Bool == true || m["deleted"] as? Bool == true { send(["res": "ok"]); store(m, data: Data()) }
                        else if let last = latest().first(where: { $0.path == m["path"] as? String }), last.hash == m["hash"] as? String, !last.deleted {
                            send(["res": "ok"])   // dedupe: server already has it
                        } else if (m["pieces"] as? Int ?? 0) == 0 { send(["res": "ok"]); store(m, data: Data()) }
                        else { pendingUpload = (m, m["pieces"] as! Int, Data()); send(["res": "next"]) }
                    case "pull":
                        guard let r = records.first(where: { $0.uid == m["uid"] as? Int }) else { send(["err": "Not found"]); return receive() }
                        let pieces = (r.data.count + SyncConnection.pieceSize - 1) / SyncConnection.pieceSize
                        send(["size": r.data.count, "pieces": pieces, "deleted": r.deleted])
                        for i in 0..<pieces { sendBinary(r.data.subdata(in: (i * SyncConnection.pieceSize)..<min((i + 1) * SyncConnection.pieceSize, r.data.count))) }
                    case "history":
                        send(["items": records.filter { $0.path == m["path"] as? String }.reversed().map {
                            ["uid": $0.uid, "path": $0.path, "hash": $0.hash, "size": $0.size, "ts": $0.mtime, "folder": $0.folder, "deleted": $0.deleted, "device": "mock"] as [String: Any] }, "more": false])
                    case "size": send(["res": "ok", "size": records.reduce(0) { $0 + $1.data.count }, "limit": 10_000_000_000])
                    default: send(["err": "unknown op"])
                    }
                }
                receive()
            }
        }
        c.start(queue: q)
        receive()
    }

    private func latest() -> [Record] {
        var byPath: [String: Record] = [:]
        for r in records { byPath[r.path] = r }
        return byPath.values.sorted { $0.uid < $1.uid }
    }

    func snapshot() async -> (records: [Record], log: [[String: Any]]) {
        await withCheckedContinuation { c in q.async { c.resume(returning: (self.records, self.log)) } }
    }
}

final class MockServerTests: XCTestCase {
    let key = Array(Hex.decode("47828e890e26499530026a1d8a709efa527338b8abd7cb7d792cd5f4b1f82b26")!)
    let salt = "0123456789abcdef0123456789abcdef"

    func nextEvent(_ it: inout AsyncStream<SyncEvent>.AsyncIterator, timeout: TimeInterval = 5) async throws -> SyncEvent {
        guard let e = await it.next() else { throw SyncConnectionError.disconnected }
        return e
    }

    func testEndToEndAgainstMockHost() async throws {
        let crypto = try ObsidianV2Provider(key: key, salt: salt)
        let server = try MockSyncServer(keyhash: crypto.keyHash)
        try await server.start()
        defer { server.stop() }
        let url = try SyncConnection.url(forHost: "127.0.0.1:\(server.port)", allowLocal: true)

        // 1. Wrong key is refused at init.
        let wrong = SyncConnection(crypto: try ObsidianV2Provider(key: Array(repeating: 1, count: 32), salt: salt))
        do { try await wrong.connect(url: url, token: "t", vaultID: "v", version: 0, initial: true, device: "Onyx"); XCTFail("should refuse") }
        catch SyncConnectionError.authFailed(let m) { XCTAssertEqual(m, "Invalid encryption key") }

        // 2. Fresh connect: empty backlog → ready(0).
        let conn = SyncConnection(crypto: crypto)
        var events = conn.events.makeAsyncIterator()
        try await conn.connect(url: url, token: "t", vaultID: "v", version: 0, initial: true, device: "Onyx")
        guard case .ready(0) = try await nextEvent(&events) else { return XCTFail("expected ready") }
        let uid = await conn.userID
        XCTAssertEqual(uid, 7)

        // 3. Folder + file upload; the server echoes each as a push the client recognises as its own.
        try await conn.push(path: "Daily", folder: true)
        guard case .push(let f) = try await nextEvent(&events) else { return XCTFail() }
        XCTAssertEqual(f.path, "Daily"); XCTAssertTrue(f.folder)
        let note = Data("# Today\n\nSynced from Onyx ✦\n".utf8)
        try await conn.push(path: "Daily/2026-11-20.md", ctime: 1_763_600_000_000, mtime: 1_763_600_000_500, data: note)
        guard case .push(let up) = try await nextEvent(&events) else { return XCTFail() }
        XCTAssertEqual(up.path, "Daily/2026-11-20.md")
        XCTAssertEqual(up.hash, ObsidianCrypto.contentHash(note))
        // wasJustPushed depends on whether the server echoes before or after its final reply (open question), so not asserted.

        // 4. Re-push identical content: server dedupes (res ok, no upload, no new version).
        try await conn.push(path: "Daily/2026-11-20.md", ctime: 1, mtime: 1_763_600_000_500, data: note)

        // 5. Multi-piece upload (5 MB → 3 pieces) and pull back.
        let big = Data((0..<(5 * 1024 * 1024)).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        try await conn.push(path: "Attachments/blob.bin", mtime: 2, data: big)
        guard case .push(let b) = try await nextEvent(&events) else { return XCTFail() }
        let pulledBig = try await conn.pull(uid: b.uid)
        XCTAssertEqual(pulledBig, big)
        let pulled = try await conn.pull(uid: up.uid)
        XCTAssertEqual(pulled, note)

        // 6. History + delete.
        let hist = try await conn.history(path: "Daily/2026-11-20.md")
        XCTAssertEqual(hist.items.map(\.uid), [up.uid])
        try await conn.push(path: "Attachments/blob.bin", deleted: true)
        guard case .push(let del) = try await nextEvent(&events) else { return XCTFail() }
        XCTAssertTrue(del.deleted)
        await conn.disconnect()

        // 7. The server never saw plaintext.
        let snap = await server.snapshot()
        XCTAssertEqual(snap.records.count, 4)
        for r in snap.records {
            XCTAssertFalse(r.path.contains("Daily") || r.path.contains("blob"), "path must be ciphertext")
            XCTAssertNil(r.data.range(of: Data("Synced from Onyx".utf8)))
        }
        let pushes = snap.log.filter { $0["op"] as? String == "push" }
        XCTAssertEqual(pushes.first?["extension"] as? String, "")
        XCTAssertEqual(pushes[1]["extension"] as? String, "md")
        XCTAssertEqual(pushes[1]["pieces"] as? Int, 1)

        // 8. Reconnect from version 0 on a second device: backlog arrives decrypted, then ready.
        let other = SyncConnection(crypto: try ObsidianCrypto.provider(version: 3, key: key, salt: salt))
        var ev2 = other.events.makeAsyncIterator()
        try await other.connect(url: url, token: "t", vaultID: "v", version: 0, initial: true, device: "Other")
        var seen: [String] = []
        loop: while true {
            switch try await nextEvent(&ev2) {
            case .push(let f): seen.append(f.path + (f.deleted ? " (deleted)" : ""))
            case .ready(let v): XCTAssertEqual(v, 4); break loop
            case .disconnected(let why): return XCTFail(why)
            }
        }
        XCTAssertEqual(seen, ["Daily", "Daily/2026-11-20.md", "Attachments/blob.bin (deleted)"])
        await other.disconnect()
    }
}
