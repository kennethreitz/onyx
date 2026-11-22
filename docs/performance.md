# Performance

Onyx keeps the whole vault in memory as one `VaultSnapshot`: every note's text, its parsed
links, tags, fields and headings, and the indexes built from them (backlinks, unresolved links,
tags, `partOf` and other relations, the sidebar tree). Most of what feels fast or slow comes
down to how often that work is redone, and whether it happens on the main thread.

## Measuring

`onyx-bench` times the work behind launch, saving, switching notes, typing, search, the
inspector, the graph, Dataview and Bases against a real vault. It only reads files, but point
it at a copy, never at the vault you write in:

```sh
rsync -a --exclude .git --exclude .trash --exclude .obsidian/plugins ~/Notes/ /tmp/onyx-bench-vault/
swift run -c release onyx-bench /tmp/onyx-bench-vault 5     # best of 5 runs per row
ONYX_BENCH_JSON=/tmp/bench.json swift run -c release onyx-bench /tmp/onyx-bench-vault
ONYX_BENCH_SCAN=1 swift run -c release onyx-bench /tmp/onyx-bench-vault 1   # cold-open parse breakdown
rm -rf /tmp/onyx-bench-vault
```

Always build with `-c release`; debug builds are 5–20× slower and not representative. Each row
prints the best time of N runs. The biggest note and the most-linked-to note are picked
automatically and printed at the top, since they are the worst cases for typing and backlinks.

The editor's syntax highlighter lives in the app target (it needs AppKit), so it isn't in
`onyx-bench`; its partial restyle is covered by the comparison described below.

## What keeps it fast

- **Saving a note doesn't reindex the vault.** When a note that already exists changes (an
  autosave, or Obsidian Sync or git touching it), only that note's links, tags and relations
  are swapped out of the indexes. New, deleted, moved or renamed files, folders and canvases
  still rebuild everything, because they can change what other notes' links resolve to.
- **Onyx's own saves aren't read back.** The file watcher sees every save Onyx makes. If the
  bytes on disk are what the index already holds, the event is dropped instead of re-reading
  the file and publishing a new snapshot (which would redraw the sidebar and invalidate ⌘O).
- **Full rebuilds resolve links in parallel**, then merge.
- **Search** scores notes in parallel with a byte-level substring search over the already
  lowercased text, and only builds snippets for the results it returns.
- **Backlinks** skip lines that can't link to the note (a link to `Foo.md` must contain "foo",
  or be percent-encoded) instead of parsing every line of every linking note.
- **Line-based parsers** (fences, headings, inline fields) walk one UTF-16 copy of the note
  and only copy out lines that could matter (a `#` at the start, a `` ` `` or `~` after up to
  three spaces, a `::` somewhere in the line).
- **Dataview** builds its date formatters and regular expressions once, rejects values that
  can't be dates before trying six date formats, and skips notes with no `[ ]`/`[x]` in TASK
  queries.
- **Typing in long notes** (30,000+ characters) restyles only the edited lines and the lines
  on either side, unless the edit changes something that reaches further: frontmatter, a code
  fence, a `%%` or `<!-- -->` comment, inline code, or a footnote reference. Then the whole note
  is restyled, as before. The word count and the inspector's outline and properties follow
  long notes about 300 ms after you stop typing; shorter notes update on every keystroke.

## Checking a change keeps behavior identical

Speedups here should never change results. For index, search, backlink and Dataview changes,
build the old and new `OnyxCore` side by side (for example `git archive origin/master
Sources/OnyxCore`), dump every search hit, backlink, Dataview row, quick-switcher result,
per-note summary and the derived indexes after a series of edits against the same vault copy,
and diff the two dumps. `PerformanceTests` covers the same ground on small fixtures (the
incremental reindex is checked against a full rebuild after every edit).
