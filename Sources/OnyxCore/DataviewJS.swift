import Foundation
import JavaScriptCore

/// DataviewJS in a JavaScriptCore sandbox: a `dv` API backed by the vault index,
/// no network and no file writes. Output is collected and rendered as HTML.
public enum DataviewJS {
    public enum Outcome: Sendable {
        case html(String)
        case error(String)
    }

    /// Run a ```dataviewjs block. Output from dv.table/list/taskList/paragraph/header/span/el is concatenated.
    public static func run(_ source: String, in snap: VaultSnapshot, from path: String, now: Date = Date()) -> Outcome {
        let (r, err) = evaluate(source, in: snap, from: path, now: now, expression: false)
        if let err { return .error(err) }
        guard let r else { return .error("DataviewJS returned nothing") }
        if r.html.isEmpty, let v = r.value, v != "undefined", v != "" {
            return .html(Dataview.esc(v))
        }
        return .html(r.html.isEmpty ? "<p class=\"dataview-empty\">No output.</p>" : r.html)
    }

    /// Evaluate an inline `$= expr` and return an HTML snippet.
    public static func evalInline(_ source: String, in snap: VaultSnapshot, from path: String, now: Date = Date()) -> String {
        let (r, err) = evaluate(source, in: snap, from: path, now: now, expression: true)
        if let err { return "<span class=\"dataview-inline-error\">\(Dataview.esc(err))</span>" }
        if let r {
            if !r.html.isEmpty { return r.html }
            return Dataview.esc(r.value ?? "")
        }
        return ""
    }

    struct ScriptResult {
        var html: String
        var value: String?
    }

    static func evaluate(_ source: String, in snap: VaultSnapshot, from path: String, now: Date, expression: Bool) -> (ScriptResult?, String?) {
        let ctx = JSContext()!
        var jsError: String?
        ctx.exceptionHandler = { _, exc in
            jsError = exc?.toString() ?? "JavaScript error"
        }
        let payload: [String: Any] = [
            "pages": snap.sortedNotePaths.compactMap { snap.notes[$0].map { pageJSON($0, snap: snap) } },
            "current": path,
            "now": iso(now),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return (nil, "Couldn’t build the DataviewJS index")
        }
        ctx.evaluateScript(prelude)
        if let jsError { return (nil, jsError) }
        installBridges(ctx, snap: snap, path: path, now: now)
        ctx.evaluateScript("OnyxDV.load(\(jsonLiteral(json)))")
        if let jsError { return (nil, jsError) }

        let wrapped: String
        if expression {
            wrapped = "OnyxDV.runExpr(async function(){ return (\n\(source)\n); })"
        } else {
            wrapped = "OnyxDV.run(async function(){\n\(source)\n})"
        }
        guard let val = ctx.evaluateScript(wrapped) else {
            return (nil, jsError ?? "DataviewJS failed")
        }
        if let jsError { return (nil, jsError) }
        let (settled, promiseError) = awaitPromise(val, in: ctx)
        if let promiseError { return (nil, promiseError) }
        if let jsError { return (nil, jsError) }
        guard let settled, let raw = settled.toString(), let parsed = parseResult(raw) else {
            return (nil, jsError ?? "DataviewJS returned nothing")
        }
        return (parsed, nil)
    }

        static func jsonLiteral(_ s: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [s])
        var t = String(data: data, encoding: .utf8) ?? "[\"\"]"
        t.removeFirst(); t.removeLast()
        return t
    }

    static func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }

    static func pageJSON(_ n: NoteRecord, snap: VaultSnapshot) -> [String: Any] {
        func date(_ d: Date) -> [String: Any] { ["__d": iso(d)] }
        func link(_ path: String, _ name: String) -> [String: Any] { ["__l": path, "name": name] }
        func day(_ d: Date?) -> Any { d.map { date(Calendar.current.startOfDay(for: $0)) } ?? NSNull() }
        var fields: [String: Any] = [:]
        for p in n.summary.frontmatter.properties {
            fields[p.key] = jsonValue(DVValue.from(p.value), snap: snap)
        }
        var inline: [String: [DVValue]] = [:]
        for f in n.summary.fields {
            let v: DVValue
            if f.links.isEmpty { v = DVValue.coerceScalar(f.value) }
            else if f.links.count == 1, let l = f.links.first, let p = snap.resolve(l.target, from: n.path) {
                v = .link(path: p, name: l.alias ?? l.target)
            } else {
                v = .list(f.links.map { l in
                    snap.resolve(l.target, from: n.path).map { DVValue.link(path: $0, name: l.alias ?? l.target) } ?? .string(l.target)
                })
            }
            inline[f.key, default: []].append(v)
        }
        for (k, vs) in inline where fields[k] == nil {
            fields[k] = jsonValue(vs.count == 1 ? vs[0] : .list(vs), snap: snap)
        }
        let outlinks = n.summary.links.compactMap { l -> [String: Any]? in
            guard let p = snap.resolve(l.target, from: n.path) else { return nil }
            return link(p, ((p as NSString).lastPathComponent as NSString).deletingPathExtension)
        }
        let inlinks = (snap.backlinks[n.path] ?? []).sorted().map {
            link($0, (($0 as NSString).lastPathComponent as NSString).deletingPathExtension)
        }
        var tags: [String] = []
        var seen = Set<String>()
        for t in n.summary.tags {
            var acc = ""
            for part in t.split(separator: "/") {
                acc = acc.isEmpty ? String(part) : acc + "/" + part
                if seen.insert(acc).inserted { tags.append("#" + acc) }
            }
        }
        let tasks: [[String: Any]] = Dataview.tasks(in: n).map { t in
            var o: [String: Any] = [
                "text": t.text, "completed": t.completed, "path": t.path,
                "line": t.line, "indexInFile": t.indexInFile, "tags": t.tags,
            ]
            if let d = t.due { o["due"] = date(d) }
            if let d = t.scheduled { o["scheduled"] = date(d) }
            if let d = t.created { o["created"] = date(d) }
            if let d = t.completion { o["completion"] = date(d) }
            return o
        }
        let file: [String: Any] = [
            "name": n.name, "path": n.path, "folder": n.folder, "size": n.size,
            "link": link(n.path, n.name),
            "ctime": date(n.ctime), "mtime": date(n.mtime),
            "cday": date(Calendar.current.startOfDay(for: n.ctime)),
            "mday": date(Calendar.current.startOfDay(for: n.mtime)),
            "day": day(DVDate.fromFileName(n.name)),
            "tags": tags,
            "etags": n.summary.tags.sorted().map { "#" + $0 },
            "aliases": n.aliases,
            "outlinks": outlinks,
            "inlinks": inlinks,
            "tasks": tasks,
        ]
        fields["file"] = file
        fields["__path"] = n.path
        return fields
    }

    static func jsonValue(_ v: DVValue, snap: VaultSnapshot) -> Any {
        switch v {
        case .null: return NSNull()
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b
        case .link(let p, let n): return ["__l": p, "name": n]
        case .page(let p):
            let n = snap.notes[p]?.name ?? ((p as NSString).lastPathComponent as NSString).deletingPathExtension
            return ["__l": p, "name": n]
        case .date(let d, _): return ["__d": iso(d)]
        case .duration(let d): return d.text
        case .list(let l): return l.map { jsonValue($0, snap: snap) }
        case .task(let t): return t.text
        }
    }

    static func parseResult(_ raw: String) -> ScriptResult? {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if obj["error"] is String { return nil }
        let nodes = obj["out"] as? [Any] ?? []
        return ScriptResult(html: render(nodes), value: obj["value"] as? String)
    }

    static let allowedTags: Set<String> = [
        "p", "div", "span", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li",
        "table", "thead", "tbody", "tr", "th", "td", "em", "strong", "br", "hr",
        "a", "blockquote", "code", "pre", "small", "b", "i", "section",
    ]

    static func render(_ nodes: [Any]) -> String {
        nodes.map(renderNode).joined()
    }

    static func renderNode(_ node: Any) -> String {
        guard let d = node as? [String: Any], let t = d["t"] as? String else {
            return Dataview.esc(stringify(node))
        }
        switch t {
        case "p": return "<p>\(Dataview.esc(d["s"] as? String ?? ""))</p>"
        case "h":
            let level = min(max(d["level"] as? Int ?? 2, 1), 6)
            return "<h\(level)>\(Dataview.esc(d["s"] as? String ?? ""))</h\(level)>"
        case "span": return "<span>\(Dataview.esc(d["s"] as? String ?? ""))</span>"
        case "table":
            let headers = (d["headers"] as? [Any] ?? []).map { "<th>\(Dataview.esc(stringify($0)))</th>" }.joined()
            let rows = (d["rows"] as? [Any] ?? []).map { row -> String in
                let cells = (row as? [Any] ?? [row]).map { "<td>\(cell($0))</td>" }.joined()
                return "<tr>\(cells)</tr>"
            }.joined()
            if rows.isEmpty { return "<p class=\"dataview-empty\">No results.</p>" }
            return "<div class=\"table-wrap\"><table class=\"dataview\"><thead><tr>\(headers)</tr></thead><tbody>\(rows)</tbody></table></div>"
        case "list":
            let items = (d["items"] as? [Any] ?? []).map { "<li>\(cell($0))</li>" }.joined()
            return "<ul class=\"dataview-list\">\(items)</ul>"
        case "tasks":
            return renderTasks(d["tasks"] as? [Any] ?? [], group: d["group"] as? Bool ?? true)
        case "el":
            let tag = ((d["tag"] as? String) ?? "div").lowercased()
            guard allowedTags.contains(tag) else { return "<div>\(Dataview.esc(stringify(d["c"] ?? "")))</div>" }
            let content = renderChildren(d["c"])
            if tag == "br" || tag == "hr" { return "<\(tag)>" }
            var attrs = ""
            if tag == "a" {
                if let path = d["path"] as? String, !path.isEmpty {
                    attrs += " class=\"internal-link\" data-path=\"\(Dataview.esc(path))\""
                } else if let href = d["href"] as? String, safeHref(href) {
                    attrs += " href=\"\(Dataview.esc(href))\""
                }
            }
            return "<\(tag)\(attrs)>\(content)</\(tag)>"
        case "style":
            return "<style>\(sanitizeCSS(d["s"] as? String ?? ""))</style>"
        case "html":
            return d["s"] as? String ?? ""
        default:
            return Dataview.esc(stringify(node))
        }
    }

    static func renderChildren(_ c: Any?) -> String {
        if let c = c as? [Any], c.first is [String: Any] { return render(c) }
        if let c = c as? [Any] { return c.map(cell).joined() }
        if let c { return cell(c) }
        return ""
    }

    static func renderTasks(_ tasks: [Any], group: Bool) -> String {
        var parsed: [DVTask] = []
        for t in tasks {
            guard let d = t as? [String: Any] else { continue }
            let text = d["text"] as? String ?? stringify(t)
            let completed = d["completed"] as? Bool ?? false
            let path = d["path"] as? String ?? ""
            let index = d["indexInFile"] as? Int ?? 0
            parsed.append(DVTask(text: text, completed: completed, path: path, line: d["line"] as? Int ?? 0, indexInFile: index))
        }
        if parsed.isEmpty { return "<p class=\"dataview-empty\">No tasks.</p>" }
        if !group {
            return "<ul class=\"dataview-list dataview-tasks\">" + parsed.map(taskItem).joined() + "</ul>"
        }
        var order: [String] = []
        var bucket: [String: [DVTask]] = [:]
        for t in parsed {
            let k = t.path.isEmpty ? "" : t.path
            if bucket[k] == nil { order.append(k) }
            bucket[k, default: []].append(t)
        }
        let groups = order.map { p -> String in
            let name = ((p as NSString).lastPathComponent as NSString).deletingPathExtension
            let title = p.isEmpty ? "" : "<div class=\"dataview-task-title\"><a class=\"internal-link\" data-path=\"\(Dataview.esc(p))\">\(Dataview.esc(name))</a></div>"
            return "<div class=\"dataview-task-group\">\(title)<ul class=\"dataview-list dataview-tasks\">" + (bucket[p] ?? []).map(taskItem).joined() + "</ul></div>"
        }.joined()
        return "<div class=\"dataview-task-list\">\(groups)</div>"
    }

    static func taskItem(_ t: DVTask) -> String {
        let checked = t.completed ? " checked" : ""
        let pathAttr = t.path.isEmpty ? "" : " data-path=\"\(Dataview.esc(t.path))\""
        return "<li class=\"task-list-item\(t.completed ? " is-checked" : "")\"><input type=\"checkbox\" data-dv-task\(pathAttr) data-index=\"\(t.indexInFile)\"\(checked)>\(Dataview.esc(t.text))</li>"
    }

    static func cell(_ v: Any) -> String {
        if v is NSNull { return "" }
        if let d = v as? [String: Any] {
            if let p = d["__l"] as? String {
                return "<a class=\"internal-link\" data-path=\"\(Dataview.esc(p))\">\(Dataview.esc(d["name"] as? String ?? p))</a>"
            }
            if d["t"] != nil { return renderNode(d) }
        }
        if let a = v as? [Any] { return a.map(cell).joined(separator: ", ") }
        return Dataview.esc(stringify(v))
    }

    static func stringify(_ v: Any) -> String {
        if v is NSNull { return "" }
        if let s = v as? String { return s }
        if let n = v as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            return n.stringValue
        }
        if let d = v as? [String: Any], let p = d["__l"] as? String { return d["name"] as? String ?? p }
        if let a = v as? [Any] { return a.map(stringify).joined(separator: ", ") }
        return "\(v)"
    }

    static func safeHref(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces).lowercased()
        if t.isEmpty { return false }
        if t.hasPrefix("javascript:") || t.hasPrefix("data:") || t.hasPrefix("vbscript:") || t.hasPrefix("file:") { return false }
        return true
    }


    static func awaitPromise(_ value: JSValue, in ctx: JSContext, timeout: TimeInterval = 2) -> (JSValue?, String?) {
        if value.isUndefined || value.isNull { return (value, nil) }
        let then = value.objectForKeyedSubscript("then")
        guard let then, then.isObject, !then.isUndefined, !then.isNull else { return (value, nil) }

        var result: JSValue?
        var error: String?
        var done = false
        let onFulfilled: @convention(block) (JSValue?) -> Void = { v in
            result = v
            done = true
        }
        let onRejected: @convention(block) (JSValue?) -> Void = { e in
            error = e?.toString() ?? "Promise rejected"
            done = true
        }
        value.invokeMethod("then", withArguments: [
            JSValue(object: onFulfilled, in: ctx) as Any,
            JSValue(object: onRejected, in: ctx) as Any,
        ])

        let deadline = Date().addingTimeInterval(timeout)
        while !done, Date() < deadline {
            ctx.evaluateScript("void 0")
            if done { break }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.005))
        }
        if !done { return (nil, "DataviewJS timed out waiting for a Promise") }
        if let error { return (nil, error) }
        return (result, nil)
    }

    static func encodeJSON(_ obj: Any) -> String {
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: data, encoding: .utf8) else { return "null" }
        return s
    }

    static func installBridges(_ ctx: JSContext, snap: VaultSnapshot, path: String, now: Date) {
        let pages: @convention(block) (String?) -> String = { src in
            let trimmed = src?.trimmingCharacters(in: .whitespacesAndNewlines)
            let arg: String? = (trimmed == nil || trimmed == "" || trimmed == "undefined" || trimmed == "null") ? nil : src
            do {
                let paths = try Dataview.pagePaths(arg, in: snap, from: path)
                return encodeJSON(paths)
            } catch {
                return encodeJSON(["error": String(describing: error)])
            }
        }
        let load: @convention(block) (String?, String?) -> String? = { raw, origin in
            guard let rel = resolveVaultPath(raw ?? "", origin: origin, current: path, snap: snap) else { return nil }
            return readVaultFile(rel, snap: snap)
        }
        let normalize: @convention(block) (String?, String?) -> String? = { raw, origin in
            normalizeVaultPath(raw ?? "", origin: origin, current: path, snap: snap)
        }
        let csv: @convention(block) (String?, String?) -> String? = { raw, origin in
            guard let rel = resolveVaultPath(raw ?? "", origin: origin, current: path, snap: snap),
                  let text = readVaultFile(rel, snap: snap) else { return nil }
            return encodeJSON(parseCSV(text))
        }
        let view: @convention(block) (String?) -> String = { raw in
            encodeJSON(loadView(raw ?? "", current: path, snap: snap))
        }
        let query: @convention(block) (String?, String?) -> String = { source, file in
            let from = (file?.isEmpty == false && file != "undefined" && file != "null") ? file! : path
            do {
                let r = try Dataview.run(source ?? "", in: snap, from: from, now: now)
                return encodeJSON(["successful": true, "value": queryValue(r, snap: snap)])
            } catch {
                return encodeJSON(["successful": false, "error": String(describing: error)])
            }
        }
        let queryMd: @convention(block) (String?, String?) -> String = { source, file in
            let from = (file?.isEmpty == false && file != "undefined" && file != "null") ? file! : path
            do {
                let r = try Dataview.run(source ?? "", in: snap, from: from, now: now)
                let md = try Dataview.markdown(r)
                return encodeJSON(["successful": true, "value": md])
            } catch {
                return encodeJSON(["successful": false, "error": String(describing: error)])
            }
        }
        let execute: @convention(block) (String?) -> String = { source in
            do {
                return Dataview.html(try Dataview.run(source ?? "", in: snap, from: path, now: now))
            } catch {
                return "<div class=\"dataview-error\"><span>dataview</span> \(Dataview.esc(String(describing: error)))<pre>\(Dataview.esc(source ?? ""))</pre></div>"
            }
        }
        let evaluate: @convention(block) (String?, String?) -> String = { expr, contextJSON in
            do {
                let v = try Dataview.evalExpr(expr ?? "", in: snap, from: path, now: now, bindings: bindings(from: contextJSON))
                return encodeJSON(["successful": true, "value": jsonValue(v, snap: snap)])
            } catch {
                return encodeJSON(["successful": false, "error": String(describing: error)])
            }
        }
        let duration: @convention(block) (String?) -> String? = { text in
            guard let d = DVDuration.parse(text ?? "") else { return nil }
            return encodeJSON([
                "text": d.text,
                "years": d.years, "months": d.months, "weeks": d.weeks,
                "days": d.days, "hours": d.hours, "minutes": d.minutes, "seconds": d.seconds,
            ])
        }
        let parse: @convention(block) (String?) -> String? = { text in
            parseLiteral(text ?? "", snap: snap)
        }
        let markdown: @convention(block) (String?, String?) -> String = { kind, payload in
            markdownFromJS(kind ?? "", payload ?? "", snap: snap)
        }
        ctx.setObject(pages, forKeyedSubscript: "_onyxPages" as NSString)
        ctx.setObject(load, forKeyedSubscript: "_onyxLoad" as NSString)
        ctx.setObject(normalize, forKeyedSubscript: "_onyxNormalize" as NSString)
        ctx.setObject(csv, forKeyedSubscript: "_onyxCSV" as NSString)
        ctx.setObject(view, forKeyedSubscript: "_onyxView" as NSString)
        ctx.setObject(query, forKeyedSubscript: "_onyxQuery" as NSString)
        ctx.setObject(queryMd, forKeyedSubscript: "_onyxQueryMarkdown" as NSString)
        ctx.setObject(execute, forKeyedSubscript: "_onyxExecute" as NSString)
        ctx.setObject(evaluate, forKeyedSubscript: "_onyxEvaluate" as NSString)
        ctx.setObject(duration, forKeyedSubscript: "_onyxDuration" as NSString)
        ctx.setObject(parse, forKeyedSubscript: "_onyxParse" as NSString)
        ctx.setObject(markdown, forKeyedSubscript: "_onyxMarkdown" as NSString)
    }

    static func bindings(from json: String?) -> [String: DVValue] {
        guard let json, let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var out: [String: DVValue] = [:]
        for (k, v) in obj { out[k] = dvValue(v) }
        return out
    }

    static func dvValue(_ v: Any) -> DVValue {
        if v is NSNull { return .null }
        if let n = v as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            return .number(n.doubleValue)
        }
        if let s = v as? String { return DVValue.coerceScalar(s) }
        if let a = v as? [Any] { return .list(a.map(dvValue)) }
        if let d = v as? [String: Any] {
            if let p = d["__l"] as? String { return .link(path: p, name: d["name"] as? String ?? p) }
            if let isoStr = d["__d"] as? String {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = f.date(from: isoStr) ?? ISO8601DateFormatter().date(from: isoStr) {
                    return .date(date, dayOnly: false)
                }
            }
        }
        return .string("\(v)")
    }

    static func queryValue(_ r: DVResult, snap: VaultSnapshot) -> [String: Any] {
        if r.isCalendar {
            let months: [[String: Any]] = r.calendar.map { mon in
                var days: [String: Any] = [:]
                for (d, notes) in mon.days {
                    days[String(d)] = notes.map { jsonValue($0, snap: snap) }
                }
                return ["year": mon.year, "month": mon.month, "days": days]
            }
            return ["type": "calendar", "values": months]
        }
        if r.isTask {
            return ["type": "task", "values": r.taskGroups.flatMap(\.tasks).map { taskJSON($0) }]
        }
        if r.isList {
            let values: [Any] = r.rows.map { row in
                if row.count == 1 { return jsonValue(row[0], snap: snap) }
                return row.map { jsonValue($0, snap: snap) }
            }
            return ["type": "list", "values": values]
        }
        return [
            "type": "table",
            "headers": r.headers,
            "values": r.rows.map { $0.map { jsonValue($0, snap: snap) } },
        ]
    }

    static func taskJSON(_ t: DVTask) -> [String: Any] {
        var o: [String: Any] = [
            "text": t.text, "completed": t.completed, "path": t.path,
            "line": t.line, "indexInFile": t.indexInFile, "tags": t.tags,
        ]
        if let d = t.due { o["due"] = ["__d": iso(d)] }
        if let d = t.scheduled { o["scheduled"] = ["__d": iso(d)] }
        if let d = t.created { o["created"] = ["__d": iso(d)] }
        if let d = t.completion { o["completion"] = ["__d": iso(d)] }
        return o
    }

    static func normalizeRel(_ path: String) -> String? {
        var parts: [String] = []
        for part in path.split(separator: "/").map(String.init) {
            if part.isEmpty || part == "." { continue }
            if part == ".." {
                if parts.isEmpty { return nil }
                parts.removeLast()
                continue
            }
            if part.contains("\0") { return nil }
            parts.append(part)
        }
        return parts.joined(separator: "/")
    }

    static func cleanPathArg(_ raw: String) -> String? {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("[["), t.hasSuffix("]]") {
            t = String(t.dropFirst(2).dropLast(2))
            if let bar = t.firstIndex(of: "|") { t = String(t[..<bar]) }
        }
        t = t.trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t.contains("\0") { return nil }
        if t.hasPrefix("/") || t.hasPrefix("~") || t.hasPrefix("\\") || t.contains("://") { return nil }
        return t
    }

    static func resolveVaultPath(_ raw: String, origin: String?, current: String, snap: VaultSnapshot) -> String? {
        guard let t = cleanPathArg(raw) else { return nil }
        let originPath = (origin?.isEmpty == false && origin != "undefined" && origin != "null") ? origin! : current
        if let resolved = snap.resolve(t, from: originPath), readable(resolved, snap: snap) {
            return sandboxRel(resolved, snap: snap)
        }
        let folder = (originPath as NSString).deletingLastPathComponent
        var candidates: [String] = []
        if t.hasPrefix("./") || t.hasPrefix("../") {
            candidates.append(folder.isEmpty ? t : (folder as NSString).appendingPathComponent(t))
        } else {
            if !folder.isEmpty { candidates.append((folder as NSString).appendingPathComponent(t)) }
            candidates.append(t) // also try vault-root relative
        }
        for combined in candidates {
            guard let normalized = normalizeRel(combined), let rel = sandboxRel(normalized, snap: snap) else { continue }
            if readable(rel, snap: snap) { return rel }
        }
        // Fall back to the first sandbox-legal candidate even if the file is missing (normalize uses this too).
        for combined in candidates {
            if let normalized = normalizeRel(combined), let rel = sandboxRel(normalized, snap: snap) { return rel }
        }
        return nil
    }

    static func readable(_ rel: String, snap: VaultSnapshot) -> Bool {
        if snap.notes[rel] != nil { return true }
        if !rel.hasSuffix(".md"), snap.notes[rel + ".md"] != nil { return true }
        if snap.attachments[rel] != nil { return true }
        let root = snap.root.resolvingSymlinksInPath().standardizedFileURL
        guard FileManager.default.fileExists(atPath: root.path) else { return false }
        let url = root.appendingPathComponent(rel).resolvingSymlinksInPath().standardizedFileURL
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard url.path == root.path || url.path.hasPrefix(prefix) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func normalizeVaultPath(_ raw: String, origin: String?, current: String, snap: VaultSnapshot) -> String? {
        if let resolved = resolveVaultPath(raw, origin: origin, current: current, snap: snap) {
            if snap.notes[resolved] != nil { return resolved }
            if !resolved.hasSuffix(".md"), snap.notes[resolved + ".md"] != nil { return resolved + ".md" }
            return resolved
        }
        guard let t = cleanPathArg(raw) else { return nil }
        let originPath = (origin?.isEmpty == false && origin != "undefined" && origin != "null") ? origin! : current
        let folder = (originPath as NSString).deletingLastPathComponent
        let combined = folder.isEmpty ? t : (folder as NSString).appendingPathComponent(t)
        guard var normalized = normalizeRel(combined) else { return nil }
        if (normalized as NSString).pathExtension.isEmpty { normalized += ".md" }
        return sandboxRel(normalized, snap: snap)
    }

    static func sandboxRel(_ rel: String, snap: VaultSnapshot) -> String? {
        guard let normalized = normalizeRel(rel), !normalized.isEmpty else { return nil }
        let root = snap.root.resolvingSymlinksInPath().standardizedFileURL
        if !FileManager.default.fileExists(atPath: root.path) { return normalized }
        let url = root.appendingPathComponent(normalized).resolvingSymlinksInPath().standardizedFileURL
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        if url.path == root.path || url.path.hasPrefix(prefix) { return normalized }
        return nil
    }

    static func readVaultFile(_ rel: String, snap: VaultSnapshot) -> String? {
        if let n = snap.notes[rel] { return n.content }
        if !rel.hasSuffix(".md"), let n = snap.notes[rel + ".md"] { return n.content }
        guard sandboxRel(rel, snap: snap) != nil else { return nil }
        let root = snap.root.resolvingSymlinksInPath().standardizedFileURL
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }
        let url = root.appendingPathComponent(rel).resolvingSymlinksInPath().standardizedFileURL
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard url.path == root.path || url.path.hasPrefix(prefix) else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func loadView(_ raw: String, current: String, snap: VaultSnapshot) -> [String: String] {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = t.split(separator: "/").map(String.init)
        if parts.contains(where: { $0.hasPrefix(".") && $0 != "." && $0 != ".." }) {
            return ["error": "Dataview: custom view not found for '\(t)/view.js' or '\(t).js'."]
        }
        func file(_ rel: String) -> String? {
            if let path = resolveVaultPath(rel, origin: nil, current: current, snap: snap) {
                return readVaultFile(path, snap: snap)
            }
            if let path = sandboxRel(rel, snap: snap) { return readVaultFile(path, snap: snap) }
            return nil
        }
        let js = file(t + "/view.js") ?? (t.hasSuffix(".js") ? file(t) : file(t + ".js"))
        guard let js else {
            return ["error": "Dataview: custom view not found for '\(t)/view.js' or '\(t).js'."]
        }
        var out = ["js": js]
        if let css = file(t + "/view.css") ?? file((t.hasSuffix(".js") ? String(t.dropLast(3)) : t) + ".css") {
            let clean = sanitizeCSS(css)
            if !clean.isEmpty { out["css"] = clean }
        }
        return out
    }

    static func sanitizeCSS(_ raw: String) -> String {
        var s = raw.replacingOccurrences(of: "</style", with: "", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "<", with: "")
        let patterns = [#"@import\b[^;]*;?"#, #"url\s*\([^)]*\)"#, #"expression\s*\([^)]*\)"#, #"javascript\s*:"#, #"-moz-binding\s*:[^;]*;?"#]
        for pat in patterns {
            s = s.replacingOccurrences(of: pat, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return s
    }

    static func parseCSV(_ text: String) -> [[String: String]] {
        let rows = csvRows(text)
        guard let headers = rows.first, !headers.isEmpty else { return [] }
        return rows.dropFirst().map { row in
            var o: [String: String] = [:]
            for (i, h) in headers.enumerated() { o[h] = i < row.count ? row[i] : "" }
            return o
        }
    }

    static func csvRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if quoted {
                if ch == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 2; continue }
                    quoted = false; i += 1; continue
                }
                field.append(ch); i += 1; continue
            }
            switch ch {
            case "\"": quoted = true; i += 1
            case ",": row.append(field); field = ""; i += 1
            case "\n":
                row.append(field); field = ""
                if !(row.count == 1 && row[0].isEmpty && rows.isEmpty) { rows.append(row) }
                row = []; i += 1
            case "\r":
                i += 1
                if i < chars.count, chars[i] == "\n" { continue }
                row.append(field); field = ""
                if !(row.count == 1 && row[0].isEmpty && rows.isEmpty) { rows.append(row) }
                row = []
            default: field.append(ch); i += 1
            }
        }
        if quoted || !field.isEmpty || !row.isEmpty {
            row.append(field)
            if !(row.count == 1 && row[0].isEmpty && rows.isEmpty) { rows.append(row) }
        }
        return rows
    }

    static func parseLiteral(_ text: String, snap: VaultSnapshot) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("[["), t.hasSuffix("]]") {
            var inner = String(t.dropFirst(2).dropLast(2))
            var name: String? = nil
            if let bar = inner.firstIndex(of: "|") {
                name = String(inner[inner.index(after: bar)...]).trimmingCharacters(in: .whitespaces)
                inner = String(inner[..<bar]).trimmingCharacters(in: .whitespaces)
            }
            let path = snap.resolve(inner, from: nil) ?? inner
            return encodeJSON(["__l": path, "name": name ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension])
        }
        if let d = DVDate.parse(t) { return encodeJSON(["__d": iso(d)]) }
        if let d = DVDuration.parse(t) {
            return encodeJSON([
                "text": d.text,
                "years": d.years, "months": d.months, "weeks": d.weeks,
                "days": d.days, "hours": d.hours, "minutes": d.minutes, "seconds": d.seconds,
                "__dur": true,
            ])
        }
        return nil
    }

    static func markdownFromJS(_ kind: String, _ payload: String, snap: VaultSnapshot) -> String {
        guard let data = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return "" }
        switch kind {
        case "table":
            let d = obj as? [String: Any] ?? [:]
            let headers = (d["headers"] as? [Any] ?? []).map { stringify($0) }
            let values = (d["values"] as? [Any] ?? []).map { row -> [DVValue] in
                (row as? [Any] ?? [row]).map(dvValue)
            }
            return Dataview.markdownTable(headers, values)
        case "list":
            let values = (obj as? [Any] ?? [obj]).map(dvValue)
            return Dataview.markdownList(values)
        case "tasks":
            let tasks = (obj as? [Any] ?? []).compactMap { item -> DVTask? in
                guard let d = item as? [String: Any] else { return nil }
                return DVTask(
                    text: d["text"] as? String ?? stringify(item),
                    completed: d["completed"] as? Bool ?? false,
                    path: d["path"] as? String ?? "",
                    line: d["line"] as? Int ?? 0,
                    indexInFile: d["indexInFile"] as? Int ?? 0
                )
            }
            return Dataview.markdownTaskList(tasks)
        default:
            return ""
        }
    }

    static let prelude = #"""
    var OnyxDV = (function(){
      function revive(v) {
        if (v == null) return v;
        if (Array.isArray(v)) return v.map(revive);
        if (typeof v !== 'object') return v;
        if (typeof v.__d === 'string') { var d = new Date(v.__d); return isNaN(d) ? v.__d : d; }
        if (typeof v.__l === 'string') { v.toString = function(){ return this.name || this.__l; }; return v; }
        var o = Array.isArray(v) ? [] : {};
        Object.keys(v).forEach(function(k){ o[k] = revive(v[k]); });
        return o;
      }
      function cmp(a, b) {
        if (a == null && b == null) return 0;
        if (a == null) return -1;
        if (b == null) return 1;
        if (a instanceof Date && b instanceof Date) return a - b;
        if (typeof a === 'number' && typeof b === 'number') return a - b;
        return String(a).localeCompare(String(b), undefined, { numeric: true, sensitivity: 'base' });
      }
      function keyOf(k) {
        if (k == null) return '∅';
        if (k instanceof Date) return 'd:' + k.toISOString();
        if (typeof k === 'object' && k.__l) return 'l:' + k.__l;
        return 's:' + String(k);
      }
      if (!Array.prototype.where) Array.prototype.where = function(fn){ return this.filter(fn); };
      if (!Array.prototype.sortBy) Array.prototype.sortBy = function(fn){
        return this.slice().sort(function(a,b){ return cmp(fn(a), fn(b)); });
      };
      if (!Array.prototype.groupBy) Array.prototype.groupBy = function(fn){
        var m = [], i, k, rec, x, idx = {};
        for (i = 0; i < this.length; i++) {
          x = this[i]; k = fn(x); rec = keyOf(k);
          if (idx[rec] == null) { idx[rec] = m.length; m.push({ key: k, rows: [] }); }
          m[idx[rec]].rows.push(x);
        }
        return m;
      };
      if (!Array.prototype.limit) Array.prototype.limit = function(n){ return this.slice(0, n); };

      var pages = [], byPath = {}, currentPath = '', now = new Date(), out = [];

      function matchFrom(source, page) {
        if (source == null || String(source).trim() === '') return true;
        var s = String(source).trim();
        var parts = [], tok = '', i, q = '', c;
        function push(){ if (tok.trim()) parts.push(tok.trim()); tok = ''; }
        for (i = 0; i < s.length; i++) {
          c = s[i];
          if (q) { if (c === q) q = ''; tok += c; }
          else if (c === '"' || c === "'") { q = c; tok += c; }
          else if (/\s/.test(c)) push();
          else tok += c;
        }
        push();
        var anyPos = false, hitPos = false, neg = false, p;
        for (i = 0; i < parts.length; i++) {
          p = parts[i];
          if (/^(OR|AND)$/i.test(p)) continue;
          if (p === '-' || p === '!') { neg = true; continue; }
          var raw = p.replace(/^["']|["']$/g, '');
          var ok;
          if (raw.charAt(0) === '#') {
            var tag = raw.slice(1).toLowerCase();
            var tags = (page.file && page.file.etags) || [];
            ok = tags.some(function(t){ t = String(t).replace(/^#/, '').toLowerCase(); return t === tag || t.indexOf(tag + '/') === 0; });
          } else {
            var folder = raw.replace(/\/$/, '');
            ok = page.file.path === folder || page.file.path === folder + '.md' || page.file.path.indexOf(folder + '/') === 0;
          }
          if (neg) { if (ok) return false; neg = false; }
          else { anyPos = true; if (ok) hitPos = true; }
        }
        return !anyPos || hitPos;
      }

      function linkOf(page) {
        if (!page) return null;
        if (page.__l) return page;
        if (page.file && page.file.link) return page.file.link;
        if (page.file) return { __l: page.file.path, name: page.file.name };
        return page;
      }
      function flattenCell(v) {
        if (v == null) return null;
        if (v instanceof Date) return v.toISOString().slice(0, 19).replace('T', ' ');
        if (typeof v === 'object' && v.__l) return v;
        if (Array.isArray(v)) return v.map(flattenCell);
        if (typeof v === 'object' && v.file && v.file.link) return v.file.link;
        return v;
      }

      var dv = {};
      dv.pages = function(source){ return dv.pagePaths(source).map(function(p){ return byPath[p]; }).filter(Boolean); };
      dv.current = function(){ return byPath[currentPath] || null; };
      dv.page = function(path){
        if (!path) return dv.current();
        if (typeof path === 'object' && path.file) return path;
        if (typeof path === 'object' && path.__l) path = path.__l;
        var s = String(path).replace(/\.md$/,'');
        if (byPath[s] || byPath[s + '.md']) return byPath[s] || byPath[s + '.md'];
        var name = s.split('/').pop().toLowerCase();
        var hits = pages.filter(function(p){ return p.file.name.toLowerCase() === name || p.file.path.toLowerCase() === s.toLowerCase() || p.file.path.toLowerCase() === (s + '.md').toLowerCase(); });
        return hits.length === 1 ? hits[0] : (hits[0] || null);
      };
      dv.date = function(x){
        if (x == null || x === '') return new Date(now);
        if (x instanceof Date) return x;
        var s = String(x).toLowerCase();
        if (s === 'now') return new Date(now);
        if (s === 'today') { var d = new Date(now); d.setHours(0,0,0,0); return d; }
        if (s === 'yesterday') { var y = new Date(now); y.setDate(y.getDate()-1); y.setHours(0,0,0,0); return y; }
        if (s === 'tomorrow') { var t = new Date(now); t.setDate(t.getDate()+1); t.setHours(0,0,0,0); return t; }
        var p = new Date(x);
        return isNaN(p) ? null : p;
      };
      dv.paragraph = function(s){ out.push({ t: 'p', s: String(s == null ? '' : s) }); };
      dv.header = function(a, b){
        var level, s;
        if (typeof a === 'number') { level = a; s = b; }
        else { s = a; level = b; }
        out.push({ t: 'h', s: String(s == null ? '' : s), level: level || 2 });
      };
      dv.span = function(s){ out.push({ t: 'span', s: String(s == null ? '' : s) }); };
      dv.table = function(headers, rows){
        out.push({ t: 'table', headers: (headers || []).map(function(h){ return String(h); }), rows: (rows || []).map(function(r){
          return Array.isArray(r) ? r.map(flattenCell) : [flattenCell(r)];
        }) });
      };
      dv.list = function(items){ out.push({ t: 'list', items: (items || []).map(flattenCell) }); };
      dv.taskList = function(tasks, group){
        var list = tasks || [];
        list = list.map(function(t){
          if (t && t.text != null) return t;
          return { text: String(t), completed: false, path: '', indexInFile: 0 };
        });
        out.push({ t: 'tasks', tasks: list, group: group !== false });
      };
      dv.el = function(tag, a, b){
        var node = { t: 'el', tag: String(tag || 'div') };
        var content = (arguments.length >= 3) ? b : a;
        var attrs = (arguments.length >= 3) ? a : null;
        if (attrs && typeof attrs === 'object' && !Array.isArray(attrs)) {
          if (attrs.attr && attrs.attr.href) node.href = String(attrs.attr.href);
          if (attrs.href) node.href = String(attrs.href);
          if (attrs.attr && attrs.attr['data-path']) node.path = String(attrs.attr['data-path']);
        }
        if (content == null) node.c = '';
        else if (Array.isArray(content)) node.c = content.map(flattenCell);
        else if (typeof content === 'object' && content.__l) { node.t = 'el'; node.tag = 'a'; node.path = content.__l; node.c = content.name || content.__l; }
        else node.c = String(content);
        out.push(node);
      };

      dv.pagePaths = function(source){
        var raw = _onyxPages(source == null ? null : String(source));
        var data = JSON.parse(raw);
        if (data && data.error) throw new Error(data.error);
        return data;
      };
      dv.array = function(v){
        if (v == null) return [];
        if (Array.isArray(v)) return v;
        return [v];
      };
      dv.isArray = function(v){ return Array.isArray(v); };
      dv.fileLink = function(path, embed, display){
        var s = String(path || '');
        var name = display == null ? s.split('/').pop().replace(/\.md$/,'') : String(display);
        return { __l: s, name: name, embed: !!embed, toString: function(){ return this.name || this.__l; } };
      };
      dv.sectionLink = function(path, section, embed, display){
        var s = String(path || ''), sec = String(section || '');
        var name = display == null ? (s.split('/').pop().replace(/\.md$/,'') + '#' + sec) : String(display);
        return { __l: s, subpath: '#' + sec, name: name, embed: !!embed, toString: function(){ return this.name || this.__l; } };
      };
      dv.blockLink = function(path, blockId, embed, display){
        return dv.sectionLink(path, '^' + String(blockId || ''), embed, display);
      };
      dv.duration = function(text){
        var raw = _onyxDuration(text == null ? '' : String(text));
        if (!raw) return null;
        var d = JSON.parse(raw);
        d.toString = function(){ return this.text; };
        return d;
      };
      dv.compare = function(a, b){ return cmp(a, b); };
      dv.equal = function(a, b){ return cmp(a, b) === 0; };
      dv.clone = function(v){
        if (v == null || typeof v !== 'object') return v;
        if (v instanceof Date) return new Date(v.getTime());
        if (Array.isArray(v)) return v.map(dv.clone);
        var o = {};
        Object.keys(v).forEach(function(k){ o[k] = dv.clone(v[k]); });
        if (v.__l) o.toString = function(){ return this.name || this.__l; };
        return o;
      };
      dv.parse = function(value){
        if (value == null || typeof value !== 'string') return value;
        var raw = _onyxParse(String(value));
        if (!raw) return value;
        var parsed = JSON.parse(raw);
        if (parsed && parsed.__dur) {
          parsed.toString = function(){ return this.text; };
          return parsed;
        }
        return revive(parsed);
      };
      dv.markdownTable = function(headers, values){
        return _onyxMarkdown('table', JSON.stringify({ headers: headers || [], values: values || [] }));
      };
      dv.markdownList = function(values){
        return _onyxMarkdown('list', JSON.stringify(values || []));
      };
      dv.markdownTaskList = function(tasks){
        return _onyxMarkdown('tasks', JSON.stringify(tasks || []));
      };
      function pathArg(p){
        if (p == null) return '';
        if (typeof p === 'object' && p.__l) return String(p.__l);
        return String(p);
      }
      dv.io = {
        load: function(p, origin){ return Promise.resolve(_onyxLoad(pathArg(p), origin || null)); },
        csv: function(p, origin){
          return Promise.resolve(_onyxCSV(pathArg(p), origin || null)).then(function(raw){
            if (raw == null) return undefined;
            return JSON.parse(raw);
          });
        },
        normalize: function(p, origin){ return _onyxNormalize(pathArg(p), origin || null); }
      };
      var execDepth = 0;
      dv.execute = function(source){
        var html = _onyxExecute(String(source || ''));
        out.push({ t: 'html', s: String(html || '') });
      };
      dv.executeJs = function(source){
        if (execDepth >= 8) throw new Error('DataviewJS executeJs nesting is too deep');
        execDepth++;
        try { return (function(){ return eval(String(source || '')); })(); }
        finally { execDepth--; }
      };
      dv.view = function(path, input){
        return Promise.resolve(_onyxView(String(path || ''))).then(function(raw){
          var info = JSON.parse(raw);
          if (!info || info.error) throw new Error((info && info.error) || 'Dataview: custom view not found');
          if (info.css) out.push({ t: 'style', s: String(info.css) });
          var fn = new Function('dv', 'input', 'return (async function(){\n' + info.js + '\n}).call(this);');
          return fn(dv, input);
        });
      };
      dv.query = function(source, file){
        return Promise.resolve(JSON.parse(_onyxQuery(String(source || ''), file == null ? null : String(file)))).then(function(r){
          if (r && r.successful && r.value) r.value = revive(r.value);
          return r;
        });
      };
      dv.tryQuery = function(source, file){
        return dv.query(source, file).then(function(r){
          if (!r.successful) throw new Error(r.error || 'Query failed');
          return r.value;
        });
      };
      dv.queryMarkdown = function(source, file){
        return Promise.resolve(JSON.parse(_onyxQueryMarkdown(String(source || ''), file == null ? null : String(file))));
      };
      dv.tryQueryMarkdown = function(source, file){
        return dv.queryMarkdown(source, file).then(function(r){
          if (!r.successful) throw new Error(r.error || 'Query failed');
          return r.value;
        });
      };
      dv.evaluate = function(expression, context){
        var ctx = {};
        if (context && typeof context === 'object') {
          Object.keys(context).forEach(function(k){
            var v = context[k];
            if (v instanceof Date) ctx[k] = { __d: v.toISOString() };
            else ctx[k] = v;
          });
        }
        var r = JSON.parse(_onyxEvaluate(String(expression || ''), JSON.stringify(ctx)));
        if (r && r.successful) r.value = revive(r.value);
        return r;
      };
      dv.tryEvaluate = function(expression, context){
        var r = dv.evaluate(expression, context);
        if (!r.successful) throw new Error(r.error || 'Evaluation failed');
        return r.value;
      };
      Object.freeze(dv.io);
      Object.freeze(dv);


      return {
        load: function(json){
          var data = JSON.parse(json);
          currentPath = data.current || '';
          now = data.now ? new Date(data.now) : new Date();
          pages = (data.pages || []).map(revive);
          byPath = {};
          pages.forEach(function(p){ if (p && p.file) byPath[p.file.path] = p; });
          out = [];
          globalThis.dv = dv;
          globalThis.dataview = dv;
        },
        run: function(fn){
          out = [];
          return Promise.resolve(fn(dv)).then(function(){ return Promise.resolve(); }).then(function(){
            return JSON.stringify({ out: out });
          });
        },
        runExpr: function(fn){
          out = [];
          return Promise.resolve(fn(dv)).then(function(v){
            var value = (v == null) ? '' : (v instanceof Date ? v.toISOString() : (typeof v === 'object' && v.__l ? (v.name || v.__l) : String(v)));
            return JSON.stringify({ out: out, value: value });
          });
        }
      };
    })();
    """#

}
