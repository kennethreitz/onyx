// Reader typesetting tests: loads the real Resources/web scripts into a stub DOM and checks
// the HTML Onyx.renders. Run with `node --test Tests/reader` (also part of `make test`).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const web = path.join(path.dirname(fileURLToPath(import.meta.url)), '../../Resources/web');
// Anything the scripts touch at load time: every property is a callable no-op that returns itself.
const stub = () => new Proxy(function () {}, {
  get: (t, k) => k === Symbol.toPrimitive ? () => 0 : k === 'length' ? 0 : stub(),
  apply: () => stub(), construct: () => stub(),
});
const window = { innerHeight: 800, innerWidth: 1000, scrollY: 0, addEventListener() {}, scrollTo() {} };
const ctx = vm.createContext({ window, document: stub(), console, setTimeout, clearTimeout, requestAnimationFrame: f => setTimeout(f, 0),
  getComputedStyle: () => stub(), NodeFilter: { SHOW_COMMENT: 128 }, ResizeObserver: class { observe() {} }, MutationObserver: class { observe() {} } });
ctx.self = ctx.globalThis = ctx; Object.assign(window, { document: ctx.document });
for (const f of ['marked.js', 'marked-footnote.js', 'reader.js']) {
  vm.runInContext(fs.readFileSync(path.join(web, f), 'utf8'), ctx, { filename: f });
  if (f !== 'reader.js') {
    Object.assign(ctx, window);   // UMD builds hang their globals on window/self
    // In a browser globalThis === window; in this vm they are distinct, so the
    // reader would skip marked-footnote unless we attach it to window too.
    if (ctx.marked) window.marked = ctx.marked;
    if (ctx.markedFootnote) window.markedFootnote = ctx.markedFootnote;
  }
}
const html = (md) => ctx.window.Onyx._html(md).replace(/<!--L\d+:\d+-->/g, '');
const marks = (md) => [...ctx.window.Onyx._html(md).matchAll(/<!--L(\d+):(\d+)-->/g)].map(m => [+m[1], +m[2]]);

test('single newlines inside a paragraph are line breaks (Obsidian default)', () => {
  const out = html('**Domain**: Communication\n**Symbol**: ☿\n**Roman Equivalent**: Mercury\n');
  assert.match(out, /<p><strong>Domain<\/strong>: Communication<br>\s*<strong>Symbol<\/strong>: ☿<br>\s*<strong>Roman Equivalent<\/strong>: Mercury<\/p>/);
});

test('blank lines still separate paragraphs', () => {
  const out = html('one\n\ntwo\n');
  assert.equal((out.match(/<p>/g) || []).length, 2);
  assert.doesNotMatch(out, /<br>/);
});

test('lists, tables and code blocks are not broken', () => {
  const list = html('- a\n- b\n- c\n');
  assert.equal((list.match(/<li>/g) || []).length, 3);
  assert.doesNotMatch(list, /<br>/);
  const table = html('| a | b |\n| - | - |\n| 1 | 2 |\n| 3 | 4 |\n');
  assert.match(table, /<table>/);
  assert.equal((table.match(/<tr>/g) || []).length, 3);
  assert.doesNotMatch(table, /<br>/);
  const code = html('```\nline one\nline two\n```\n');
  assert.match(code, /line one\nline two/);
  assert.doesNotMatch(code, /<br>/);
  const indented = html('    x = 1\n    y = 2\n');
  assert.doesNotMatch(indented, /<br>/);
});

test('blockquotes break lines like paragraphs; callouts keep their title', () => {
  const q = html('> first\n> second\n');
  assert.match(q, /<blockquote>\s*<p>first<br>\s*second<\/p>/);
  const c = html('> [!note] Heads up\n> line one\n> line two\n');
  assert.match(c, /class="callout" data-callout="note"/);
  assert.match(c, /callout-title">Heads up\./);
  assert.match(c, /callout-content"><p>line one<br>\s*line two<\/p>/);
  assert.doesNotMatch(c, /Heads up<br>/);
});

test('wikilinks with aliases survive the break', () => {
  const out = html('**Roman Equivalent**: [[Mercury|Mercury]]\n**Next**: x\n');
  assert.match(out, /internal-link[^>]*>Mercury<\/a><br>/);
});

test('source-line markers are unchanged by line breaks (scroll mapping)', () => {
  const md = '# T\n\n**A**: 1\n**B**: 2\n**C**: 3\n\npara\n\n- x\n- y\n';
  assert.deepEqual(marks(md), [[0, 1], [2, 3], [6, 1], [8, 2]]);
});

// --- Footnotes / sidenotes ---------------------------------------------------
// The fixture mirrors the structure of a long essay with five named footnotes
// defined at the end (H1 first, named [^sn-…] refs in body paragraphs, one
// def per line). It is synthetic; it does not use anyone's private text.

const namedFixture = fs.readFileSync(path.join(path.dirname(fileURLToPath(import.meta.url)), 'fixtures/named-sidenotes.md'), 'utf8');

function sectionIndex(out) {
  return out.search(/<section[^>]*class="footnotes"/);
}

test('named footnotes at the end of the source become a notes section after the title, not before it', () => {
  const out = html(namedFixture);
  const fn = sectionIndex(out);
  const h1 = out.indexOf('<h1');
  assert.ok(fn >= 0, 'expected a footnotes section');
  assert.ok(h1 >= 0, 'expected an h1');
  assert.ok(h1 < fn, `footnotes section must come after the title (h1@${h1}, fn@${fn})`);
  assert.equal((out.match(/data-footnote-ref/g) || []).length, 5);
  assert.match(out, /id="footnote-sn-prodromal-signs"/);
  assert.match(out, /id="footnote-sn-malachi-learning"/);
  // definitions should not leak as raw paragraphs
  assert.doesNotMatch(out, /\[\^sn-prodromal-signs\]:/);
});

test('numeric footnotes also stay below the body', () => {
  const out = html('# Num\n\nHello.[^1] There.[^2]\n\n[^1]: first note\n[^2]: second note\n');
  const fn = sectionIndex(out);
  const h1 = out.indexOf('<h1');
  const p = out.indexOf('<p>');
  assert.ok(fn > h1 && fn > p, `section should follow body (h1@${h1}, p@${p}, fn@${fn})`);
  assert.equal((out.match(/data-footnote-ref/g) || []).length, 2);
});

test('multi-paragraph and list-context footnotes still collect at the end', () => {
  const out = html(`# T

A claim in a list:

- first item
- second with a note.[^long]
- third

> A quote with a note.[^q]

[^long]: First paragraph of the note.

    Second paragraph, indented, continues the same note.

[^q]: A short quoted-context note.
`);
  const fn = sectionIndex(out);
  assert.ok(fn > out.indexOf('<h1'), 'section after title');
  assert.ok(fn > out.indexOf('<ul'), 'section after the list');
  assert.ok(fn > out.indexOf('<blockquote'), 'section after the quote');
  assert.equal((out.match(/data-footnote-ref/g) || []).length, 2);
  assert.match(out, /Second paragraph, indented/);
});

test('source-line markers still map the heading and body when footnotes exist', () => {
  const md = '# T\n\nHello.[^1]\n\n[^1]: a note\n';
  const m = marks(md);
  assert.deepEqual(m[0], [0, 1]); // heading at line 0
  assert.ok(m.some(([line]) => line === 2), `expected a marker at line 2, got ${JSON.stringify(m)}`);
  // the collected footnotes section must not steal line 0
  const raw = (md) => ctx.window.Onyx._html(md);
  const out = raw(md);
  assert.doesNotMatch(out, /<!--L0:1--><section/);
  assert.match(out, /<!--L0:1--><h1/);
});

test('canvas cards: fragment renders against the card context, without line markers', () => {
  const out = ctx.window.Onyx.fragment('# Card\nSee [[Hecate]] and ==this==', { links: { hecate: { path: 'AI/Hecate.md', name: 'Hecate' } }, embeds: {} });
  assert.match(out, /<h1>Card<\/h1>/);
  assert.match(out, /data-path="AI\/Hecate\.md"/);
  assert.match(out, /<mark>this<\/mark>/);
  assert.doesNotMatch(out, /<!--L\d/);
  // the reader's own links are untouched afterwards
  assert.doesNotMatch(ctx.window.Onyx._html('[[Hecate]]'), /AI\/Hecate/);
});
