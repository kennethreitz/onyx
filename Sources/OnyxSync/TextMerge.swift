import Foundation
import JavaScriptCore

/// Obsidian Sync's three-way Markdown merge (`sw` in Obsidian 1.15.1):
///
///     diffs = dmp.diff_main(base, local, checklines: true, deadline: 0)
///     if diffs.count > 2 { cleanupSemantic; cleanupEfficiency }
///     return dmp.patch_apply(dmp.patch_make(base, diffs), remote)[0]
///
/// i.e. the local edits since the common base are re-applied as fuzzy patches onto the remote text. Obsidian bundles
/// a port of Google's diff-match-patch; we run the reference JavaScript (Apache-2.0) in JavaScriptCore so the
/// result is byte-identical (fuzzed against Obsidian's own copy: 0 differences in 3,000 random merges).
/// Note `deadline: 0` makes diff_bisect bail at once, so Obsidian's diffs are coarse; that's reproduced too.
public final class TextMerge: @unchecked Sendable {
    public static let shared = TextMerge()
    private let lock = NSLock()
    private let ctx: JSContext
    private let fn: JSValue

    private init() {
        ctx = JSContext()!
        ctx.evaluateScript(diffMatchPatchJS)
        ctx.evaluateScript("""
        function onyxMerge(o, t, e) {
          var i = new diff_match_patch(), r = i.diff_main(o, t, true, 0);
          if (r.length > 2) { i.diff_cleanupSemantic(r); i.diff_cleanupEfficiency(r); }
          var n = i.patch_make(o, r);
          return i.patch_apply(n, e)[0];
        }
        """)
        ctx.evaluateScript("""
        function onyxMergeJSON(l, r) {
          try {
            var a = JSON.parse(l), b = JSON.parse(r);
            if (a && !Array.isArray(a) && typeof a == "object" && b && !Array.isArray(b) && typeof b == "object") {
              for (var k in b) if (Object.prototype.hasOwnProperty.call(b, k)) a[k] = b[k];
              return JSON.stringify(a, undefined, 2);
            }
          } catch (e) {}
          return null;
        }
        function onyxPatchCorePlugins(s) {
          try {
            var i = JSON.parse(s), r = false;
            if (Array.isArray(i)) { if (!i.includes("sync")) { i.push("sync"); r = true; } }
            else if (typeof i == "object" && i.sync !== true) { i.sync = true; r = true; }
            return r ? JSON.stringify(i, null, 2) : s;
          } catch (e) { return s; }
        }
        """)
        fn = ctx.objectForKeyedSubscript("onyxMerge")
    }

    /// Obsidian's config-file conflict rule: shallow-merge remote keys over local, re-serialised with 2-space JSON
    /// (JS key order preserved). nil when either side isn't a JSON object.
    public func mergeJSONObjects(local: String, remote: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let v = ctx.objectForKeyedSubscript("onyxMergeJSON").call(withArguments: [local, remote]), !v.isNull else { return nil }
        return v.toString()
    }

    public func patchCorePlugins(_ s: String) -> String {
        lock.lock(); defer { lock.unlock() }
        return ctx.objectForKeyedSubscript("onyxPatchCorePlugins").call(withArguments: [s])?.toString() ?? s
    }

    /// base = last version both sides agreed on, local = ours now, remote = the incoming server version.
    public func merge(base: String, local: String, remote: String) -> String {
        lock.lock(); defer { lock.unlock() }
        return fn.call(withArguments: [base, local, remote])?.toString() ?? remote
    }
}
