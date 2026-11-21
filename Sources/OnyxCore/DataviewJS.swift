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
        ctx.evaluateScript("OnyxDV.load(\(jsonLiteral(json)))")
        if let jsError { return (nil, jsError) }

        let wrapped: String
        if expression {
            wrapped = "OnyxDV.runExpr(function(){ return (\n\(source)\n); })"
        } else {
            wrapped = "OnyxDV.run(function(){\n\(source)\n})"
        }
        guard let val = ctx.evaluateScript(wrapped) else {
            return (nil, jsError ?? "DataviewJS failed")
        }
        if let jsError { return (nil, jsError) }
        guard let raw = val.toString(), let parsed = parseResult(raw) else {
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
      dv.pages = function(source){ return pages.filter(function(p){ return matchFrom(source, p); }); };
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
      dv.header = function(s, level){ out.push({ t: 'h', s: String(s == null ? '' : s), level: level || 2 }); };
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
        },
        run: function(fn){
          out = [];
          fn(dv);
          return JSON.stringify({ out: out });
        },
        runExpr: function(fn){
          out = [];
          var v = fn(dv);
          var value = (v == null) ? '' : (v instanceof Date ? v.toISOString() : (typeof v === 'object' && v.__l ? (v.name || v.__l) : String(v)));
          return JSON.stringify({ out: out, value: value });
        }
      };
    })();
    """#

}
